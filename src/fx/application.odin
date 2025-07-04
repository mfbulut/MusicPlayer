package fx

import win "core:sys/windows"
import "core:strings"
import "core:time"

Context :: struct {
	hwnd:                win.HWND,
	is_running:          bool,
	is_minimized:        bool,

	frame_proc:          proc(),
	text_callback:       proc(char: rune),
	file_drop_callback:  proc(files: []string),

	clipboard:           strings.Builder,
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
	last_high_surrogate: Maybe(win.WCHAR),
	last_click_time:     time.Time,
	last_click_pos:      struct {
		x, y: int,
	},
	resize_state:        ResizeState,
	resize_mouse_offset: struct {
		x, y: i32,
	},
	is_resizing:         bool,
	compact_mode:        bool,
}

ctx: Context

init :: proc(title: string, width, height: int) {
    init_windows(title, width, height)

	init_dx()
	init_font()
	init_audio()

	ctx.prev_time = time.now()
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
		set_scissor(0, 0, f32(ctx.window.w), f32(ctx.window.h))
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

run_once :: proc(frame: proc()) {
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

get_mouse :: proc() -> (f32, f32) {
	return f32(ctx.mouse_pos.x), f32(ctx.mouse_pos.y)
}

get_mouse_scroll :: proc() -> f32 {
	return f32(ctx.mouse_scroll)
}

delta_time :: proc() -> f32 {
	return ctx.delta_time
}

time :: proc() -> f32 {
	return ctx.timer
}

set_char_callback :: proc(callback: proc(char: rune)) {
	ctx.text_callback = callback
}

window_size :: proc() -> (f32, f32) {
	return f32(ctx.window.w), f32(ctx.window.h)
}

is_resizing :: proc() -> bool {
	return ctx.is_resizing
}

is_hovering_files :: proc() -> bool {
	return ctx.is_hovering_files
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
