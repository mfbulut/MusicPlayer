package fx

import "base:runtime"
import "core:net"
import "core:slice"
import "core:strings"

import win "core:sys/windows"

WINHTTP_ACCESS_TYPE_DEFAULT_PROXY :: 0
WINHTTP_FLAG_SECURE :: 0x00800000
WINHTTP_QUERY_STATUS_CODE :: 19
WINHTTP_QUERY_FLAG_NUMBER :: 0x20000000

INTERNET_SCHEME_HTTPS :: 2
INTERNET_SCHEME_HTTP :: 1

HINTERNET :: rawptr

URL_COMPONENTS :: struct {
	dwStructSize:      win.DWORD,
	lpszScheme:        [^]u16,
	dwSchemeLength:    win.DWORD,
	nScheme:           i32,
	lpszHostName:      [^]u16,
	dwHostNameLength:  win.DWORD,
	nPort:             u16,
	lpszUserName:      [^]u16,
	dwUserNameLength:  win.DWORD,
	lpszPassword:      [^]u16,
	dwPasswordLength:  win.DWORD,
	lpszUrlPath:       [^]u16,
	dwUrlPathLength:   win.DWORD,
	lpszExtraInfo:     [^]u16,
	dwExtraInfoLength: win.DWORD,
}

foreign import winhttp "system:winhttp.lib"

@(default_calling_convention = "stdcall")
foreign winhttp {
	WinHttpOpen :: proc(pwszAgent: ^u16, dwAccessType: win.DWORD, pwszProxy: ^u16, pwszProxyBypass: ^u16, dwFlags: win.DWORD) -> HINTERNET ---

	WinHttpConnect :: proc(hSession: HINTERNET, pswzServerName: ^u16, nServerPort: u16, dwReserved: win.DWORD) -> HINTERNET ---

	WinHttpOpenRequest :: proc(hConnect: HINTERNET, pwszVerb: ^u16, pwszObjectName: ^u16, pwszVersion: ^u16, pwszReferrer: ^u16, ppwszAcceptTypes: ^^u16, dwFlags: win.DWORD) -> HINTERNET ---

	WinHttpSendRequest :: proc(hRequest: HINTERNET, lpszHeaders: ^u16, dwHeadersLength: win.DWORD, lpOptional: rawptr, dwOptionalLength: win.DWORD, dwTotalLength: win.DWORD, dwContext: rawptr) -> win.BOOL ---

	WinHttpReceiveResponse :: proc(hRequest: HINTERNET, lpReserved: rawptr) -> win.BOOL ---

	WinHttpCloseHandle :: proc(hInternet: HINTERNET) -> win.BOOL ---

	WinHttpCrackUrl :: proc(pwszUrl: cstring16, dwUrlLength: win.DWORD, dwFlags: win.DWORD, lpUrlComponents: ^URL_COMPONENTS) -> win.BOOL ---

	WinHttpQueryHeaders :: proc(hRequest: HINTERNET, dwInfoLevel: win.DWORD, pwszName: ^u16, lpBuffer: rawptr, lpdwBufferLength: ^win.DWORD, lpdwIndex: ^win.DWORD) -> win.BOOL ---

	WinHttpQueryDataAvailable :: proc(hRequest: HINTERNET, lpdwNumberOfBytesAvailable: ^win.DWORD) -> win.BOOL ---

	WinHttpReadData :: proc(hRequest: HINTERNET, lpBuffer: rawptr, dwNumberOfBytesToRead: win.DWORD, lpdwNumberOfBytesRead: ^win.DWORD) -> win.BOOL ---
}

Request_Query_Param :: struct {
	key, value: string,
}

Response :: struct {
	status: i32,
	data:   []u8,
}

get :: proc(
	scheme_hostname_path: string,
	opts: []Request_Query_Param,
	allocator := context.allocator,
) -> (
	result: Response,
	ok: bool,
) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	urlComp := URL_COMPONENTS{}
	hostName := make([]u16, 256, context.temp_allocator)
	urlPath := make([]u16, 1024, context.temp_allocator)

	// WinHttp has facilities for escaping (ICU_ESCAPE), but sadly without support for >1 "extra infos".
	// That is, parameters containing an "&" or "?" need be escaped manually first anyways..!
	urlExtras: strings.Builder
	strings.builder_init(&urlExtras, context.temp_allocator)
	for opt, i in opts {
		strings.write_rune(&urlExtras, i > 0 ? '&' : '?')
		strings.write_string(&urlExtras, opt.key)
		strings.write_rune(&urlExtras, '=')
		strings.write_string(&urlExtras, net.percent_encode(opt.value, context.temp_allocator))
	}

	urlComp.dwStructSize = win.DWORD(size_of(URL_COMPONENTS))
	urlComp.lpszHostName = raw_data(hostName)
	urlComp.dwHostNameLength = win.DWORD(len(hostName))
	urlComp.lpszUrlPath = raw_data(urlPath)
	urlComp.dwUrlPathLength = win.DWORD(len(urlPath))

	url_wstring := win.utf8_to_wstring(scheme_hostname_path)
	WinHttpCrackUrl(url_wstring, 0, 0, &urlComp) or_return

	// This is a no-op for requests without query parameters.
	lpszUrlPathWithParams := slice.concatenate(
		[][]u16 {
			urlComp.lpszUrlPath[:urlComp.dwUrlPathLength],
			win.utf8_to_utf16(strings.to_string(urlExtras)),
			win.L("")[:1],
		},
		context.temp_allocator,
	)

	userAgent := win.L("github.com/mfbulut/MusicPlayer WinHTTP Client/1.0")

	hSession := WinHttpOpen(userAgent, WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, nil, nil, 0)
	(hSession != nil) or_return
	defer WinHttpCloseHandle(hSession)

	hConnect := WinHttpConnect(hSession, urlComp.lpszHostName, urlComp.nPort, 0)
	(hConnect != nil) or_return
	defer WinHttpCloseHandle(hConnect)

	flags := urlComp.nScheme == INTERNET_SCHEME_HTTPS ? WINHTTP_FLAG_SECURE : 0
	verb := win.L("GET")

	hRequest := WinHttpOpenRequest(
		hConnect,
		verb,
		raw_data(lpszUrlPathWithParams),
		nil,
		nil,
		nil,
		win.DWORD(flags),
	)
	(hRequest != nil) or_return
	defer WinHttpCloseHandle(hRequest)

	WinHttpSendRequest(hRequest, nil, 0, nil, 0, 0, nil) or_return

	WinHttpReceiveResponse(hRequest, nil) or_return

	status_code: win.DWORD = 0
	status_len := win.DWORD(size_of(win.DWORD))

	WinHttpQueryHeaders(
		hRequest,
		WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
		nil,
		&status_code,
		&status_len,
		nil,
	)

	result.status = i32(status_code)

	totalSize: win.DWORD = 0
	buffer := make([dynamic]byte, context.temp_allocator)

	for {
		chunkSize: win.DWORD = 0
		WinHttpQueryDataAvailable(hRequest, &chunkSize) or_break
		(chunkSize > 0) or_break

		resize(&buffer, totalSize + chunkSize)

		bytesRead: win.DWORD = 0
		WinHttpReadData(hRequest, raw_data(buffer[totalSize:]), chunkSize, &bytesRead) or_break
		totalSize += bytesRead
	}

	result.data = slice.clone(buffer[:totalSize], allocator)
	return result, true
}
