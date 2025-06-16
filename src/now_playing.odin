package main

import fx "../fx"

draw_now_playing_view :: proc(x, y, w, h: f32) {
    track := player.current_track

    has_lyrics := len(track.lyrics) > 0

    if has_lyrics {
        ui_state.lyrics_target_progress = ui_state.show_lyrics ? 1.0 : 0.0
    } else {
        ui_state.lyrics_target_progress = 0.0
    }

    animation_speed: f32 = 8.0
    ui_state.lyrics_animation_progress += (ui_state.lyrics_target_progress - ui_state.lyrics_animation_progress) * animation_speed * fx.delta_time()

    ui_state.lyrics_animation_progress = clamp(ui_state.lyrics_animation_progress, 0.0, 1.0)

    lyrics_width_factor := ui_state.lyrics_animation_progress * 0.5
    content_split := w * (1.0 - lyrics_width_factor)

    art_size: f32 = has_lyrics ? mix(300, 250, ui_state.lyrics_animation_progress) : 300

    art_x := x + content_split/2 - art_size/2
    total_h := art_size + 135
    if has_lyrics {
        total_h += 25
    }
    art_y := y + h/2 - total_h/2

    cover := track.audio_clip.cover

    if !track.audio_clip.has_cover && len(track.playlist) > 0 {
        playlist := find_playlist_by_name(track.playlist)
        cover = playlist.cover
    }

    if cover.width > 0 {
        if update_background {
            fx.begin_render_to_texture(&background, {0, 128, 0, 0})
            fx.set_scissor(0, 0, 1024, 1024)
            fx.use_shader(blur_shader)
            fx.draw_texture_cropped(cover, 0, 0, 1024, 1024, fx.WHITE)

            fx.end_render_to_texture()
            update_background = false
        }

        fx.use_render_texture(background)

        fx.set_scissor(i32(x), i32(y), i32(w), i32(h))

        fx.draw_texture_cropped(background.tx, x, y, w, h, fx.WHITE)

        fx.draw_gradient_rect_vertical(x, y, w, h, NOW_PLAYING_BACKDROP_BRIGHT, NOW_PLAYING_BACKDROP_DARK)

        fx.disable_scissor()

        fx.draw_texture_rounded_cropped(cover, art_x, art_y, art_size, art_size, 12, fx.WHITE)
    } else {
        fx.draw_rect_rounded(art_x, art_y, art_size, art_size, 20, UI_SECONDARY_COLOR)
    }

    selected_title := track.audio_clip.tags.title if track.audio_clip.has_tags else track.name
    selected_album := track.audio_clip.tags.album if track.audio_clip.has_tags else track.playlist

    info_y := art_y + art_size + 30
    track_name := truncate_text(selected_title, content_split - 50, 24)
    track_name_width := fx.measure_text(track_name, 24)
    fx.draw_text(track_name, x + content_split/2 - track_name_width/2, info_y, 24, UI_TEXT_COLOR)

    playlist_name := truncate_text(selected_album, content_split - 50, 16)
    playlist_name_width := fx.measure_text(playlist_name, 16)
    fx.draw_text(playlist_name, x + content_split/2 - playlist_name_width/2, info_y + 30, 16, UI_TEXT_SECONDARY)

    if is_hovering(x + content_split/2 - playlist_name_width/2, info_y + 30, playlist_name_width, 18) {
        fx.set_cursor(.CLICK)

        if fx.mouse_pressed(.LEFT) {
                ui_state.selected_playlist = track.playlist
                ui_state.current_view = .PLAYLIST_DETAIL
                ui_state.playlist_scrollbar.scroll = 0
                ui_state.playlist_scrollbar.target = 0
        }
    }

    progress_y := info_y + 70

    progress_w: f32 = min(400, content_split - 60)
    progress_x := x + content_split/2 - progress_w/2

    progress := player.duration > 0 ? player.position / player.duration : 0

    progress_bar := ProgressBar{
        x = progress_x, y = progress_y, w = progress_w, h = 5,
        progress = progress,
        color = UI_TEXT_COLOR,
        bg_color = darken(UI_SECONDARY_COLOR),
    }

    draw_progress_bar(progress_bar)

    current_time := format_time(player.position)
    total_time := format_time(player.duration)

    fx.draw_text(current_time, progress_x, progress_y + 12, 16, UI_TEXT_SECONDARY)
    total_time_width := fx.measure_text(total_time, 16)
    fx.draw_text(total_time, progress_x + progress_w - total_time_width, progress_y + 12, 16, UI_TEXT_SECONDARY)

    if has_lyrics {
        toggle_text := ui_state.show_lyrics ? "Hide Lyrics" : "Show Lyrics"
        toggle_width := fx.measure_text(toggle_text, 14) + 6

        toggle_btn := Button{
            x = x + content_split/2 - toggle_width/2 - 10,
            y = progress_y + 30,
            w = toggle_width + 30,
            h = 35,
            text = toggle_text,
            color = set_alpha(UI_SECONDARY_COLOR, 0.4),
            hover_color = set_alpha(UI_HOVER_COLOR, 0.4),
            text_color = set_alpha(UI_TEXT_SECONDARY, 0.8),
        }

        if draw_button(toggle_btn) {
            ui_state.show_lyrics = !ui_state.show_lyrics
        }
    }

    if has_lyrics && ui_state.lyrics_animation_progress > 0.001 {
        lyrics_panel_w := (w * 0.5 - 40)
        lyrics_panel_x := x + content_split + 20 + (w - content_split - 40 - lyrics_panel_w) + (1 - ui_state.lyrics_animation_progress) * w * 0.5
        lyrics_panel_y := y + 40
        lyrics_panel_h := h - 80

        lyrics_alpha := ui_state.lyrics_animation_progress

        if lyrics_panel_w > 10 {
            draw_lyrics(lyrics_panel_x, lyrics_panel_y, lyrics_panel_w, lyrics_panel_h, &track, lyrics_alpha)
        }
    }

    window_w, window_h := fx.window_size()
    interaction_rect(0, 0, f32(window_w), f32(window_h))
}

mix :: proc(a, b, t: f32) -> f32 {
    return a + (b - a) * t
}

LYRIC_HEIGHT :: 48
LYRIC_FONT_SIZE :: 18

draw_lyrics :: proc(x, y, w, h: f32, track: ^Track, alpha: f32) {
    fx.draw_gradient_rect_rounded_vertical(x, y, w, h, 12,
        set_alpha(BACKGROUND_GRADIENT_BRIGHT, 0.85 * alpha),
        set_alpha(BACKGROUND_GRADIENT_DARK, 0.75 * alpha))

    content_y := y + 10
    content_h := h - 20

    total_line_height: f32 = 0
    avg_line_height: f32 = LYRIC_HEIGHT
    line_height: f32 = LYRIC_HEIGHT

    fx.set_scissor(i32(x + 10), i32(y), i32(w - 25), i32(h))
    interaction_rect(x + 10, content_y, w - 25, content_h)

    current_lyric_index := get_current_lyric_index(track.lyrics[:], player.position)

    if fx.key_pressed(.LEFT) {
        seek_to_lyric(max(current_lyric_index - 1, 0), track.lyrics[:])
        ui_state.follow_lyrics = true
    }

    if fx.key_pressed(.RIGHT) {
        seek_to_lyric(min(current_lyric_index + 1, len(track.lyrics) - 1), track.lyrics[:])
        ui_state.follow_lyrics = true
    }

    ui_state.lyrics_scrollbar.scroll = max(ui_state.lyrics_scrollbar.scroll, 0)
    line_y := content_y + 15 - ui_state.lyrics_scrollbar.scroll

    line_heights := make([]f32, len(track.lyrics), context.temp_allocator)
    for lyric, i in track.lyrics {
        text_width := fx.measure_text(lyric.text, LYRIC_FONT_SIZE)

        if text_width < w - 60 {
            line_heights[i] = LYRIC_HEIGHT
        } else {
            line_heights[i] = LYRIC_HEIGHT * 1.6
        }

        total_line_height += line_heights[i]
    }

    if current_lyric_index > 0 {
        sum: f32 = 0
        for i in 0..<current_lyric_index {
            sum += line_heights[i]
        }
        avg_line_height = sum / f32(current_lyric_index)
    }

    for lyric, i in track.lyrics {
        current_line_height := line_heights[i]

        if line_y > content_y + content_h + 20 {
            line_y += current_line_height
            continue
        }

        if line_y + current_line_height < content_y - 20 {
            line_y += current_line_height
            continue
        }

        is_current := i == current_lyric_index
        is_past := i < current_lyric_index
        is_future := i > current_lyric_index
        is_hovering := is_hovering(x + 15, line_y, w - 35, current_line_height)

        text_color := UI_TEXT_SECONDARY

        if is_current {
            text_color = set_alpha(UI_TEXT_COLOR, alpha)
        } else if is_past {
            text_color = set_alpha(UI_TEXT_SECONDARY, 0.55 * alpha)
        } else if is_future {
            text_color = set_alpha(UI_TEXT_SECONDARY, 0.75 * alpha)
        }

        if is_hovering && !is_current {
            text_color = set_alpha(UI_TEXT_COLOR, 0.8 * alpha)
            fx.set_cursor(.CLICK)
        }

        if is_current {
            fx.draw_circle(x + 15, line_y + current_line_height / 2 + 1, 2.5,  set_alpha(UI_SECONDARY_COLOR, alpha))
        }

        text_x := x + (is_current ? 28 : 25)
        text_y := line_y + (current_line_height - LYRIC_FONT_SIZE) / 2

        if current_line_height > LYRIC_HEIGHT {
            text_y = line_y + (current_line_height - LYRIC_FONT_SIZE * 2 - 4) / 2
        }

        fx.draw_text_wrapped(lyric.text, text_x, text_y, w - 60, LYRIC_FONT_SIZE, text_color)

        if fx.mouse_pressed(.LEFT) && is_hovering {
            seek_to_lyric(i, track.lyrics[:])
            ui_state.follow_lyrics = true
        }

        line_y += current_line_height
    }

    fx.disable_scissor()

    lyrics_max_scroll := max(0, total_line_height - content_h + 30)
    ui_state.lyrics_scrollbar.target = clamp(ui_state.lyrics_scrollbar.target, 0, lyrics_max_scroll)
    ui_state.lyrics_scrollbar.scroll = clamp(ui_state.lyrics_scrollbar.scroll, 0, lyrics_max_scroll)

    if lyrics_max_scroll > 0 {
        scrollbar_x := x + w - 15
        scrollbar_y := content_y
        scrollbar_h := content_h

        draw_scrollbar(&ui_state.lyrics_scrollbar, scrollbar_x, scrollbar_y, 4, scrollbar_h, lyrics_max_scroll, set_alpha(UI_PRIMARY_COLOR, 0.8), set_alpha(UI_SECONDARY_COLOR, 0.6))

        if ui_state.lyrics_scrollbar.is_dragging {
            ui_state.follow_lyrics = false
        }
    }

    if ui_state.follow_lyrics && current_lyric_index >= 0 && current_lyric_index < len(track.lyrics) {
        current_lyric_pos: f32 = 0
        for i in 0..<current_lyric_index {
            current_lyric_pos += line_heights[i]
        }

        target_scroll := current_lyric_pos - content_h/2 + line_heights[current_lyric_index]/2
        target_scroll = clamp(target_scroll, 0, lyrics_max_scroll)
        ui_state.lyrics_scrollbar.target = target_scroll
    }

    scroll_delta := fx.get_mouse_scroll()
    if scroll_delta != 0 {
        if is_hovering(x + 10, content_y, w - 25, content_h) {
            ui_state.follow_lyrics = false
            ui_state.lyrics_scrollbar.target -= f32(scroll_delta) * 100
            ui_state.lyrics_scrollbar.target = clamp(ui_state.lyrics_scrollbar.target, 0, lyrics_max_scroll)
        }
    }
}