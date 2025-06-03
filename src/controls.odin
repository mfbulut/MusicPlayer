package main

import fx "../fx"

import "core:strings"
import "core:math"

handle_time_drag :: proc(time_x, time_y, time_width, time_height: f32) {
    mouse_x, mouse_y := fx.get_mouse()

    is_hovering := is_hovering(time_x, time_y, time_width, time_height)

    if fx.mouse_pressed(.LEFT) && is_hovering {
        ui_state.is_dragging_time = true
        ui_state.drag_start_time_x = f32(mouse_x)
        ui_state.drag_start_position = player.position
    }

    if !fx.mouse_held(.LEFT) {
        ui_state.is_dragging_time = false
    }

    if ui_state.is_dragging_time {
        mouse_delta := f32(mouse_x) - ui_state.drag_start_time_x

        time_delta := mouse_delta * 0.1

        new_position := ui_state.drag_start_position + time_delta
        new_position = clamp(new_position, 0, player.duration)

        seek_to_position(new_position)
    }

    if is_hovering {
        fx.set_cursor(.HORIZONTAL_RESIZE)
    }
}


draw_player_controls :: proc() {
    window_w, window_h := fx.window_size()
    player_y := f32(window_h) - player_height

    progress := player.duration > 0 ? player.position / player.duration : 0

    colors := []fx.Color{fx.Color{15, 18, 30, 255}, UI_SECONDARY_COLOR, fx.Color{15, 18, 30, 255}}
    stops := []f32{0.0, 0.5, 1.0}
    fx.draw_gradient_rect_multistop(0, player_y, f32(window_w), player_height, colors, stops)

    fx.draw_rect(0, player_y, f32(window_w), 2, UI_SECONDARY_COLOR)

    cover := player.current_track.audio_clip.cover

    if !player.current_track.audio_clip.has_cover && len(player.current_track.playlist) > 0 {
        playlist := find_playlist_by_name(player.current_track.playlist)
        cover = playlist.cover
    }

    startX : f32 = 20
    if cover.width > 0 {
        fx.use_texture(cover)

        padding :: 7
        fx.draw_texture_rounded(padding, player_y + padding, player_height - padding * 2, player_height - padding * 2, 12, fx.WHITE)
        startX += 70

        mouse_x, mouse_y := fx.get_mouse()

        if is_hovering(0, player_y, player_height, player_height) {
            fx.set_cursor(.CLICK)

            if fx.mouse_pressed(.LEFT) {
                ui_state.current_view = .NOW_PLAYING
            }
        }
    }

    track_title := truncate_text(player.current_track.name, 350, 24)
    fx.draw_text(track_title, startX, player_y + 15, 24, UI_TEXT_COLOR)
    track_playlist := truncate_text(player.current_track.playlist, 350, 16)
    fx.draw_text(track_playlist, startX, player_y + 45, 16, UI_TEXT_SECONDARY)

    title_end := startX + fx.measure_text(track_title, 24)
    controls_x := f32(window_w) / 2 - 80
    controls_x = max(controls_x, title_end + 70)
    controls_y := player_y + 20

    current_time := format_time(player.position)
    total_time := format_time(player.duration)

    if player.current_track.audio_clip.loaded {
        time_text := strings.concatenate({current_time, " / ", total_time}, context.temp_allocator)
        time_width := fx.measure_text(time_text, 16)
        time_x: f32 = controls_x + 205
        time_y := player_y + 30

        handle_time_drag(time_x, time_y, time_width, 20)

        text_color := ui_state.is_dragging_time ? UI_TEXT_COLOR : UI_TEXT_SECONDARY
        fx.draw_text(time_text, time_x, time_y, 16, text_color)
    }

    prev_btn := IconButton{
        x = controls_x, y = controls_y, size = 40,
        icon = previous_icon,
        color = UI_PRIMARY_COLOR,
        hover_color = UI_HOVER_COLOR,
    }

    if draw_icon_button(prev_btn) || fx.key_pressed_global(.MEDIA_PREV_TRACK) {
        previous_track()
    }

    play_btn := IconButton{
        x = controls_x + 50, y = controls_y, size = 40,
        icon = player.state == .PLAYING ? pause_icon : play_icon,
        color = UI_ACCENT_COLOR,
        hover_color = UI_HOVER_COLOR,
    }

    if draw_icon_button(play_btn) || fx.key_pressed_global(fx.Key.MEDIA_PLAY_PAUSE) {
        toggle_playback()
    }

    next_btn := IconButton{
        x = controls_x + 100, y = controls_y, size = 40,
        icon = forward_icon,
        color = UI_PRIMARY_COLOR,
        hover_color = UI_HOVER_COLOR,
    }

    if draw_icon_button(next_btn) || fx.key_pressed_global(.MEDIA_NEXT_TRACK) {
        next_track()
    }

    shuffle_btn := IconButton{
        x = controls_x - 50, y = controls_y, size = 40,
        icon = shuffle_icon,
        color = player.shuffle ? UI_ACCENT_COLOR : UI_PRIMARY_COLOR,
        hover_color = player.shuffle ? brighten(UI_ACCENT_COLOR) : UI_HOVER_COLOR,
    }

    if draw_icon_button(shuffle_btn) {
        toggle_shuffle()
    }

    is_liked := is_song_liked(player.current_track.name, player.current_track.playlist)

    heart_btn := IconButton{
        x = controls_x + 150, y = controls_y, size = 40,
        icon = is_liked ? liked_icon : liked_empty,
        color = UI_PRIMARY_COLOR,
        hover_color = UI_HOVER_COLOR,
    }

    if draw_icon_button(heart_btn) && player.current_track.audio_clip.loaded {
        toggle_song_like(player.current_track.name, player.current_track.playlist)
    }

    volume_x := f32(window_w) - 150
    volume_y := player_y + 35

    fx.use_texture(volume_icon)
    fx.draw_texture(volume_x - 30, volume_y - 8, 24, 24, fx.WHITE)

    new_volume := draw_slider(volume_x, volume_y, 100, 8, player.volume, UI_ACCENT_COLOR, UI_TEXT_COLOR)
    if new_volume != player.volume && !ui_state.is_dragging_time {
        player.volume = new_volume
        fx.set_volume(&player.current_track.audio_clip, math.pow(player.volume, 2.0))
    }

    fx.draw_rect(0, player_y, f32(window_w) * progress, 1, UI_TEXT_COLOR)
}