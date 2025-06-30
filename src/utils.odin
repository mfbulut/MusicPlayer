package main

import "fx"

import "core:os"
import "core:fmt"
import "core:math"
import "core:strings"
import fp "core:path/filepath"

Button :: struct {
	x, y, w, h:  f32,
	text:        string,
	color:       fx.Color,
	color_dark:  fx.Color,
	hover_color: fx.Color,
	text_color:  fx.Color,
	expand:      bool,
	gradient:    int,
}

truncated_text_buffer: [256]u8

truncate_text :: proc(text: string, max_width: f32, font_size: f32) -> string {
	text_width := fx.measure_text(text, font_size)
	if text_width <= max_width {
		return text
	}

	ratio := max_width / text_width
	target_len := int(f32(len(text)) * ratio)
	if target_len < 3 {
		return "..."
	}

	if target_len - 3 > len(truncated_text_buffer) - 4 {
		target_len = len(truncated_text_buffer) - 1
	}


	copy(truncated_text_buffer[:target_len - 3], text[:target_len - 3])
	copy(truncated_text_buffer[target_len - 3:target_len], "...")
	truncated_text_buffer[target_len] = 0

	return string(truncated_text_buffer[:target_len])
}

ANIM_ARRAY_SIZE :: 1024 * 32
g_anim_values: [ANIM_ARRAY_SIZE]f32

hash_button :: proc(x, y, w, h: u32) -> u32 {
	hash: u32 = 2166136261

	hash = hash ~ x
	hash = hash * 16777619

	hash = hash ~ y
	hash = hash * 16777619

	hash = hash ~ w
	hash = hash * 16777619

	hash = hash ~ h
	hash = hash * 16777619

	hash = hash ~ (hash >> 16)
	hash = hash * 0x85ebca6b
	hash = hash ~ (hash >> 13)
	hash = hash * 0xc2b2ae35
	hash = hash ~ (hash >> 16)

	return hash % ANIM_ARRAY_SIZE
}

draw_button :: proc(btn: Button, text_offset := 0, cursor := true) -> bool {
	mouse_x, mouse_y := fx.get_mouse()
	is_hovered := is_hovering(btn.x, btn.y, btn.w, btn.h)
	is_valid := is_valid(f32(mouse_x), f32(mouse_y))
	is_clicked := is_hovered && fx.mouse_pressed(.LEFT) && is_valid

	hash_idx := hash_button(u32(btn.x), u32(btn.y), u32(btn.w), u32(btn.h))

	target_hover := f32(1.0) if (is_hovered && is_valid) else f32(0.0)
	current_hover := &g_anim_values[hash_idx]

	animation_speed: f32 : 8.0
	dt := fx.delta_time()
	current_hover^ = lerp(current_hover^, target_hover, 1.0 - math.pow(0.01, dt * animation_speed))

	color := lerp_color(btn.color, btn.hover_color, current_hover^)

	if btn.expand {
		scale_factor := 1.0 + (current_hover^ * 0.01)
		scaled_x := btn.x - (btn.w * (scale_factor - 1.0) * 0.5)
		scaled_y := btn.y - (btn.h * (scale_factor - 1.0) * 0.5)
		scaled_w := btn.w * scale_factor
		scaled_h := btn.h * scale_factor

		fx.draw_gradient_rect_rounded_vertical(
			scaled_x,
			scaled_y,
			scaled_w,
			scaled_h,
			8,
			color,
			darken(color, 20 + btn.gradient),
		)
	} else {
		fx.draw_gradient_rect_rounded_vertical(
			btn.x,
			btn.y,
			btn.w,
			btn.h,
			8,
			color,
			darken(color, 20 + btn.gradient),
		)
	}

	if is_hovered && is_valid && false {
		fx.set_cursor(.CLICK)
	}

	text := truncate_text(btn.text, btn.w - 15, 16)
	text_x := btn.x
	text_y := btn.y + btn.h / 2 - 10

	if text_offset == 0 {
		text_x += btn.w / 2
		fx.draw_text_aligned(text, text_x, text_y, 16, btn.text_color, .CENTER)
	} else {
		text_x += f32(text_offset)
		fx.draw_text(text, text_x, text_y, 16, btn.text_color)
	}

	return is_clicked
}

draw_icon_button_rect :: proc(
	x, y, w, h: f32,
	icon: fx.Texture,
	color: fx.Color,
	hover_color: fx.Color,
	is_exit := false,
	padding: f32 = 6,
) -> bool {
	is_hovered := is_hovering(x, y, w, h)

	is_clickled := is_hovered && fx.mouse_pressed(.LEFT)

	color := color
	if is_hovered {
		color = hover_color
	}

	if is_exit {
		fx.draw_gradient_rect_rounded_horizontal_selective(
			x,
			y,
			w,
			h,
			8,
			color,
			color,
			{.TOP_RIGHT},
		)
	} else {
		fx.draw_rect(x, y, w, h, color)
	}

	size := h - padding * 2

	fx.draw_texture(
		icon,
		x + w / 2 - size / 2,
		y + padding,
		size,
		size,
		fx.Color{215, 215, 230, 196},
	)

	return is_clickled
}

IconButton :: struct {
	x, y, size:  f32,
	icon:        fx.Texture,
	color:       fx.Color,
	hover_color: fx.Color,
	expand:      bool,
}

draw_icon_button :: proc(btn: IconButton) -> bool {
	is_hovered := is_hovering(btn.x, btn.y, btn.size, btn.size)

	hash_idx := hash_button(u32(btn.x), u32(btn.y), u32(btn.size), u32(btn.size))

	target_hover := f32(1.0) if is_hovered else f32(0.0)
	current_hover := &g_anim_values[hash_idx]

	animation_speed: f32 : 8.0
	dt := fx.delta_time()
	current_hover^ = lerp(current_hover^, target_hover, 1.0 - math.pow(0.01, dt * animation_speed))

	color := lerp_color(btn.color, btn.hover_color, current_hover^)

	scale_factor: f32 = 1.0

	if btn.expand {
		scale_factor = 1.0 + (current_hover^ * 0.05)
	}

	scaled_size := btn.size * scale_factor
	offset := (scaled_size - btn.size) * 0.5
	scaled_x := btn.x - offset
	scaled_y := btn.y - offset

	if is_hovered {
		fx.set_cursor(.CLICK)
	}

	fx.draw_gradient_circle_radial(
		scaled_x + scaled_size / 2,
		scaled_y + scaled_size / 2,
		scaled_size / 2,
		brighten(color, 10),
		color,
	)

	padding :: 10
	icon_padding := padding * scale_factor
	fx.draw_texture(
		btn.icon,
		scaled_x + icon_padding,
		scaled_y + icon_padding,
		scaled_size - icon_padding * 2,
		scaled_size - icon_padding * 2,
		UI_TEXT_COLOR,
	)

	return is_hovered && fx.mouse_pressed(.LEFT)
}

previous_icon_qoi :: #load("assets/previous.qoi")
forward_icon_qoi :: #load("assets/forward.qoi")
pause_icon_qoi :: #load("assets/pause.qoi")
play_icon_qoi :: #load("assets/play.qoi")
volume_icon_qoi :: #load("assets/volume.qoi")
shuffle_icon_qoi :: #load("assets/shuffle.qoi")
search_icon_qoi :: #load("assets/search.qoi")
liked_icon_qoi :: #load("assets/liked.qoi")
empty_icon_qoi :: #load("assets/liked_empty.qoi")
queue_icon_qoi :: #load("assets/queue.qoi")
exit_icon_qoi :: #load("assets/exit.qoi")
maximize_icon_qoi :: #load("assets/maximize.qoi")
minimize_icon_qoi :: #load("assets/minimize.qoi")
music_icon_qoi :: #load("assets/music.qoi")

previous_icon: fx.Texture
forward_icon: fx.Texture
pause_icon: fx.Texture
play_icon: fx.Texture
volume_icon: fx.Texture
shuffle_icon: fx.Texture
liked_icon: fx.Texture
liked_empty: fx.Texture
search_icon: fx.Texture
queue_icon: fx.Texture
exit_icon: fx.Texture
maximize_icon: fx.Texture
minimize_icon: fx.Texture
music_icon: fx.Texture

load_icons :: proc() {
	previous_icon = fx.load_texture_from_bytes(previous_icon_qoi)
	forward_icon = fx.load_texture_from_bytes(forward_icon_qoi)
	pause_icon = fx.load_texture_from_bytes(pause_icon_qoi)
	play_icon = fx.load_texture_from_bytes(play_icon_qoi)
	volume_icon = fx.load_texture_from_bytes(volume_icon_qoi)
	shuffle_icon = fx.load_texture_from_bytes(shuffle_icon_qoi)
	liked_icon = fx.load_texture_from_bytes(liked_icon_qoi)
	search_icon = fx.load_texture_from_bytes(search_icon_qoi)
	liked_empty = fx.load_texture_from_bytes(empty_icon_qoi)
	exit_icon = fx.load_texture_from_bytes(exit_icon_qoi)
	maximize_icon = fx.load_texture_from_bytes(maximize_icon_qoi)
	minimize_icon = fx.load_texture_from_bytes(minimize_icon_qoi)
	queue_icon = fx.load_texture_from_bytes(queue_icon_qoi)
	music_icon = fx.load_texture_from_bytes(music_icon_qoi)
}

ProgressBar :: struct {
	x, y, w, h: f32,
	progress:   f32,
	color:      fx.Color,
	bg_color:   fx.Color,
}

draw_progress_bar :: proc(bar: ProgressBar) {
	mouse_x, mouse_y := fx.get_mouse()
	progress_width := bar.w * bar.progress

	hovered := is_hovering(bar.x - 10, bar.y - 10, bar.w + 20, bar.h + 25)

	if fx.mouse_pressed(.LEFT) && hovered {
		progress_width = (f32(mouse_x) - bar.x)
		seek_to_position(progress_width / bar.w * player.duration)
	}

	fx.draw_rect_rounded(bar.x, bar.y, bar.w, bar.h, bar.h / 2, bar.bg_color)

	if bar.progress > 0 {
		fx.draw_rect_rounded(bar.x, bar.y, progress_width, bar.h, bar.h / 2, bar.color)
	}

	if hovered {
		relative_x := clamp(f32(mouse_x) - bar.x, 0, bar.w)
		hover_time := relative_x / bar.w * player.duration
		time_text := format_time(hover_time)

		text_w := fx.measure_text(time_text, 14)
		popup_x := f32(mouse_x) - text_w / 2
		popup_y := bar.y - 25

		fx.draw_rect_rounded(
			popup_x - 5,
			popup_y,
			text_w + 10,
			20,
			6,
			darken(UI_PRIMARY_COLOR, 10),
		)

		fx.draw_text(time_text, popup_x, popup_y + 2, 14, fx.Color{255, 255, 255, 255})
	}
}

draw_slider :: proc(x, y, w, h: f32, value: f32, bg_color, fg_color: fx.Color) -> f32 {
	handle_x := x + (w - h) * value
	mouse_x, mouse_y := fx.get_mouse()
	is_hover := is_hovering(x - 10, y - 30, w + 20, h + 60)

	new_value := value

	if is_hover {
		fx.draw_rect_rounded(x, y, w, h, h / 2, brighten(bg_color, 10))
		fx.draw_rect_rounded(x, y, handle_x - x + 4, h, h / 2, brighten(fg_color, 10))
		fx.draw_circle(handle_x + 2, y + h / 2, 4, brighten(fg_color, 10))

		if fx.mouse_held(.LEFT) {
			new_value = clamp((f32(mouse_x) - x) / w, 0, 1)

			vol_text := fmt.tprintf("%%%d", int(new_value * 100))
			text_w := fx.measure_text(vol_text, 14)
			popup_x := f32(mouse_x) - text_w / 2
			popup_y := y - 27

			fx.draw_rect_rounded(
				popup_x - 5,
				popup_y - 1,
				text_w + 10,
				20,
				6,
				darken(UI_PRIMARY_COLOR, 10),
			)
			fx.draw_text(vol_text, popup_x, popup_y + 2, 14, fx.Color{255, 255, 255, 255})
		}
	} else {
		fx.draw_rect_rounded(x, y, w, h, h / 2, bg_color)
		fx.draw_rect_rounded(x, y, handle_x - x + 4, h, h / 2, darken(fg_color, 30))
		fx.draw_circle(handle_x + 2, y + h / 2, 4, darken(fg_color, 30))
	}

	return new_value
}


format_time :: proc(seconds: f32) -> string {
	mins := int(seconds) / 60
	secs := int(seconds) % 60
	return fmt.tprintf("%d:%02d", mins, secs)
}

valid_rect: [4]f32 = {0, 0, 1280, 720}

interaction_rect :: proc(x, y, w, h: f32) {
	valid_rect[0] = x
	valid_rect[1] = y
	valid_rect[2] = w
	valid_rect[3] = h
}

is_valid :: proc(px, py: f32) -> bool {
	x := valid_rect[0]
	y := valid_rect[1]
	w := valid_rect[2]
	h := valid_rect[3]

	return px >= x && px <= x + w && py >= y && py <= y + h
}

calculate_max_scroll :: proc(content_count: int, item_height: f32, visible_height: f32) -> f32 {
	total_content_height := f32(content_count) * item_height
	if total_content_height <= visible_height {
		return 0
	}
	return total_content_height - visible_height
}


draw_scrollbar :: proc(
	scrollbar: ^Scrollbar,
	x, y, w, h: f32,
	max_scroll: f32,
	bg_color: fx.Color,
	thumb_color: fx.Color,
) -> bool {
	if max_scroll <= 0 {
		return false
	}

	fx.draw_rect_rounded(x, y, w, h, w / 2, bg_color)

	thumb_size := max(20, h * (h / (h + max_scroll)))
	scroll_ratio := scrollbar.scroll / max_scroll
	thumb_y := y + (h - thumb_size) * scroll_ratio

	mouse_x, mouse_y := fx.get_mouse()
	is_over_thumb := is_inside(
		f32(mouse_x),
		f32(mouse_y),
		x - 10,
		thumb_y - 20,
		w + 20,
		thumb_size + 40,
	)

	thumb_draw_color := thumb_color
	if is_over_thumb {
		thumb_draw_color = brighten(thumb_color, 30)
	}

	fx.draw_rect_rounded(x, thumb_y, w, thumb_size, w / 2, thumb_draw_color)

	if fx.mouse_pressed(.LEFT) {
		if is_over_thumb {
			scrollbar.is_dragging = true
			ui_state.drag_start_mouse_y = f32(mouse_y)
			ui_state.drag_start_scroll = scrollbar.scroll
		}
	}

	if !fx.mouse_held(.LEFT) {
		scrollbar.is_dragging = false
	}

	if scrollbar.is_dragging {
		thumb_size = max(20, h * (h / (h + max_scroll)))
		available_drag_space := h - thumb_size

		mouse_delta := f32(mouse_y) - ui_state.drag_start_mouse_y

		scroll_ratio = mouse_delta / available_drag_space
		scroll_delta := scroll_ratio * max_scroll

		new_scroll := ui_state.drag_start_scroll + scroll_delta
		new_scroll = clamp(new_scroll, 0, max_scroll)

		scrollbar.scroll = new_scroll
		scrollbar.target = new_scroll
	}

	return is_over_thumb
}

UI_SCROLL_SPEED :: 20.0

update_smooth_scrolling :: proc(dt: f32) {
	if abs(ui_state.sidebar_scrollbar.target - ui_state.sidebar_scrollbar.scroll) > 0.5 {
		ui_state.sidebar_scrollbar.scroll +=
			(ui_state.sidebar_scrollbar.target - ui_state.sidebar_scrollbar.scroll) *
			UI_SCROLL_SPEED *
			dt
	} else {
		ui_state.sidebar_scrollbar.scroll = ui_state.sidebar_scrollbar.target
	}

	if abs(ui_state.playlist_scrollbar.target - ui_state.playlist_scrollbar.scroll) > 0.5 {
		ui_state.playlist_scrollbar.scroll +=
			(ui_state.playlist_scrollbar.target - ui_state.playlist_scrollbar.scroll) *
			UI_SCROLL_SPEED *
			dt
	} else {
		ui_state.playlist_scrollbar.scroll = ui_state.playlist_scrollbar.target
	}

	if abs(ui_state.lyrics_scrollbar.target - ui_state.lyrics_scrollbar.scroll) > 0.5 {
		ui_state.lyrics_scrollbar.scroll +=
			(ui_state.lyrics_scrollbar.target - ui_state.lyrics_scrollbar.scroll) *
			UI_SCROLL_SPEED *
			dt
	} else {
		ui_state.lyrics_scrollbar.scroll = ui_state.lyrics_scrollbar.target
	}

	if abs(ui_state.search_scrollbar.target - ui_state.search_scrollbar.scroll) > 0.5 {
		ui_state.search_scrollbar.scroll +=
			(ui_state.search_scrollbar.target - ui_state.search_scrollbar.scroll) *
			UI_SCROLL_SPEED *
			dt
	} else {
		ui_state.search_scrollbar.scroll = ui_state.search_scrollbar.target
	}
}

darken :: proc(color: fx.Color, amount: int = 20) -> fx.Color {
	return fx.Color {
		u8(max(int(color.r) - amount, 0)),
		u8(max(int(color.g) - amount, 0)),
		u8(max(int(color.b) - amount, 0)),
		color.a,
	}
}

brighten :: proc(color: fx.Color, amount: int = 20) -> fx.Color {
	return fx.Color {
		u8(min(int(color.r) + amount, 255)),
		u8(min(int(color.g) + amount, 255)),
		u8(min(int(color.b) + amount, 255)),
		color.a,
	}
}

lerp_color :: proc(a, b: fx.Color, t: f32) -> fx.Color {
	return fx.Color {
		r = u8(f32(a.r) + (f32(b.r) - f32(a.r)) * t),
		g = u8(f32(a.g) + (f32(b.g) - f32(a.g)) * t),
		b = u8(f32(a.b) + (f32(b.b) - f32(a.b)) * t),
		a = u8(f32(a.a) + (f32(b.a) - f32(a.a)) * t),
	}
}

lerp :: proc(a, b, t: f32) -> f32 {
	return a + (b - a) * t
}

set_alpha :: proc(color: fx.Color, val: f32) -> fx.Color {
	return fx.Color {
		u8(f32(color.r) * val),
		u8(f32(color.g) * val),
		u8(f32(color.b) * val),
		u8(val * 255),
	}
}

is_inside :: proc(px, py, x, y, w, h: f32) -> bool {
	return px >= x && px <= x + w && py >= y && py <= y + h
}

is_hovering :: proc(x, y, w, h: f32) -> bool {
	mouse_x, mouse_y := fx.get_mouse()
	px := f32(mouse_x)
	py := f32(mouse_y)

	return px >= x && px <= x + w && py >= y && py <= y + h && is_valid(px, py)
}


ease_in_out_cubic :: proc(t: f32) -> f32 {
	if t < 0.5 {
		return 4 * t * t * t
	} else {
		return 1 - math.pow(-2 * t + 2, 3) / 2
	}
}

Alert :: struct {
	image:              fx.Texture,
	title:              string,
	description:        string,
	is_visible:         bool,
	animation_progress: f32,
	target_progress:    f32,
	show_time:          f32,
	duration:           f32,
}

g_alert: Alert
ALERT_ANIMATION_SPEED :: 12.0
ALERT_DEFAULT_DURATION :: 3.0

show_alert :: proc(
	image: fx.Texture,
	title: string,
	description: string,
	duration: f32 = ALERT_DEFAULT_DURATION,
) {
	g_alert.image = image
	g_alert.title = title
	g_alert.description = description
	g_alert.is_visible = true
	g_alert.target_progress = 1.0
	g_alert.show_time = 0.0
	g_alert.duration = duration
}

update_alert :: proc(dt: f32) {
	if !g_alert.is_visible && g_alert.animation_progress <= 0.0 {
		return
	}

	if abs(g_alert.target_progress - g_alert.animation_progress) > 0.01 {
		g_alert.animation_progress +=
			(g_alert.target_progress - g_alert.animation_progress) * ALERT_ANIMATION_SPEED * dt
	} else {
		g_alert.animation_progress = g_alert.target_progress
	}

	if g_alert.is_visible {
		g_alert.show_time += dt
		if g_alert.show_time >= g_alert.duration {
			g_alert.is_visible = false
			g_alert.target_progress = 0.0
		}
	}

	if !g_alert.is_visible && g_alert.animation_progress <= 0.01 {
		g_alert.animation_progress = 0.0
	}
}

draw_alert :: proc() {
	if g_alert.animation_progress <= 0.0 {
		return
	}

	window_w, window_h := fx.window_size()
	screen_w := f32(window_w)
	screen_h := f32(window_h)

	alert_w := f32(350)
	alert_h := f32(70)
	padding := f32(20)

	alert_x :=
		screen_w - alert_w - padding + (1.0 - g_alert.animation_progress) * (alert_w + padding)
	alert_y := screen_h - alert_h - padding - 75

	bg_color := set_alpha(brighten(UI_PRIMARY_COLOR, 20), min(g_alert.animation_progress, 0.9))

	fx.draw_gradient_rect_rounded_vertical(
		alert_x,
		alert_y,
		alert_w,
		alert_h,
		12,
		brighten(bg_color, 15),
		bg_color,
	)

	content_x := alert_x + 15
	content_y := alert_y + 15

	title_color := set_alpha(fx.Color{255, 255, 255, 255}, g_alert.animation_progress)

	image_size := f32(50)
	if g_alert.image.width != 0 {
		fx.draw_texture_rounded(
			g_alert.image,
			content_x,
			content_y + (alert_h - 30 - image_size) / 2,
			image_size,
			image_size,
			8,
			title_color,
		)
		content_x += image_size + 15
	}

	text_area_w := alert_w - (content_x - alert_x) - 20

	if len(g_alert.title) > 0 {
		title_text := truncate_text(g_alert.title, text_area_w, 18)
		fx.draw_text(title_text, content_x, content_y, 18, title_color)
		content_y += 25
	}

	desc_color := set_alpha(fx.Color{200, 200, 215, 255}, g_alert.animation_progress)
	if len(g_alert.description) > 0 {
		desc_text := truncate_text(g_alert.description, text_area_w, 14)
		fx.draw_text(desc_text, content_x, content_y, 14, desc_color)
	}
}

hide_alert :: proc() {
	g_alert.is_visible = false
	g_alert.target_progress = 0.0
}

is_alert_visible :: proc() -> bool {
	return g_alert.animation_progress > 0.0
}


is_audio_file :: proc(filepath: string) -> bool {
	ext := strings.to_lower(fp.ext(filepath), context.temp_allocator)
	switch ext {
	case ".mp3", ".wav", ".flac", ".ogg", ".m4a", ".aac", ".wma", ".opus":
		return true
	case:
		return false
	}
}

is_image_file :: proc(filepath: string) -> bool {
	ext := strings.to_lower(fp.ext(filepath), context.temp_allocator)
	switch ext {
	case ".qoi", ".png", ".jpg":
		return true
	case:
		return false
	}
}

copy_file :: proc(src, dest: string) -> bool {
    data, ok := os.read_entire_file(src)
    if !ok {
        return false
    }
    defer delete(data)

    return os.write_entire_file(dest, data)
}