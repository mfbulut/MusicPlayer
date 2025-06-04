package fx

import "base:runtime"
import "core:time"

import win "core:sys/windows"

Context :: struct {
	hwnd: 	     win.HWND,
	is_running : bool,
	is_minimized: bool,
	frame_proc : proc(dt : f32),
	text_callback : proc(char : u8),

	prev_time:  time.Time,
	delta_time: f32,

	window:      struct { w, h: int },
	mouse_pos:   struct { x, y: int },
	key_state:   [256]u8,
	mouse_state: [8]u8,
	mouse_scroll : int,
}

@(private)
ctx: Context

ICON_DATA : []win.BYTE = #load("icon.ico")

ICONDIR :: struct {
    reserved: u16,
    type_: u16,
    count: u16,
}

ICONDIRENTRY :: struct {
    width: u8,
    height: u8,
    color_count: u8,
    reserved: u8,
    planes: u16,
    bit_count: u16,
    bytes_in_res: u32,
    image_offset: u32,
}

load_icon_by_size :: proc(desired_size: int) -> win.HICON {
    dir := cast(^ICONDIR)&ICON_DATA[0]
    entries := cast([^]ICONDIRENTRY)&ICON_DATA[size_of(ICONDIR)]

    best_entry := entries[0]
    best_diff : i32 = abs(i32(entries[0].width) - i32(desired_size))

    for i in 1..<dir.count {
        e := entries[i]
        diff := abs(i32(e.width) - i32(desired_size))
        if diff < best_diff {
            best_entry = e
            best_diff = diff
        }
    }

    icon_data := &ICON_DATA[best_entry.image_offset]
    icon_size := best_entry.bytes_in_res

    return win.CreateIconFromResourceEx(
        icon_data,
        icon_size,
        win.TRUE,
        0x00030000,
        0, 0, 0
    )
}

init :: proc(title: string, width, height: int) {
	win_title := win.utf8_to_wstring(title)

	instance := win.HINSTANCE(win.GetModuleHandleW(nil))
	class_name := win.L("Window Class")

	cls := win.WNDCLASSEXW{
		cbSize =        size_of(win.WNDCLASSEXW),
		lpfnWndProc =   win_proc,
		lpszClassName = class_name,
		hInstance =     instance,
		hCursor =       win.LoadCursorA(nil, win.IDC_ARROW),
		hIcon =         load_icon_by_size(256),
		hIconSm =       load_icon_by_size(32),
		style =         win.CS_HREDRAW | win.CS_VREDRAW,
	}

	win.RegisterClassExW(&cls)

	screen_width := win.GetSystemMetrics(win.SM_CXSCREEN)
	screen_height := win.GetSystemMetrics(win.SM_CYSCREEN)

	x := (screen_width  - i32(width)) / 2
	y := (screen_height - i32(height)) / 2

	rect : win.RECT = {
		left = 0,
		top = 0,
		right = i32(width),
		bottom = i32(height),
	}

	win.AdjustWindowRectEx(&rect, win.WS_OVERLAPPEDWINDOW, win.FALSE, 0)

	adjusted_width := rect.right - rect.left
	adjusted_height := rect.bottom - rect.top

	ctx.hwnd = win.CreateWindowW(
		class_name,
		win_title,
		win.WS_POPUP | win.WS_OVERLAPPEDWINDOW | win.WS_VISIBLE,
		x, y,
		adjusted_width, adjusted_height,
		nil, nil, instance, nil
	)

	win.ShowWindow(ctx.hwnd, 1)
	local_true := win.TRUE
	win.DwmSetWindowAttribute(ctx.hwnd, u32(win.DWMWINDOWATTRIBUTE.DWMWA_USE_IMMERSIVE_DARK_MODE), &local_true, size_of(local_true))

	init_dx()
	init_audio()
	set_scissor(0, 0, i32(width), i32(height))

	ctx.window.w = width
	ctx.window.h = height
	ctx.is_running = true
}

run_manual :: proc(frame : proc()) {
	msg: win.MSG
	for win.PeekMessageW(&msg, ctx.hwnd, 0, 0, win.PM_REMOVE) {
		win.TranslateMessage(&msg)
		win.DispatchMessageW(&msg)
	}

	clear_background(BLACK)
	begin_render()

	frame()

	end_render()
	swap_buffers()

	for &state in ctx.key_state {
		state &~= (KEY_STATE_PRESSED | KEY_STATE_RELEASED)
	}
	for &state in ctx.mouse_state {
		state &~= (KEY_STATE_PRESSED | KEY_STATE_RELEASED)
	}

	ctx.mouse_scroll = 0
}

run :: proc(frame : proc(dt : f32)) {
	ctx.frame_proc = frame

	current_time := time.now()
	ctx.prev_time = current_time

	msg: win.MSG
	for ctx.is_running {
		for win.PeekMessageW(&msg, ctx.hwnd, 0, 0, win.PM_REMOVE) {
			win.TranslateMessage(&msg)
			win.DispatchMessageW(&msg)
		}

		current_time = time.now()
		ctx.delta_time = f32(time.duration_seconds(time.diff(ctx.prev_time, current_time)))
		ctx.prev_time = current_time

		if !ctx.is_minimized {
			clear_background(BLACK)
			begin_render()
			frame(ctx.delta_time)
			end_render()
			swap_buffers()
		} else {
			frame(ctx.delta_time)
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
}


@(private)
switch_button :: #force_inline proc(x: u32) -> Mouse {
	switch x {
	case win.WM_RBUTTONDOWN, win.WM_RBUTTONUP: return .RIGHT
	case win.WM_MBUTTONDOWN, win.WM_MBUTTONUP: return .MIDDLE
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

@(private)
win_proc :: proc "stdcall" (hwnd: win.HWND, message: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM) -> win.LRESULT {
	context = runtime.default_context()

	switch message {
	case win.WM_KEYDOWN, win.WM_SYSKEYDOWN:
	    if wparam == win.VK_ESCAPE { ctx.is_running = false }
		if lparam & (1 << 30) != 0 do break // key repeat
		code := switch_keys(u32(wparam), lparam)
		ctx.key_state[code] = KEY_STATE_HELD | KEY_STATE_PRESSED

	case win.WM_KEYUP, win.WM_SYSKEYUP:
		code := switch_keys(u32(wparam), lparam)
		ctx.key_state[code] &= ~KEY_STATE_HELD
		ctx.key_state[code] |=  KEY_STATE_RELEASED

	case win.WM_LBUTTONDOWN, win.WM_RBUTTONDOWN, win.WM_MBUTTONDOWN:
		win.SetCapture(hwnd)
		button := switch_button(message)
		ctx.mouse_state[button] = KEY_STATE_HELD | KEY_STATE_PRESSED

	case win.WM_LBUTTONUP, win.WM_RBUTTONUP, win.WM_MBUTTONUP:
		win.ReleaseCapture()
		button := switch_button(message)
		ctx.mouse_state[button] &= ~KEY_STATE_HELD
		ctx.mouse_state[button] |= KEY_STATE_RELEASED

	case win.WM_MOUSEMOVE:
	   ctx.mouse_pos.x = int(win.GET_X_LPARAM(lparam))
	   ctx.mouse_pos.y = int(win.GET_Y_LPARAM(lparam))

	case win.WM_QUIT, win.WM_CLOSE:
		ctx.is_running = false

	case win.WM_SIZE:
		if wparam == win.SIZE_MINIMIZED {
			ctx.is_minimized = true
		} else if wparam == win.SIZE_RESTORED || wparam == win.SIZE_MAXIMIZED {
			ctx.is_minimized = false

			new_width := cast(int) win.LOWORD(lparam)
			new_height := cast(int) win.HIWORD(lparam)

			if new_width != ctx.window.w || new_height != ctx.window.h {
				ctx.window.w = new_width
				ctx.window.h = new_height

				if ctx.is_running && swapchain != nil {
					resize_swapchain(new_width, new_height)
				}
			}
		}
		return 0

	case win.WM_ENTERSIZEMOVE:
        win.SetTimer(ctx.hwnd, 1, win.USER_TIMER_MINIMUM, nil)
        break
    case win.WM_EXITSIZEMOVE:
        win.KillTimer(ctx.hwnd, 1)
        break
    case win.WM_TIMER:
		current_time := time.now()
		ctx.delta_time = f32(time.duration_seconds(time.diff(ctx.prev_time, current_time)))
		ctx.prev_time = current_time

		clear_background(BLACK)
		begin_render()

        ctx.frame_proc(ctx.delta_time);

		end_render()
		swap_buffers()
	case win.WM_MOUSEWHEEL:
		delta := cast(i8)((wparam >> 16) & 0xFFFF)
		ctx.mouse_scroll += int(delta) / win.WHEEL_DELTA // usually ±120
	case win.WM_GETMINMAXINFO: {
	    minMax := cast(^win.MINMAXINFO)uintptr(lparam);
	    minMax.ptMinTrackSize.x = 600;
	    minMax.ptMinTrackSize.y = 600;
	    return 0;
	}
	case win.WM_CHAR:
		char := u8(wparam)
		if ctx.text_callback != nil && char >= 32 && char != 127 {
			ctx.text_callback(char)
		}

	case:
		return win.DefWindowProcW(hwnd, message, wparam, lparam)
	}

    return 0
}

KEY_STATE_HELD:     u8: 0x0001
KEY_STATE_PRESSED:  u8: 0x0002
KEY_STATE_RELEASED: u8: 0x0004

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

set_char_callback :: proc(callback : proc(char : u8)) {
	ctx.text_callback = callback
}

window_size :: proc() -> (int, int) {
	return ctx.window.w, ctx.window.h
}

set_cursor :: proc(cursor: Cursor) {
    sys_cursor: win.HCURSOR

    switch cursor {
    case .DEFAULT:              sys_cursor = win.LoadCursorA(nil, win.IDC_ARROW)
    case .CLICK:                sys_cursor = win.LoadCursorA(nil, win.IDC_HAND)
    case .TEXT:                 sys_cursor = win.LoadCursorA(nil, win.IDC_IBEAM)
    case .CROSSHAIR:            sys_cursor = win.LoadCursorA(nil, win.IDC_CROSS)
    case .HORIZONTAL_RESIZE:    sys_cursor = win.LoadCursorA(nil, win.IDC_SIZEWE)
    case .VERTICAL_RESIZE:      sys_cursor = win.LoadCursorA(nil, win.IDC_SIZENS)
    case .DIAGONAL_RESIZE_1:    sys_cursor = win.LoadCursorA(nil, win.IDC_SIZENWSE)
    case .DIAGONAL_RESIZE_2:    sys_cursor = win.LoadCursorA(nil, win.IDC_SIZENESW)
    case .NONE:                 sys_cursor = nil // hides the cursor
    }

    win.SetCursor(sys_cursor)
}

prev_state: [256]bool
key_pressed_global :: proc(vKey: Key) -> bool {
    state := i32(win.GetAsyncKeyState(i32(vKey)))
    is_down := (state & 0x8000) != 0

    result := is_down && !prev_state[vKey]
    prev_state[vKey] = is_down
    return result
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
	UNKNOWN = 0,

	N0 = '0',
	N1 = '1',
	N2 = '2',
	N3 = '3',
	N4 = '4',
	N5 = '5',
	N6 = '6',
	N7 = '7',
	N8 = '8',
	N9 = '9',

	A = 'A',
	B = 'B',
	C = 'C',
	D = 'D',
	E = 'E',
	F = 'F',
	G = 'G',
	H = 'H',
	I = 'I',
	J = 'J',
	K = 'K',
	L = 'L',
	M = 'M',
	N = 'N',
	O = 'O',
	P = 'P',
	Q = 'Q',
	R = 'R',
	S = 'S',
	T = 'T',
	U = 'U',
	V = 'V',
	W = 'W',
	X = 'X',
	Y = 'Y',
	Z = 'Z',

	RETURN    = 0x0D,
	TAB       = 0x09,
	BACKSPACE = 0x08,
	DELETE    = 0x2E,
	ESCAPE    = 0x1B,
	SPACE     = 0x20,

	LEFT_SHIFT    = 0xA0,
	RIGHT_SHIFT   = 0xA1,
	LEFT_CONTROL  = 0xA2,
	RIGHT_CONTROL = 0xA3,
	LEFT_ALT      = 0xA4,
	RIGHT_ALT     = 0xA5,
	LEFT_SUPER    = 0x5B,
	RIGHT_SUPER   = 0x5C,

	END   = 0x23,
	HOME  = 0x24,
	LEFT  = 0x25,
	UP    = 0x26,
	RIGHT = 0x27,
	DOWN  = 0x28,

	SEMICOLON = 0xBA,
	EQUALS    = 0xBB,
	COMMA     = 0xBC,
	MINUS     = 0xBD,
	DOT       = 0xBE,
	PERIOD    = DOT,
	SLASH     = 0xBF,
	GRAVE     = 0xC0,

	PAGE_UP   = 0x21,
	PAGE_DOWN = 0x22,

	LEFT_BRACKET  = 0xDB,
	RIGHT_BRACKET = 0xDD,
	BACKSLASH     = 0xDC,
	QUOTE         = 0xDE,

	P0 = 0x60,
	P1 = 0x61,
	P2 = 0x62,
	P3 = 0x63,
	P4 = 0x64,
	P5 = 0x65,
	P6 = 0x66,
	P7 = 0x67,
	P8 = 0x68,
	P9 = 0x69,

	KEYPAD_MULTIPLY = 0x6A,
	KEYPAD_PLUS     = 0x6B,
	KEYPAD_MINUS    = 0x6D,
	KEYPAD_DOT      = 0x6E,
	KEYPAD_PERIOD   = KEYPAD_DOT,
	KEYPAD_DIVIDE   = 0x6F,
	KEYPAD_RETURN   = RETURN,
	KEYPAD_EQUALS   = EQUALS,

	F1  = 0x70,
	F2  = 0x71,
	F3  = 0x72,
	F4  = 0x73,
	F5  = 0x74,
	F6  = 0x75,
	F7  = 0x76,
	F8  = 0x77,
	F9  = 0x78,
	F10 = 0x79,
	F11 = 0x7A,
	F12 = 0x7B,
	F13 = 0x7C,
	F14 = 0x7D,
	F15 = 0x7E,
	F16 = 0x7F,
	F17 = 0x80,
	F18 = 0x81,
	F19 = 0x82,
	F20 = 0x83,

	MEDIA_NEXT_TRACK = 0xB1,
	MEDIA_PREV_TRACK = 0xB1,
	MEDIA_PLAY_PAUSE = 0xB3,
}