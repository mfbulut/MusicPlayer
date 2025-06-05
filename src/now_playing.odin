package main

import fx "../fx"

update_background: bool

draw_now_playing_view :: proc(x, y, w, h: f32) {
    track := player.current_track

    has_lyrics := len(track.lyrics) > 0

    art_size: f32 = has_lyrics && ui_state.show_lyrics ? 250 : 300
    content_split := has_lyrics && ui_state.show_lyrics ? w * 0.5 : w

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
            fx.use_texture(cover)
            fx.set_scissor(0, 0, 1024, 1024)
            fx.use_shader(use_gaussian ? gaussian_shader : bokeh_shader)
            fx.draw_texture(0, 0, 1024, 1024, fx.WHITE)

            fx.end_render_to_texture()
            update_background = false
        }

        fx.use_render_texture(background)

        fx.set_scissor(i32(x), i32(y), i32(w), i32(h))

        texture_w := cover.width
        texture_h := cover.height
        texture_aspect := f32(texture_w) / f32(texture_h)
        dest_aspect := f32(w) / f32(h)

        if texture_aspect > dest_aspect {
            new_w := h * texture_aspect
            diff := (new_w - w) / 2
            fx.draw_texture(x - diff, y, new_w, h, fx.Color{80, 80, 80, 255})
        } else {
            new_h := w / texture_aspect
            diff := (new_h - h) / 2
            fx.draw_texture(x, y - diff, w, new_h, fx.Color{80, 80, 80, 255})
        }

        fx.disable_scissor()

        fx.use_texture(cover)
        fx.draw_texture_rounded(art_x, art_y, art_size, art_size, 12, fx.WHITE)
    } else {
        fx.draw_rect_rounded(art_x, art_y, art_size, art_size, 20, UI_SECONDARY_COLOR)
    }

    info_y := art_y + art_size + 30
    track_name := truncate_text(track.name, content_split - 50, 24)
    track_name_width := fx.measure_text(track_name, 24)
    fx.draw_text(track_name, x + content_split/2 - track_name_width/2, info_y, 24, UI_TEXT_COLOR)

    playlist_name_width := fx.measure_text(track.playlist, 16)
    fx.draw_text(track.playlist, x + content_split/2 - playlist_name_width/2, info_y + 30, 16, UI_TEXT_SECONDARY)

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
        x = progress_x, y = progress_y, w = progress_w, h = 6,
        progress = progress,
        color = UI_TEXT_COLOR,
        bg_color = UI_ACCENT_COLOR, // UI_SECONDARY_COLOR
    }

    new_progress := draw_progress_bar(progress_bar)
    if new_progress >= 0 {
        seek_to_position(new_progress * player.duration)
    }

    current_time := format_time(player.position)
    total_time := format_time(player.duration)

    fx.draw_text(current_time, progress_x, progress_y + 15, 16, UI_TEXT_SECONDARY)
    total_time_width := fx.measure_text(total_time, 16)
    fx.draw_text(total_time, progress_x + progress_w - total_time_width, progress_y + 15, 16, UI_TEXT_SECONDARY)

    if has_lyrics {
        toggle_text := ui_state.show_lyrics ? "Hide Lyrics" : "Show Lyrics"
        toggle_width := fx.measure_text(toggle_text, 14) + 6
        toggle_btn := Button{
            x = x + content_split/2 - toggle_width/2 - 10,
            y = progress_y + 30,
            w = toggle_width + 30,
            h = 35,
            text = toggle_text,
            color = UI_SECONDARY_COLOR,
            hover_color = UI_HOVER_COLOR,
            text_color = UI_TEXT_SECONDARY,
        }

        if draw_button(toggle_btn) {
            ui_state.show_lyrics = !ui_state.show_lyrics
        }
    }

    total_line_height : f32 = 0
    avg_line_height : f32 = 35

    if has_lyrics && ui_state.show_lyrics {
        lyrics_x := x + content_split + 20
        lyrics_y := y + 40
        lyrics_w := w - content_split - 40
        lyrics_h := h - 60

        fx.draw_rect_rounded(lyrics_x, lyrics_y, lyrics_w, lyrics_h, 8, UI_SECONDARY_COLOR)

        lyrics_content_y := lyrics_y // ?
        lyrics_content_h := lyrics_h // ?

        line_height: f32 = 35

        fx.set_scissor(i32(lyrics_x), i32(lyrics_content_y), i32(lyrics_w - 15), i32(lyrics_content_h))

        interaction_rect(lyrics_x, lyrics_content_y, lyrics_w - 15, lyrics_content_h)

        current_lyric_index := get_current_lyric_index(track.lyrics[:], player.position)

        ui_state.lyrics_scrollbar.scroll = max(ui_state.lyrics_scrollbar.scroll, 0)
        line_y := lyrics_content_y + 10 - ui_state.lyrics_scrollbar.scroll

        for lyric, i in track.lyrics {
            len := fx.measure_text(lyric.text, 16)
            if len + 20 < lyrics_w - 35 {
                line_height = 35
            } else {
                line_height = 50
            }

            if i < current_lyric_index {
                avg_line_height += line_height
            } else if i == current_lyric_index {
                avg_line_height /= f32(i + 1)
            }

            total_line_height += line_height

            if line_y > lyrics_y + lyrics_h {
                continue
            }

            if line_y + line_height > lyrics_content_y {
                is_hovering := is_hovering(lyrics_x + 10, line_y - 5, lyrics_w - 35, line_height - 1)

                text_color := UI_TEXT_SECONDARY
                bg_color := fx.Color{0, 0, 0, 0}

                if i == current_lyric_index {
                    text_color = UI_TEXT_COLOR
                    bg_color = UI_HOVER_COLOR
                } else if is_hovering {
                    text_color = UI_TEXT_COLOR
                    bg_color = fx.Color{30, 35, 45, 128}
                    fx.set_cursor(.CLICK)
                }

                if bg_color.a > 0 {
                    fx.draw_rect_rounded(lyrics_x + 10, line_y - 5, lyrics_w - 35, line_height, 8, bg_color)
                }

                fx.draw_text_wrapped(lyric.text, lyrics_x + 20, line_y, lyrics_w - 55, 16, text_color)

                if fx.mouse_pressed(.LEFT) && is_hovering {
                    seek_to_lyric(i, track.lyrics[:])
                }
            }

            line_y += line_height
        }

        fx.disable_scissor()

        lyrics_max_scroll := total_line_height - lyrics_h + 20

        ui_state.lyrics_scrollbar.target = clamp(ui_state.lyrics_scrollbar.target, 0, lyrics_max_scroll)
        ui_state.lyrics_scrollbar.scroll = clamp(ui_state.lyrics_scrollbar.scroll, 0, lyrics_max_scroll)

        if lyrics_max_scroll > 0 {
            indicator_x := lyrics_x + lyrics_w - 12
            indicator_y := lyrics_content_y + 5
            indicator_h := lyrics_content_h - 10

            draw_scrollbar(&ui_state.lyrics_scrollbar, indicator_x, indicator_y, 4, indicator_h, lyrics_max_scroll, UI_PRIMARY_COLOR, UI_ACCENT_COLOR)

            if ui_state.lyrics_scrollbar.is_dragging {
                ui_state.follow_lyrics = false
            }
        }

        if ui_state.follow_lyrics && current_lyric_index >= 0 && current_lyric_index < len(track.lyrics) {
            target_scroll := f32(current_lyric_index) * avg_line_height - lyrics_content_h/2
            target_scroll = clamp(target_scroll, 0, lyrics_max_scroll)
            ui_state.lyrics_scrollbar.target = target_scroll
        }

        scroll_delta := fx.get_mouse_scroll()
        if scroll_delta != 0 {
            if is_hovering(lyrics_x, lyrics_content_y, lyrics_w - 15, lyrics_content_h) {
                ui_state.follow_lyrics = false

                ui_state.lyrics_scrollbar.target -= f32(scroll_delta) * 80
                ui_state.lyrics_scrollbar.target = clamp(ui_state.lyrics_scrollbar.target, 0, lyrics_max_scroll)
            }
        }
    }

    window_w, window_h := fx.window_size()
    interaction_rect(0, 0, f32(window_w), f32(window_h))
}