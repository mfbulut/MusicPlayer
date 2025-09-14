package fx

import "base:runtime"
import "core:mem"
import "core:strings"
import "core:time"
import "core:unicode/utf8"

import win "core:sys/windows"

chroma_key :: Color{0, 0, 0, 0}

window_styles :: win.WS_OVERLAPPEDWINDOW | win.WS_VISIBLE

HOTKEY_NEXT :: 1001
HOTKEY_PREV :: 1002
HOTKEY_PLAY_PAUSE :: 1003

init_windows :: proc(title: string, width, height: int) {
	win_title := win.utf8_to_wstring(title)

	// win.SetProcessDPIAware() // TODO(furkan) add dpi aware scaling

	instance := win.HINSTANCE(win.GetModuleHandleW(nil))
	class_name : cstring16 = "Window Class"

	cls := win.WNDCLASSEXW{
	    cbSize        = size_of(win.WNDCLASSEXW),
	    lpfnWndProc   = win_proc,
	    lpszClassName = class_name,
	    hInstance     = instance,
	    hCursor       = win.LoadCursorA(nil, win.IDC_ARROW),
	    hIcon         = load_icon_by_size(256),
	    hIconSm       = load_icon_by_size(32),
	    style         = win.CS_HREDRAW | win.CS_VREDRAW,
	}

	win.RegisterClassExW(&cls)

	screen_width := win.GetSystemMetrics(win.SM_CXSCREEN)
	screen_height := win.GetSystemMetrics(win.SM_CYSCREEN)

	x := (screen_width - i32(width)) / 2
	y := (screen_height - i32(height)) / 2

	rect: win.RECT = {
		left   = 0,
		top    = 0,
		right  = i32(width),
		bottom = i32(height),
	}

	win.AdjustWindowRectEx(&rect, window_styles, win.FALSE, 0)

	adjusted_width := rect.right - rect.left
	adjusted_height := rect.bottom - rect.top

	ctx.window.w = int(adjusted_width)
	ctx.window.h = int(adjusted_height)

	ctx.hwnd = win.CreateWindowExW(
		win.WS_EX_LAYERED,
		class_name,
		win_title,
		window_styles,
		x,
		y,
		adjusted_width,
		adjusted_height,
		nil,
		nil,
		instance,
		nil,
	)

	win.RegisterHotKey(ctx.hwnd, HOTKEY_NEXT, 0, u32(Key.MEDIA_NEXT_TRACK))
	win.RegisterHotKey(ctx.hwnd, HOTKEY_PREV, 0, u32(Key.MEDIA_PREV_TRACK))
	win.RegisterHotKey(ctx.hwnd, HOTKEY_PLAY_PAUSE, 0, u32(Key.MEDIA_PLAY_PAUSE))
}

load_icon_by_size :: proc(size: i32) -> win.HICON {
    icon := win.LoadImageW(
        win.HANDLE(win.GetModuleHandleW(nil)),
        transmute(cstring16)win.MAKEINTRESOURCEW(1), // icon resource ID 1
        win.IMAGE_ICON,
        size,
        size,
        win.LR_DEFAULTCOLOR,
    );
    return win.HICON(icon);
}

@(private)
switch_button :: #force_inline proc(x: u32) -> Mouse {
	switch x {
	case win.WM_RBUTTONDOWN, win.WM_RBUTTONUP:
		return .RIGHT
	case win.WM_MBUTTONDOWN, win.WM_MBUTTONUP:
		return .MIDDLE
	}
	return .LEFT
}

@(private)
switch_keys :: #force_inline proc(virtual_code: u32, lparam: int) -> u32 {
	switch virtual_code {
	case win.VK_SHIFT:
		return win.MapVirtualKeyW(u32((lparam & 0x00ff0000) >> 16), win.MAPVK_VSC_TO_VK_EX)
	case win.VK_CONTROL:
		return (lparam & 0x01000000) != 0 ? win.VK_RCONTROL : win.VK_LCONTROL
	case win.VK_MENU:
		return (lparam & 0x01000000) != 0 ? win.VK_RMENU : win.VK_LMENU
	}
	return virtual_code
}

drop_callback :: proc(callback: proc(files: []string)) {
	ctx.file_drop_callback = callback

	if ctx.hwnd != nil {
		win.DragAcceptFiles(ctx.hwnd, win.TRUE)
	}
}

get_clipboard :: proc(allocator := context.temp_allocator) -> (text: string, ok: bool) {
	win.OpenClipboard(ctx.hwnd) or_return
	defer win.CloseClipboard()

	win.IsClipboardFormatAvailable(win.CF_UNICODETEXT) or_return

	handle := win.GetClipboardData(win.CF_UNICODETEXT)
	(handle != nil) or_return

	global := win.HGLOBAL(handle)

	ptr := win.GlobalLock(global)
	(ptr != nil) or_return
	defer win.GlobalUnlock(global)

	// Should limit the length, clipboard data is untrusted.
	str_utf8, allocator_err := win.wstring_to_utf8(win.wstring(ptr), -1, allocator)
	(allocator_err == nil) or_return

	return str_utf8, true
}

set_clipboard :: proc(text: string) -> (ok: bool) {
	win.OpenClipboard(ctx.hwnd) or_return
	defer win.CloseClipboard()

	text := win.utf8_to_utf16(text, context.temp_allocator)
	(text != nil) or_return

	data := win.GlobalAlloc(win.GMEM_MOVEABLE, len(text) * size_of(win.WCHAR) + 2)
	(data != nil) or_return
	defer if !ok {win.GlobalFree(data)}

	{
		data := cast([^]byte)win.GlobalLock(win.HGLOBAL(data))
		(data != nil) or_return
		defer win.GlobalUnlock(win.HGLOBAL(data))
		mem.copy_non_overlapping(data, raw_data(text), len(text) * size_of(win.WCHAR))
		data[len(text) * size_of(win.WCHAR) + 0] = 0
		data[len(text) * size_of(win.WCHAR) + 1] = 0
	}

	ret := win.SetClipboardData(win.CF_UNICODETEXT, win.HANDLE(data))
	(ret != nil) or_return

	return true
}

side_bar_w := 200

set_sidebar_size :: proc(w: int) {
	side_bar_w = w
}

@(private)
is_in_title_bar :: proc(x, y: int) -> bool {
	title_bar_left := side_bar_w
	title_bar_right := ctx.window.w - 150

	title_bar_height := 30

	if ctx.compact_mode {
		return (y >= title_bar_height || x < title_bar_right)
	}

	return y < title_bar_height && x >= title_bar_left && x < title_bar_right
}

@(private)
win_proc :: proc "stdcall" (
	hwnd: win.HWND,
	message: win.UINT,
	wparam: win.WPARAM,
	lparam: win.LPARAM,
) -> win.LRESULT {
	context = runtime.default_context()

	switch message {
	case win.WM_KEYDOWN, win.WM_SYSKEYDOWN:
		if lparam & (1 << 30) != 0 do break
		code := switch_keys(u32(wparam), lparam)
		ctx.key_state[code] = KEY_STATE_HELD | KEY_STATE_PRESSED

	case win.WM_KEYUP, win.WM_SYSKEYUP:
		code := switch_keys(u32(wparam), lparam)
		ctx.key_state[code] &= ~KEY_STATE_HELD
		ctx.key_state[code] |= KEY_STATE_RELEASED
	case win.WM_HOTKEY:
		hotkey_id := win.LOWORD(wparam)

		key: Key
		switch hotkey_id {
		case HOTKEY_NEXT:
			key = .MEDIA_NEXT_TRACK
		case HOTKEY_PREV:
			key = .MEDIA_PREV_TRACK
		case HOTKEY_PLAY_PAUSE:
			key = .MEDIA_PLAY_PAUSE
		}

		ctx.key_state[key] = KEY_STATE_HELD | KEY_STATE_PRESSED

	case win.WM_LBUTTONDOWN, win.WM_RBUTTONDOWN, win.WM_MBUTTONDOWN:
		button := switch_button(message)

		if message == win.WM_LBUTTONDOWN {
			resize_area := get_resize_area(ctx.mouse_pos.x, ctx.mouse_pos.y)

			if resize_area != .NONE {
				if !ctx.compact_mode {
					ctx.is_resizing = true
					ctx.resize_state = resize_area

					point: win.POINT
					win.GetCursorPos(&point)

					rect: win.RECT
					win.GetWindowRect(ctx.hwnd, &rect)

					switch resize_area {
					case .LEFT, .TOP_LEFT, .BOTTOM_LEFT:
						ctx.resize_mouse_offset.x = point.x - rect.left
					case .RIGHT, .TOP_RIGHT, .BOTTOM_RIGHT:
						ctx.resize_mouse_offset.x = point.x - rect.right
					case .TOP, .BOTTOM:
						ctx.resize_mouse_offset.x = 0
					case .NONE:
					}

					switch resize_area {
					case .TOP, .TOP_LEFT, .TOP_RIGHT:
						ctx.resize_mouse_offset.y = point.y - rect.top
					case .BOTTOM, .BOTTOM_LEFT, .BOTTOM_RIGHT:
						ctx.resize_mouse_offset.y = point.y - rect.bottom
					case .LEFT, .RIGHT:
						ctx.resize_mouse_offset.y = 0
					case .NONE:
					}
				}

				win.SetCapture(hwnd)
				ctx.mouse_state[button] = KEY_STATE_HELD | KEY_STATE_PRESSED

				break
			}

			if is_in_title_bar(ctx.mouse_pos.x, ctx.mouse_pos.y) {
				current_time := time.now()
				time_diff := f32(
					time.duration_seconds(time.diff(ctx.last_click_time, current_time)),
				)

				if ctx.compact_mode {
					ctx.mouse_state[button] = KEY_STATE_HELD | KEY_STATE_PRESSED
				}

				if time_diff <= 0.2 && !ctx.compact_mode &&
				   abs(ctx.mouse_pos.x - ctx.last_click_pos.x) <= 5 &&
				   abs(ctx.mouse_pos.y - ctx.last_click_pos.y) <= 5 {

					maximize_or_restore_window()

					ctx.last_click_time = {}
					ctx.last_click_pos = {}
				} else {
					if !ctx.is_resizing {
						win.SendMessageW(hwnd, win.WM_NCLBUTTONDOWN, win.HTCAPTION, 0)

						ctx.last_click_time = current_time
						ctx.last_click_pos = ctx.mouse_pos
					}
				}
			} else {
				win.SetCapture(hwnd)
				ctx.mouse_state[button] = KEY_STATE_HELD | KEY_STATE_PRESSED
			}
		} else {
			win.SetCapture(hwnd)
			ctx.mouse_state[button] = KEY_STATE_HELD | KEY_STATE_PRESSED
		}

	case win.WM_LBUTTONUP, win.WM_RBUTTONUP, win.WM_MBUTTONUP:
		button := switch_button(message)

		if message == win.WM_LBUTTONUP && ctx.is_resizing {
			ctx.is_resizing = false
			ctx.resize_state = .NONE
			ctx.resize_mouse_offset = {}
		}

		win.ReleaseCapture()
		ctx.mouse_state[button] &= ~KEY_STATE_HELD
		ctx.mouse_state[button] |= KEY_STATE_RELEASED

	case win.WM_MOUSEMOVE:
		ctx.mouse_pos.x = int(win.GET_X_LPARAM(lparam))
		ctx.mouse_pos.y = int(win.GET_Y_LPARAM(lparam))

		if !ctx.is_resizing && !ctx.compact_mode {
			resize_area := get_resize_area(ctx.mouse_pos.x, ctx.mouse_pos.y)
			set_resize_cursor(resize_area)
		}

	case win.WM_QUIT, win.WM_CLOSE:
		ctx.is_running = false

	case win.WM_SIZE:
		if wparam == win.SIZE_MINIMIZED {
			ctx.is_minimized = true
		} else if wparam == win.SIZE_RESTORED || wparam == win.SIZE_MAXIMIZED {
			ctx.is_minimized = false

			new_width := cast(int)win.LOWORD(lparam)
			new_height := cast(int)win.HIWORD(lparam)

			if new_width != ctx.window.w || new_height != ctx.window.h {
				ctx.window.w = new_width
				ctx.window.h = new_height

				if swapchain != nil {
					resize_swapchain(new_width, new_height)
				}
			}
		}
		return 0
	case win.WM_NCCALCSIZE:
		if (wparam == 1) {
			return 0 // removes the title bar height
		}
		break

	case win.WM_ENTERSIZEMOVE:
		win.SetTimer(ctx.hwnd, 1, win.USER_TIMER_MINIMUM, nil)
		break
	case win.WM_EXITSIZEMOVE:
		win.KillTimer(ctx.hwnd, 1)
		if ctx.compact_mode do constrain_window_to_screen()
		break
	case win.WM_TIMER:
		update_frame(ctx.frame_proc)
	case win.WM_MOUSEWHEEL:
		delta := cast(i8)((wparam >> 16) & 0xFFFF)
		ctx.mouse_scroll += int(delta) / win.WHEEL_DELTA
	case win.WM_CHAR:
		wchar := win.WCHAR(wparam)
		if wparam >= 0xd800 && wparam <= 0xdbff {
			// https://learn.microsoft.com/en-us/windows/win32/inputdev/wm-char#remarks.
			// High surrogate. Store for joining to next mesage.
			ctx.last_high_surrogate = wchar
		} else {
			defer ctx.last_high_surrogate = nil

			if callback := ctx.text_callback; callback != nil {
				buf_w: [3]win.WCHAR
				if high_surrogate, ok := ctx.last_high_surrogate.?; ok {
					buf_w = {high_surrogate, wchar, 0}
				} else {
					buf_w = {wchar, 0, 0}
				}

				buf_utf8: [4]u8
				win.wstring_to_utf8(buf_utf8[:], transmute(cstring16)raw_data(&buf_w))

				if r, len := utf8.decode_rune_in_bytes(buf_utf8[:]); r != utf8.RUNE_ERROR {
					callback(r)
				}
			}
		}
		return 0

	case win.WM_DROPFILES:
		hdrop := win.HDROP(wparam)
		defer win.DragFinish(hdrop)

		file_count := win.DragQueryFileW(hdrop, 0xFFFFFFFF, nil, 0)

		if file_count > 0 && ctx.file_drop_callback != nil {
			files := make([]string, file_count)
			defer delete(files)

			for i in 0 ..< file_count {
				length := win.DragQueryFileW(hdrop, u32(i), nil, 0)

				if length > 0 {
					buffer := make([]u16, length + 1)
					defer delete(buffer)

					win.DragQueryFileW(hdrop, u32(i), raw_data(buffer), u32(len(buffer)))

					if utf8_str, err := win.wstring_to_utf8(transmute(cstring16)raw_data(buffer), len(buffer));
					   err == nil {
						files[i] = strings.clone(utf8_str)
					}
				}
			}

			ctx.file_drop_callback(files)

			for file in files {
				delete(file)
			}
		}

		ctx.is_hovering_files = false
		return 0
	}

	return win.DefWindowProcW(hwnd, message, wparam, lparam)
}

set_window_size :: proc(width, height: int) {
	if ctx.hwnd == nil do return

	rect: win.RECT
	win.GetWindowRect(ctx.hwnd, &rect)

	temp_rect := win.RECT {
		left   = 0,
		top    = 0,
		right  = i32(width),
		bottom = i32(height),
	}

	win.AdjustWindowRectEx(&temp_rect, window_styles, win.FALSE, 0)

	adjusted_width := temp_rect.right - temp_rect.left
	adjusted_height := temp_rect.bottom - temp_rect.top

	win.SetWindowPos(
		ctx.hwnd,
		nil,
		rect.left,
		rect.top,
		adjusted_width,
		adjusted_height,
		win.SWP_NOZORDER | win.SWP_NOACTIVATE,
	)

	ctx.window.w = int(adjusted_width)
	ctx.window.h = int(adjusted_height)
}

center_window :: proc() {
	if ctx.hwnd == nil do return

	rect: win.RECT
	win.GetWindowRect(ctx.hwnd, &rect)

	window_width := rect.right - rect.left
	window_height := rect.bottom - rect.top

	screen_width := win.GetSystemMetrics(win.SM_CXSCREEN)
	screen_height := win.GetSystemMetrics(win.SM_CYSCREEN)

	x := (screen_width - window_width) / 2
	y := (screen_height - window_height) / 2

	win.SetWindowPos(
		ctx.hwnd,
		nil,
		x,
		y,
		window_width,
		window_height,
		win.SWP_NOZORDER | win.SWP_NOACTIVATE,
	)
}

set_window_pos :: proc(x, y: int) {
	if ctx.hwnd == nil do return

	rect: win.RECT
	win.GetWindowRect(ctx.hwnd, &rect)

	window_width := rect.right - rect.left
	window_height := rect.bottom - rect.top

	win.SetWindowPos(
		ctx.hwnd,
		nil,
		i32(x),
		i32(y),
		window_width,
		window_height,
		win.SWP_NOZORDER | win.SWP_NOACTIVATE,
	)
}

get_window_pos :: proc() -> (x, y: int) {
	if ctx.hwnd == nil do return 0, 0

	rect: win.RECT
	win.GetWindowRect(ctx.hwnd, &rect)

	return int(rect.left), int(rect.top)
}

maximize_or_restore_window :: proc() {
	if ctx.is_minimized {
		win.ShowWindow(ctx.hwnd, win.SW_RESTORE)
		ctx.is_minimized = false
		return
	}

	window_placement: win.WINDOWPLACEMENT
	window_placement.length = size_of(win.WINDOWPLACEMENT)
	win.GetWindowPlacement(ctx.hwnd, &window_placement)

	if window_placement.showCmd == u32(win.SW_MAXIMIZE) {
		win.ShowWindow(ctx.hwnd, win.SW_RESTORE)
	} else {
		win.ShowWindow(ctx.hwnd, win.SW_MAXIMIZE)
	}
}

close_window :: proc() {
	win.PostMessageW(ctx.hwnd, win.WM_CLOSE, 0, 0)
}

minimize_window :: proc() {
	win.ShowWindow(ctx.hwnd, win.SW_MINIMIZE)

	for &state in ctx.mouse_state {
		state &= ~KEY_STATE_HELD
	}
}

prev_state: [256]bool
key_pressed_global :: proc(vKey: Key) -> bool {
    state := i32(win.GetAsyncKeyState(i32(vKey)))
    is_down := (state & 0x8000) != 0

    result := is_down && !prev_state[vKey]
    prev_state[vKey] = is_down
    return result
}

set_cursor :: proc(cursor: Cursor) {
	sys_cursor: win.HCURSOR

	switch cursor {
	case .DEFAULT:
		sys_cursor = win.LoadCursorA(nil, win.IDC_ARROW)
	case .CLICK:
		sys_cursor = win.LoadCursorA(nil, win.IDC_HAND)
	case .TEXT:
		sys_cursor = win.LoadCursorA(nil, win.IDC_IBEAM)
	case .CROSSHAIR:
		sys_cursor = win.LoadCursorA(nil, win.IDC_CROSS)
	case .HORIZONTAL_RESIZE:
		sys_cursor = win.LoadCursorA(nil, win.IDC_SIZEWE)
	case .VERTICAL_RESIZE:
		sys_cursor = win.LoadCursorA(nil, win.IDC_SIZENS)
	case .DIAGONAL_RESIZE_1:
		sys_cursor = win.LoadCursorA(nil, win.IDC_SIZENWSE)
	case .DIAGONAL_RESIZE_2:
		sys_cursor = win.LoadCursorA(nil, win.IDC_SIZENESW)
	case .NONE:
		sys_cursor = nil
	}

	win.SetCursor(sys_cursor)
}

// Resizing

RESIZE_BORDER_WIDTH :: 8
RESIZE_CORNER_SIZE :: 16

ResizeState :: enum {
	NONE,
	LEFT,
	RIGHT,
	TOP,
	BOTTOM,
	TOP_LEFT,
	TOP_RIGHT,
	BOTTOM_LEFT,
	BOTTOM_RIGHT,
}

get_resize_area :: proc(x, y: int) -> ResizeState {
	w, h := ctx.window.w, ctx.window.h

	if x < RESIZE_CORNER_SIZE && y < RESIZE_CORNER_SIZE {
		return .TOP_LEFT
	}
	if x > w - RESIZE_CORNER_SIZE && y < RESIZE_CORNER_SIZE {
		return .TOP_RIGHT
	}
	if x < RESIZE_CORNER_SIZE && y > h - RESIZE_CORNER_SIZE {
		return .BOTTOM_LEFT
	}
	if x > w - RESIZE_CORNER_SIZE && y > h - RESIZE_CORNER_SIZE {
		return .BOTTOM_RIGHT
	}

	if x < RESIZE_BORDER_WIDTH {
		return .LEFT
	}
	if x > w - RESIZE_BORDER_WIDTH {
		return .RIGHT
	}
	if y < RESIZE_BORDER_WIDTH && x < w - 150 {
		return .TOP
	}
	if y > h - RESIZE_BORDER_WIDTH {
		return .BOTTOM
	}

	return .NONE
}

set_resize_cursor :: proc(resize_area: ResizeState) {
	switch resize_area {
	case .LEFT, .RIGHT:
		set_cursor(.HORIZONTAL_RESIZE)
	case .TOP, .BOTTOM:
		set_cursor(.VERTICAL_RESIZE)
	case .TOP_LEFT, .BOTTOM_RIGHT:
		set_cursor(.DIAGONAL_RESIZE_1)
	case .BOTTOM_LEFT:
		set_cursor(.DIAGONAL_RESIZE_2)
	case .NONE, .TOP_RIGHT:
		set_cursor(.DEFAULT)
	}
}

perform_resize :: proc() {
	if ctx.compact_mode do return

	rect: win.RECT
	win.GetWindowRect(ctx.hwnd, &rect)

	point: win.POINT
	win.GetCursorPos(&point)

	adjusted_point := win.POINT {
		x = point.x - ctx.resize_mouse_offset.x,
		y = point.y - ctx.resize_mouse_offset.y,
	}

	new_x := rect.left
	new_y := rect.top
	new_width := rect.right - rect.left
	new_height := rect.bottom - rect.top

	switch ctx.resize_state {
	case .LEFT:
		new_x = adjusted_point.x
		new_width = rect.right - adjusted_point.x

	case .RIGHT:
		new_width = adjusted_point.x - rect.left

	case .TOP:
		new_y = adjusted_point.y
		new_height = rect.bottom - adjusted_point.y

	case .BOTTOM:
		new_height = adjusted_point.y - rect.top

	case .TOP_LEFT:
		new_x = adjusted_point.x
		new_y = adjusted_point.y
		new_width = rect.right - adjusted_point.x
		new_height = rect.bottom - adjusted_point.y

	case .TOP_RIGHT:
		new_y = adjusted_point.y
		new_width = adjusted_point.x - rect.left
		new_height = rect.bottom - adjusted_point.y

	case .BOTTOM_LEFT:
		new_x = adjusted_point.x
		new_width = rect.right - adjusted_point.x
		new_height = adjusted_point.y - rect.top

	case .BOTTOM_RIGHT:
		new_width = adjusted_point.x - rect.left
		new_height = adjusted_point.y - rect.top

	case .NONE:
	}

	min_width: i32 = 750
	min_height: i32 = 600

	if new_width < min_width && !ctx.compact_mode {
		if ctx.resize_state == .LEFT ||
		   ctx.resize_state == .TOP_LEFT ||
		   ctx.resize_state == .BOTTOM_LEFT {
			new_x = rect.right - min_width
		}
		new_width = min_width
	}

	if new_height < min_height && !ctx.compact_mode {
		if ctx.resize_state == .TOP ||
		   ctx.resize_state == .TOP_LEFT ||
		   ctx.resize_state == .TOP_RIGHT {
			new_y = rect.bottom - min_height
		}
		new_height = min_height
	}

	win.SetWindowPos(
		ctx.hwnd,
		nil,
		new_x,
		new_y,
		new_width,
		new_height,
		win.SWP_NOZORDER | win.SWP_NOACTIVATE,
	)
}

handle_resize :: proc() {
	resize_area := get_resize_area(ctx.mouse_pos.x, ctx.mouse_pos.y)

	if ctx.is_resizing {
		set_resize_cursor(resize_area)
	}

	if ctx.is_resizing && mouse_held(.LEFT) {
		perform_resize()
	}
}

constrain_window_to_screen :: proc() {
	if ctx.hwnd == nil do return

	rect: win.RECT
	win.GetWindowRect(ctx.hwnd, &rect)

	window_width := rect.right - rect.left
	window_height := rect.bottom - rect.top

	screen_width := win.GetSystemMetrics(win.SM_CXSCREEN)
	screen_height := win.GetSystemMetrics(win.SM_CYSCREEN)

	new_x := rect.left
	new_y := rect.top

	if new_x < 0 {
		new_x = 0
	} else if new_x + window_width > screen_width {
		new_x = screen_width - window_width
	}

	if new_y < 0 {
		new_y = 0
	} else if new_y + window_height > screen_height {
		new_y = screen_height - window_height
	}

	if new_x != rect.left || new_y != rect.top {
		win.SetWindowPos(
			ctx.hwnd,
			nil,
			new_x,
			new_y,
			window_width,
			window_height,
			win.SWP_NOZORDER | win.SWP_NOACTIVATE,
		)
	}
}

update_window_style :: proc(enabled: bool) {
	if ctx.hwnd == nil do return
	current_style := u32(win.GetWindowLongW(ctx.hwnd, win.GWL_STYLE))
	current_ex_style := u32(win.GetWindowLongW(ctx.hwnd, win.GWL_EXSTYLE))
	new_style := current_style
	new_ex_style := current_ex_style

	if enabled {
		new_style &= ~(win.WS_THICKFRAME | win.WS_SIZEBOX)
		new_ex_style &= ~win.WS_EX_WINDOWEDGE
		new_ex_style |= win.WS_EX_TOPMOST
	} else {
		new_style |= win.WS_THICKFRAME | win.WS_SIZEBOX
		new_ex_style |= win.WS_EX_WINDOWEDGE
		new_ex_style &= ~win.WS_EX_TOPMOST
	}

	win.SetWindowLongW(ctx.hwnd, win.GWL_STYLE, i32(new_style))
	win.SetWindowLongW(ctx.hwnd, win.GWL_EXSTYLE, i32(new_ex_style))

	z_order := win.HWND_NOTOPMOST
	if enabled {
		z_order = win.HWND_TOPMOST
	}

	win.SetWindowPos(
		ctx.hwnd,
		z_order,
		0, 0, 0, 0,
		win.SWP_NOMOVE | win.SWP_NOSIZE | win.SWP_FRAMECHANGED,
	)
}

enable_compact_mode :: proc() {
	ctx.compact_mode = true
	update_window_style(true)
}

disable_compact_mode :: proc() {
	ctx.compact_mode = false
	update_window_style(false)
}