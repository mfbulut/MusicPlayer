package fx

import "base:runtime"
import "core:strings"
import "core:time"

import win "core:sys/windows"

Context :: struct {
	hwnd:                win.HWND,
	is_running:          bool,
	is_minimized:        bool,
	frame_proc:          proc(),
	text_callback:       proc(char: u8),
	file_drop_callback:  proc(files: []string),
	is_hovering_files:   bool,
	prev_time:           time.Time,
	delta_time:          f32,
	timer:               f32,
	window:              struct {
		w, h: int,
	},
	mouse_pos:           struct {
		x, y: int,
	},
	key_state:           [256]u8,
	mouse_state:         [8]u8,
	mouse_scroll:        int,
	last_click_time:     time.Time,
	last_click_pos:      struct {
		x, y: int,
	},
	resize_state:        ResizeState,
	resize_mouse_offset: struct {
		x, y: i32,
	},
	is_resizing:         bool,
}

double_click_threshold :: 0.2

@(private)
ctx: Context

ICON_DATA: []win.BYTE = #load("icon.ico")

ICONDIR :: struct {
	reserved: u16,
	type_:    u16,
	count:    u16,
}

ICONDIRENTRY :: struct {
	width:        u8,
	height:       u8,
	color_count:  u8,
	reserved:     u8,
	planes:       u16,
	bit_count:    u16,
	bytes_in_res: u32,
	image_offset: u32,
}

load_icon_by_size :: proc(desired_size: int) -> win.HICON {
	dir := cast(^ICONDIR)&ICON_DATA[0]
	entries := cast([^]ICONDIRENTRY)&ICON_DATA[size_of(ICONDIR)]

	best_entry := entries[0]
	best_diff: i32 = abs(i32(entries[0].width) - i32(desired_size))

	for i in 1 ..< dir.count {
		e := entries[i]
		diff := abs(i32(e.width) - i32(desired_size))
		if diff < best_diff {
			best_entry = e
			best_diff = diff
		}
	}

	icon_data := &ICON_DATA[best_entry.image_offset]
	icon_size := best_entry.bytes_in_res

	return win.CreateIconFromResourceEx(icon_data, icon_size, win.TRUE, 0x00030000, 0, 0, 0)
}

window_styles :: win.WS_OVERLAPPEDWINDOW | win.WS_VISIBLE

chroma_key :: Color{16, 0, 16, 0}

HOTKEY_NEXT :: 1001
HOTKEY_PREV :: 1002
HOTKEY_PLAY_PAUSE :: 1003

init :: proc(title: string, width, height: int) {
	win_title := win.utf8_to_wstring(title)

	// win.SetProcessDPIAware() // TODO(furkan) add dpi aware scaling

	instance := win.HINSTANCE(win.GetModuleHandleW(nil))
	class_name := win.L("Window Class")

	cls := win.WNDCLASSEXW {
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

	win.SetLayeredWindowAttributes(
		ctx.hwnd,
		win.RGB(chroma_key.r, chroma_key.g, chroma_key.b),
		255,
		0x00000001,
	)

	init_dx()
	init_font()
	init_audio()

	win.RegisterHotKey(ctx.hwnd, HOTKEY_NEXT, 0, u32(Key.MEDIA_NEXT_TRACK))
	win.RegisterHotKey(ctx.hwnd, HOTKEY_PREV, 0, u32(Key.MEDIA_PREV_TRACK))
	win.RegisterHotKey(ctx.hwnd, HOTKEY_PLAY_PAUSE, 0, u32(Key.MEDIA_PLAY_PAUSE))

	ctx.window.w = int(adjusted_width)
	ctx.window.h = int(adjusted_height)

	set_scissor(0, 0, i32(ctx.window.w), i32(ctx.window.h))

	ctx.is_running = true
}

update_frame :: proc(frame_proc: proc(), vsync := true) {
	ci := win.CURSORINFO {
		cbSize = size_of(win.CURSORINFO),
	}
	win.GetCursorInfo(&ci)

	// Probably only works on my machine
	CURSOR_ID :: 0x705F3
	if (ci.hCursor == transmute(win.HCURSOR)uintptr(CURSOR_ID)) {
		ctx.is_hovering_files = true
	} else {
		ctx.is_hovering_files = false
	}

	current_time := time.now()
	ctx.delta_time = f32(time.duration_seconds(time.diff(ctx.prev_time, current_time)))
	ctx.timer += ctx.delta_time
	ctx.prev_time = current_time

	handle_resize()

	if !ctx.is_minimized {
		clear_background(chroma_key)
		begin_render()
		update_constant_buffer()
		frame_proc()
		end_render()
		swap_buffers(vsync)
	} else {
		frame_proc()
		win.Sleep(16)
	}

	for &state in ctx.key_state {
		state &~= (KEY_STATE_PRESSED | KEY_STATE_RELEASED)
	}
	for &state in ctx.mouse_state {
		state &~= (KEY_STATE_PRESSED | KEY_STATE_RELEASED)
	}

	ctx.mouse_scroll = 0
}

run_manual :: proc(frame: proc()) {
	msg: win.MSG
	for win.PeekMessageW(&msg, ctx.hwnd, 0, 0, win.PM_REMOVE) {
		win.TranslateMessage(&msg)
		win.DispatchMessageW(&msg)
	}

	update_frame(frame, false)
}

run :: proc(frame: proc()) {
	ctx.frame_proc = frame

	current_time := time.now()
	ctx.prev_time = current_time

	msg: win.MSG
	for ctx.is_running {
		for win.PeekMessageW(&msg, ctx.hwnd, 0, 0, win.PM_REMOVE) {
			win.TranslateMessage(&msg)
			win.DispatchMessageW(&msg)
		}

		update_frame(frame)
	}
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

is_resizing :: proc() -> bool {
	return ctx.is_resizing
}

set_file_drop_callback :: proc(callback: proc(files: []string)) {
	ctx.file_drop_callback = callback

	if ctx.hwnd != nil {
		win.DragAcceptFiles(ctx.hwnd, win.TRUE)
	}
}

is_hovering_files :: proc() -> bool {
	return ctx.is_hovering_files
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

				win.SetCapture(hwnd)
				ctx.mouse_state[button] = KEY_STATE_HELD | KEY_STATE_PRESSED
				break
			}

			if is_in_title_bar(ctx.mouse_pos.x, ctx.mouse_pos.y) {
				current_time := time.now()
				time_diff := f32(
					time.duration_seconds(time.diff(ctx.last_click_time, current_time)),
				)

				if time_diff <= double_click_threshold &&
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

		if !ctx.is_resizing {
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
		break
	case win.WM_TIMER:
		update_frame(ctx.frame_proc)
	case win.WM_MOUSEWHEEL:
		delta := cast(i8)((wparam >> 16) & 0xFFFF)
		ctx.mouse_scroll += int(delta) / win.WHEEL_DELTA
	case win.WM_GETMINMAXINFO:
		{
			minMax := cast(^win.MINMAXINFO)uintptr(lparam)
			minMax.ptMinTrackSize.x = 700
			minMax.ptMinTrackSize.y = 600
			return 0
		}
	case win.WM_CHAR:
		char := u8(wparam)
		if ctx.text_callback != nil && char >= 32 && char != 127 {
			ctx.text_callback(char)
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

					if utf8_str, err := win.wstring_to_utf8(raw_data(buffer), len(buffer));
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
	case:

	}

	return win.DefWindowProcW(hwnd, message, wparam, lparam)
}

KEY_STATE_HELD: u8 : 0x0001
KEY_STATE_PRESSED: u8 : 0x0002
KEY_STATE_RELEASED: u8 : 0x0004

key_held :: #force_inline proc(key: Key) -> bool {
	return ctx.key_state[key] & KEY_STATE_HELD != 0
}
key_pressed :: #force_inline proc(key: Key) -> bool {
	return ctx.key_state[key] & KEY_STATE_PRESSED != 0
}
key_released :: #force_inline proc(key: Key) -> bool {
	return ctx.key_state[key] & KEY_STATE_RELEASED != 0
}

mouse_held :: #force_inline proc(button: Mouse) -> bool {
	return ctx.mouse_state[button] & KEY_STATE_HELD != 0
}
mouse_pressed :: #force_inline proc(button: Mouse) -> bool {
	return ctx.mouse_state[button] & KEY_STATE_PRESSED != 0
}
mouse_released :: #force_inline proc(button: Mouse) -> bool {
	return ctx.mouse_state[button] & KEY_STATE_RELEASED != 0
}

get_mouse :: proc() -> (int, int) {
	return ctx.mouse_pos.x, ctx.mouse_pos.y
}

get_mouse_scroll :: proc() -> int {
	return ctx.mouse_scroll
}

set_char_callback :: proc(callback: proc(char: u8)) {
	ctx.text_callback = callback
}

window_size :: proc() -> (int, int) {
	return ctx.window.w, ctx.window.h
}

delta_time :: proc() -> f32 {
	return ctx.delta_time
}

time :: proc() -> f32 {
	return ctx.timer
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
	case .TOP_RIGHT, .BOTTOM_LEFT:
		set_cursor(.DIAGONAL_RESIZE_2)
	case .NONE:
		set_cursor(.DEFAULT)
	}
}

perform_resize :: proc() {
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

	min_width: i32 = 700
	min_height: i32 = 600

	if new_width < min_width {
		if ctx.resize_state == .LEFT ||
		   ctx.resize_state == .TOP_LEFT ||
		   ctx.resize_state == .BOTTOM_LEFT {
			new_x = rect.right - min_width
		}
		new_width = min_width
	}

	if new_height < min_height {
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
	x, y := get_mouse()
	resize_area := get_resize_area(x, y)

	if ctx.is_resizing {
		set_resize_cursor(resize_area)
	}

	if ctx.is_resizing && mouse_held(.LEFT) {
		perform_resize()
	}
}

Cursor :: enum u8 {
	DEFAULT,
	CLICK,
	TEXT,
	CROSSHAIR,
	HORIZONTAL_RESIZE,
	VERTICAL_RESIZE,
	DIAGONAL_RESIZE_1,
	DIAGONAL_RESIZE_2,
	NONE,
}

Mouse :: enum u8 {
	UNKNOWN = 0,
	LEFT    = 1,
	RIGHT   = 2,
	MIDDLE  = 3,
}

Key :: enum u8 {
	UNKNOWN          = 0,
	N0               = '0',
	N1               = '1',
	N2               = '2',
	N3               = '3',
	N4               = '4',
	N5               = '5',
	N6               = '6',
	N7               = '7',
	N8               = '8',
	N9               = '9',
	A                = 'A',
	B                = 'B',
	C                = 'C',
	D                = 'D',
	E                = 'E',
	F                = 'F',
	G                = 'G',
	H                = 'H',
	I                = 'I',
	J                = 'J',
	K                = 'K',
	L                = 'L',
	M                = 'M',
	N                = 'N',
	O                = 'O',
	P                = 'P',
	Q                = 'Q',
	R                = 'R',
	S                = 'S',
	T                = 'T',
	U                = 'U',
	V                = 'V',
	W                = 'W',
	X                = 'X',
	Y                = 'Y',
	Z                = 'Z',
	RETURN           = 0x0D,
	TAB              = 0x09,
	BACKSPACE        = 0x08,
	DELETE           = 0x2E,
	ESCAPE           = 0x1B,
	SPACE            = 0x20,
	LEFT_SHIFT       = 0xA0,
	RIGHT_SHIFT      = 0xA1,
	LEFT_CONTROL     = 0xA2,
	RIGHT_CONTROL    = 0xA3,
	LEFT_ALT         = 0xA4,
	RIGHT_ALT        = 0xA5,
	LEFT_SUPER       = 0x5B,
	RIGHT_SUPER      = 0x5C,
	END              = 0x23,
	HOME             = 0x24,
	LEFT             = 0x25,
	UP               = 0x26,
	RIGHT            = 0x27,
	DOWN             = 0x28,
	SEMICOLON        = 0xBA,
	EQUALS           = 0xBB,
	COMMA            = 0xBC,
	MINUS            = 0xBD,
	DOT              = 0xBE,
	PERIOD           = DOT,
	SLASH            = 0xBF,
	GRAVE            = 0xC0,
	PAGE_UP          = 0x21,
	PAGE_DOWN        = 0x22,
	LEFT_BRACKET     = 0xDB,
	RIGHT_BRACKET    = 0xDD,
	BACKSLASH        = 0xDC,
	QUOTE            = 0xDE,
	P0               = 0x60,
	P1               = 0x61,
	P2               = 0x62,
	P3               = 0x63,
	P4               = 0x64,
	P5               = 0x65,
	P6               = 0x66,
	P7               = 0x67,
	P8               = 0x68,
	P9               = 0x69,
	KEYPAD_MULTIPLY  = 0x6A,
	KEYPAD_PLUS      = 0x6B,
	KEYPAD_MINUS     = 0x6D,
	KEYPAD_DOT       = 0x6E,
	KEYPAD_PERIOD    = KEYPAD_DOT,
	KEYPAD_DIVIDE    = 0x6F,
	KEYPAD_RETURN    = RETURN,
	KEYPAD_EQUALS    = EQUALS,
	F1               = 0x70,
	F2               = 0x71,
	F3               = 0x72,
	F4               = 0x73,
	F5               = 0x74,
	F6               = 0x75,
	F7               = 0x76,
	F8               = 0x77,
	F9               = 0x78,
	F10              = 0x79,
	F11              = 0x7A,
	F12              = 0x7B,
	F13              = 0x7C,
	F14              = 0x7D,
	F15              = 0x7E,
	F16              = 0x7F,
	F17              = 0x80,
	F18              = 0x81,
	F19              = 0x82,
	F20              = 0x83,
	MEDIA_NEXT_TRACK = 0xB0,
	MEDIA_PREV_TRACK = 0xB1,
	MEDIA_PLAY_PAUSE = 0xB3,
}
