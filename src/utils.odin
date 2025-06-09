package main

import fx "../fx"

import "core:fmt"

Button :: struct {
    x, y, w, h: f32,
    text: string,
    color: fx.Color,
    hover_color: fx.Color,
    text_color: fx.Color,
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


    copy(truncated_text_buffer[:target_len-3], text[:target_len-3])
    copy(truncated_text_buffer[target_len-3:target_len], "...")
    truncated_text_buffer[target_len] = 0

    return string(truncated_text_buffer[:target_len])
}

draw_button :: proc(btn: Button, text_offset := 0) -> bool {
    mouse_x, mouse_y := fx.get_mouse()
    is_hovered := is_hovering(btn.x, btn.y, btn.w, btn.h)

    is_valid := is_valid(f32(mouse_x), f32(mouse_y))

    is_clickled := is_hovered && fx.mouse_pressed(.LEFT) && is_valid

    color := btn.color
    if is_hovered && is_valid {
        color = btn.hover_color
        fx.set_cursor(.CLICK)
    }

    fx.draw_gradient_rect_rounded_vertical(btn.x, btn.y, btn.w, btn.h, 8, color, darken(color, 20))

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
    return is_clickled
}


draw_icon_button_rect :: proc(x, y, w, h : f32, icon: fx.Texture, color: fx.Color, hover_color: fx.Color, is_exit:= false, padding : f32 = 6) -> bool {
    is_hovered := is_hovering(x, y, w, h)

    is_clickled := is_hovered && fx.mouse_pressed(.LEFT)

    color := color
    if is_hovered {
        color = hover_color
    }

    if is_exit {
        fx.draw_gradient_rect_rounded_horizontal_selective(x, y, w, h, 8, color, color, {.TOP_RIGHT})
    } else {
        fx.draw_rect(x, y, w, h, color)
    }

    size := h - padding * 2

    fx.draw_texture(icon, x + w / 2 - size / 2, y + padding, size, size, fx.Color{215, 215, 230, 196})

    return is_clickled
}

IconButton :: struct {
    x, y, size: f32,
    icon: fx.Texture,
    color: fx.Color,
    hover_color: fx.Color,
}

draw_icon_button :: proc(btn: IconButton) -> bool {
    is_hovered := is_hovering(btn.x, btn.y, btn.size, btn.size)

    color := btn.color
    if is_hovered {
        color = btn.hover_color
        fx.set_cursor(.CLICK)
    }

    fx.draw_gradient_circle_radial(btn.x + btn.size/2, btn.y + btn.size/2, btn.size/2, brighten(color, 10), color)

    padding :: 10
    fx.draw_texture(btn.icon, btn.x + padding, btn.y + padding, btn.size - padding * 2, btn.size - padding * 2, UI_TEXT_COLOR)

    return is_hovered && fx.mouse_pressed(.LEFT)
}

ProgressBar :: struct {
    x, y, w, h: f32,
    progress: f32,
    color: fx.Color,
    bg_color: fx.Color,
}

draw_progress_bar :: proc(bar: ProgressBar){
    mouse_x, _ := fx.get_mouse()
    progress_width := bar.w * bar.progress

    if fx.mouse_held(.LEFT) && is_hovering(bar.x - 30, bar.y - 10, bar.w + 60, bar.h + 20) {
        progress_width = (f32(mouse_x) - bar.x)
        seek_to_position(progress_width / bar.w * player.duration)
    }

    fx.draw_rect_rounded(bar.x, bar.y, bar.w, bar.h, bar.h/2, bar.bg_color)

    if bar.progress > 0 {
        fx.draw_rect_rounded(bar.x, bar.y, progress_width, bar.h, bar.h/2, bar.color)
    }
}

draw_slider :: proc(x, y, w, h: f32, value: f32, bg_color, fg_color: fx.Color) -> f32 {
    handle_x := x + (w - h) * value

    mouse_x, _ := fx.get_mouse()

    if is_hovering(x - 10, y - 30, w + 20, h + 60) {
        fx.draw_rect_rounded(x, y, w, h, h/2,  brighten(bg_color))
        fx.draw_rect_rounded(x, y, handle_x - x + 4, h, h/2, brighten(fg_color))
        fx.draw_circle(handle_x + 2, y + h / 2, 4, brighten(fg_color))

        if fx.mouse_held(.LEFT) {
            new_value := (f32(mouse_x) - x) / w
            return clamp(new_value, 0, 1)
        }
    } else {
        fx.draw_rect_rounded(x, y, w, h, h/2,  bg_color)
        fx.draw_rect_rounded(x, y, handle_x - x + 4, h, h/2, darken(fg_color, 30))
        fx.draw_circle(handle_x + 2, y + h / 2, 4, darken(fg_color, 30))
    }

    return value
}

format_time :: proc(seconds: f32) -> string {
    mins := int(seconds) / 60
    secs := int(seconds) % 60
    return fmt.tprintf("%d:%02d", mins, secs)
}

valid_rect : [4]f32 = {0, 0, 1280, 720}

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


draw_scrollbar :: proc(scrollbar: ^Scrollbar, x, y, w, h: f32, max_scroll: f32, bg_color: fx.Color, thumb_color: fx.Color) -> bool {
    if max_scroll <= 0 {
        return false
    }

    fx.draw_rect_rounded(x, y, w, h, w/2, bg_color)

    thumb_size := max(20, h * (h / (h + max_scroll)))
    scroll_ratio := scrollbar.scroll / max_scroll
    thumb_y := y + (h - thumb_size) * scroll_ratio

    mouse_x, mouse_y := fx.get_mouse()
    is_over_thumb := is_inside(f32(mouse_x), f32(mouse_y), x - 10, thumb_y - 20, w + 20, thumb_size + 40)

    thumb_draw_color := thumb_color
    if is_over_thumb {
        thumb_draw_color = brighten(thumb_color, 30)
    }

    fx.draw_rect_rounded(x, thumb_y, w, thumb_size, w/2, thumb_draw_color)

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
        ui_state.sidebar_scrollbar.scroll += (ui_state.sidebar_scrollbar.target - ui_state.sidebar_scrollbar.scroll) * UI_SCROLL_SPEED * dt
    } else {
        ui_state.sidebar_scrollbar.scroll = ui_state.sidebar_scrollbar.target
    }

    if abs(ui_state.playlist_scrollbar.target - ui_state.playlist_scrollbar.scroll) > 0.5 {
        ui_state.playlist_scrollbar.scroll += (ui_state.playlist_scrollbar.target - ui_state.playlist_scrollbar.scroll) * UI_SCROLL_SPEED * dt
    } else {
        ui_state.playlist_scrollbar.scroll = ui_state.playlist_scrollbar.target
    }

    if abs(ui_state.lyrics_scrollbar.target - ui_state.lyrics_scrollbar.scroll) > 0.5 {
        ui_state.lyrics_scrollbar.scroll += (ui_state.lyrics_scrollbar.target - ui_state.lyrics_scrollbar.scroll) * UI_SCROLL_SPEED * dt
    } else {
        ui_state.lyrics_scrollbar.scroll = ui_state.lyrics_scrollbar.target
    }

    if abs(ui_state.search_scrollbar.target - ui_state.search_scrollbar.scroll) > 0.5 {
        ui_state.search_scrollbar.scroll += (ui_state.search_scrollbar.target - ui_state.search_scrollbar.scroll) * UI_SCROLL_SPEED * dt
    } else {
        ui_state.search_scrollbar.scroll = ui_state.search_scrollbar.target
    }
}

darken :: proc(color : fx.Color, amount : int = 20) -> fx.Color {
    return fx.Color{u8(max(int(color.r) - amount, 0)), u8(max(int(color.g) - amount, 0)), u8(max(int(color.b) - amount, 0)), color.a}
}

brighten :: proc(color : fx.Color, amount : int = 20) -> fx.Color {
    return fx.Color{u8(min(int(color.r) + amount, 255)), u8(min(int(color.g) + amount, 255)), u8(min(int(color.b) + amount, 255)), color.a}
}

set_alpha :: proc(color : fx.Color, val : f32) -> fx.Color {
    return fx.Color{u8(f32(color.r) * val) , u8(f32(color.g) * val), u8(f32(color.b) * val), u8(val * 255)}
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
