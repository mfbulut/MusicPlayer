package fx

import win "core:sys/windows"

WINHTTP_ACCESS_TYPE_DEFAULT_PROXY :: 0
WINHTTP_FLAG_SECURE :: 0x00800000
WINHTTP_QUERY_STATUS_CODE :: 19
WINHTTP_QUERY_FLAG_NUMBER :: 0x20000000

INTERNET_SCHEME_HTTPS :: 2
INTERNET_SCHEME_HTTP :: 1

HINTERNET :: rawptr

URL_COMPONENTS :: struct {
    dwStructSize: win.DWORD,
    lpszScheme: ^u16,
    dwSchemeLength: win.DWORD,
    nScheme: i32,
    lpszHostName: ^u16,
    dwHostNameLength: win.DWORD,
    nPort: u16,
    lpszUserName: ^u16,
    dwUserNameLength: win.DWORD,
    lpszPassword: ^u16,
    dwPasswordLength: win.DWORD,
    lpszUrlPath: ^u16,
    dwUrlPathLength: win.DWORD,
    lpszExtraInfo: ^u16,
    dwExtraInfoLength: win.DWORD,
}

foreign import winhttp "system:winhttp.lib"

@(default_calling_convention="stdcall")
foreign winhttp {
    WinHttpOpen :: proc(pwszAgent: ^u16, dwAccessType: win.DWORD,
                       pwszProxy: ^u16, pwszProxyBypass: ^u16,
                       dwFlags: win.DWORD) -> HINTERNET ---

    WinHttpConnect :: proc(hSession: HINTERNET, pswzServerName: ^u16,
                          nServerPort: u16, dwReserved: win.DWORD) -> HINTERNET ---

    WinHttpOpenRequest :: proc(hConnect: HINTERNET, pwszVerb: ^u16,
                              pwszObjectName: ^u16, pwszVersion: ^u16,
                              pwszReferrer: ^u16, ppwszAcceptTypes: ^^u16,
                              dwFlags: win.DWORD) -> HINTERNET ---

    WinHttpSendRequest :: proc(hRequest: HINTERNET, lpszHeaders: ^u16,
                              dwHeadersLength: win.DWORD, lpOptional: rawptr,
                              dwOptionalLength: win.DWORD, dwTotalLength: win.DWORD,
                              dwContext: rawptr) -> win.BOOL ---

    WinHttpReceiveResponse :: proc(hRequest: HINTERNET, lpReserved: rawptr) -> win.BOOL ---

    WinHttpCloseHandle :: proc(hInternet: HINTERNET) -> win.BOOL ---

    WinHttpCrackUrl :: proc(pwszUrl: ^u16, dwUrlLength: win.DWORD,
                           dwFlags: win.DWORD, lpUrlComponents: ^URL_COMPONENTS) -> win.BOOL ---

    WinHttpQueryHeaders :: proc(hRequest: HINTERNET, dwInfoLevel: win.DWORD,
                               pwszName: ^u16, lpBuffer: rawptr,
                               lpdwBufferLength: ^win.DWORD, lpdwIndex: ^win.DWORD) -> win.BOOL ---

    WinHttpQueryDataAvailable :: proc(hRequest: HINTERNET, lpdwNumberOfBytesAvailable: ^win.DWORD) -> win.BOOL ---

    WinHttpReadData :: proc(hRequest: HINTERNET, lpBuffer: rawptr,
                           dwNumberOfBytesToRead: win.DWORD, lpdwNumberOfBytesRead: ^win.DWORD) -> win.BOOL ---
}

Response :: struct {
    status: i32,
    data: []u8,
}

get :: proc(url: string) -> Response {
    result := Response{0, nil}

    url_wstring := win.utf8_to_wstring(url)

    urlComp := URL_COMPONENTS{}
    hostName := make([]u16, 256)
    urlPath := make([]u16, 1024)
    defer delete(hostName)
    defer delete(urlPath)

    urlComp.dwStructSize = win.DWORD(size_of(URL_COMPONENTS))
    urlComp.lpszHostName = raw_data(hostName)
    urlComp.dwHostNameLength = win.DWORD(len(hostName))
    urlComp.lpszUrlPath = raw_data(urlPath)
    urlComp.dwUrlPathLength = win.DWORD(len(urlPath))

    if !WinHttpCrackUrl(url_wstring, 0, 0, &urlComp) {
        return result
    }

    userAgent := win.utf8_to_wstring("WinHTTP Odin Client/1.0")

    hSession := WinHttpOpen(userAgent,
                           WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
                           nil, nil, 0)
    if hSession == nil do return result
    defer WinHttpCloseHandle(hSession)

    hConnect := WinHttpConnect(hSession, urlComp.lpszHostName, urlComp.nPort, 0)
    if hConnect == nil do return result
    defer WinHttpCloseHandle(hConnect)

    flags := urlComp.nScheme == INTERNET_SCHEME_HTTPS ? WINHTTP_FLAG_SECURE : 0
    verb := win.utf8_to_wstring("GET")

    hRequest := WinHttpOpenRequest(hConnect, verb,
                                  urlComp.lpszUrlPath, nil,
                                  nil, nil,
                                  win.DWORD(flags))
    if hRequest == nil do return result
    defer WinHttpCloseHandle(hRequest)

    if !WinHttpSendRequest(hRequest,
                          nil, 0,
                          nil, 0, 0, nil) {
        return result
    }

    if !WinHttpReceiveResponse(hRequest, nil) {
        return result
    }

    status_code: win.DWORD = 0
    status_len := win.DWORD(size_of(win.DWORD))

    WinHttpQueryHeaders(hRequest,
                       WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                       nil, &status_code, &status_len, nil)

    result.status = i32(status_code)

    totalSize: win.DWORD = 0
    buffer: []u8

    for {
        chunkSize: win.DWORD = 0
        if !WinHttpQueryDataAvailable(hRequest, &chunkSize) || chunkSize == 0 {
            break
        }

        old_len := len(buffer)
        new_buffer := make([]u8, old_len + int(chunkSize))
        copy(new_buffer[:old_len], buffer)
        delete(buffer)
        buffer = new_buffer

        bytesRead: win.DWORD = 0
        if !WinHttpReadData(hRequest, raw_data(buffer[old_len:]), chunkSize, &bytesRead) {
            delete(buffer)
            buffer = nil
            break
        }

        if int(bytesRead) < int(chunkSize) {
            final_buffer := make([]u8, old_len + int(bytesRead))
            copy(final_buffer, buffer[:old_len + int(bytesRead)])
            delete(buffer)
            buffer = final_buffer
        }

        totalSize += bytesRead
    }

    result.data = buffer
    return result
}