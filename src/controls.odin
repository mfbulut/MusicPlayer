package main

import "fx"

import "core:math"
import "core:strings"

draw_player_controls :: proc() {
	window_w, window_h := fx.window_size()
	player_y := f32(window_h) - PLAYER_HEIGHT

	fx.draw_gradient_rect_rounded_horizontal_selective(
		0,
		player_y,
		f32(window_w) / 2,
		PLAYER_HEIGHT,
		8,
		CONTROLS_GRADIENT_DARK,
		CONTROLS_GRADIENT_BRIGHT,
		{.BOTTOM_LEFT},
	)

	fx.draw_gradient_rect_rounded_horizontal_selective(
		f32(window_w) / 2,
		player_y,
		f32(window_w) / 2,
		PLAYER_HEIGHT,
		8,
		CONTROLS_GRADIENT_BRIGHT,
		CONTROLS_GRADIENT_DARK,
		{.BOTTOM_RIGHT},
	)

	cover := player.current_track.audio_clip.cover

	if !player.current_track.audio_clip.has_cover && len(player.current_track.playlist) > 0 {
		playlist := find_playlist_by_name(player.current_track.playlist)
		cover = playlist.cover
	}

	startX: f32 = 20
	if cover.width > 0 {
		padding :: 7
		fx.draw_texture_rounded_cropped(
			cover,
			padding,
			player_y + padding,
			PLAYER_HEIGHT - padding * 2,
			PLAYER_HEIGHT - padding * 2,
			12,
			fx.WHITE,
		)
		startX += 70

		if is_hovering(10, player_y, PLAYER_HEIGHT - 10, PLAYER_HEIGHT) {
			fx.set_cursor(.CLICK)

			if fx.mouse_pressed(.LEFT) {
				ui_state.current_view = .NOW_PLAYING
			}
		}
	}

	selected_title := player.current_track.audio_clip.tags.title if player.current_track.audio_clip.has_tags else player.current_track.name
	selected_album := player.current_track.audio_clip.tags.album if player.current_track.audio_clip.has_tags else player.current_track.playlist

	max_size: f32 = 320
	track_title := truncate_text(selected_title, max_size, 24)
	title_end := startX + fx.measure_text(track_title, 24)

	track_playlist := truncate_text(selected_album, max_size, 16)
	title_end = max(title_end, startX + fx.measure_text(track_playlist, 16))
	controls_x := max(title_end + 70, f32(window_w) / 2 - 80)

	if controls_x + 250 > f32(window_w) - 160 {
		controls_x = max(startX, f32(window_w) - 400)
		max_size = controls_x - startX - 90
	}

	controls_y := player_y + 20

	track_title = truncate_text(selected_title, max_size, 24)
	fx.draw_text(track_title, startX, player_y + 15, 24, UI_TEXT_COLOR)

	track_playlist = truncate_text(selected_album, max_size, 16)
	fx.draw_text(track_playlist, startX, player_y + 45, 16, UI_TEXT_SECONDARY)

	prev_btn := IconButton {
		x           = controls_x,
		y           = controls_y,
		size        = 40,
		icon        = previous_icon,
		color       = UI_PRIMARY_COLOR,
		hover_color = UI_HOVER_COLOR,
	}

	if draw_icon_button(prev_btn) || (fx.key_pressed(.MEDIA_PREV_TRACK) && !ui_state.search_focus) {
		previous_track()
	}

	play_btn := IconButton {
		x           = controls_x + 50,
		y           = controls_y,
		size        = 40,
		icon        = player.state == .PLAYING ? pause_icon : play_icon,
		color       = UI_ACCENT_COLOR,
		hover_color = UI_HOVER_COLOR,
	}

	if draw_icon_button(play_btn) || ((fx.key_pressed(fx.Key.MEDIA_PLAY_PAUSE) || fx.key_pressed(.SPACE)) && !ui_state.search_focus) {
		toggle_playback()
	}

	next_btn := IconButton {
		x           = controls_x + 100,
		y           = controls_y,
		size        = 40,
		icon        = forward_icon,
		color       = UI_PRIMARY_COLOR,
		hover_color = UI_HOVER_COLOR,
	}

	if draw_icon_button(next_btn) || (fx.key_pressed(.MEDIA_NEXT_TRACK) && !ui_state.search_focus) {
		next_track()
	}

	shuffle_btn := IconButton {
		x           = controls_x - 50,
		y           = controls_y,
		size        = 40,
		icon        = shuffle_icon,
		color       = player.shuffle ? UI_ACCENT_COLOR : UI_PRIMARY_COLOR,
		hover_color = player.shuffle ? brighten(UI_ACCENT_COLOR) : UI_HOVER_COLOR,
	}

	if draw_icon_button(shuffle_btn) {
		toggle_shuffle()
	}

	is_liked := is_song_liked(player.current_track.name, player.current_track.playlist)

	heart_btn := IconButton {
		x           = controls_x + 150,
		y           = controls_y,
		size        = 40,
		icon        = is_liked ? liked_icon : liked_empty,
		color       = UI_PRIMARY_COLOR,
		hover_color = UI_HOVER_COLOR,
	}

	if draw_icon_button(heart_btn) && player.current_track.audio_clip.loaded {
		toggle_song_like(player.current_track.name, player.current_track.playlist)
	}

	volume_x := f32(window_w) - 150
	volume_y := player_y + 38

	fx.draw_texture(volume_icon, volume_x - 35, volume_y - 10, 24, 24, UI_TEXT_COLOR)

	scroll_delta := fx.get_mouse_scroll()
	if scroll_delta != 0 {
		if is_hovering(volume_x, volume_y - 10, 100, 24) {
			player.volume = clamp(player.volume + f32(scroll_delta) * 0.05, 0, 1)
			fx.set_volume(&player.current_track.audio_clip, math.pow(player.volume, 2.0))
		}
	}

	if fx.key_pressed(.UP) {
		player.volume = min(player.volume + 0.05, 1)
		fx.set_volume(&player.current_track.audio_clip, math.pow(player.volume, 2.0))
	}

	if fx.key_pressed(.DOWN) {
		player.volume = max(player.volume - 0.05, 0)
		fx.set_volume(&player.current_track.audio_clip, math.pow(player.volume, 2.0))
	}

	new_volume := draw_slider(
		volume_x,
		volume_y,
		100,
		4,
		player.volume,
		UI_SECONDARY_COLOR,
		UI_TEXT_COLOR,
	)
	if new_volume != player.volume &&
	   !ui_state.is_dragging_time &&
	   !ui_state.is_dragging_progress &&
	   !ui_state.playlist_scrollbar.is_dragging &&
	   !ui_state.search_scrollbar.is_dragging &&
	   !ui_state.is_dragging_progress &&
	   !fx.is_resizing() {
		player.volume = new_volume
		fx.set_volume(&player.current_track.audio_clip, math.pow(player.volume, 2.0))
	}

	if player.current_track.audio_clip.loaded {
		current_time := format_time(player.position)
		total_time := format_time(player.duration)

		time_text := strings.concatenate({current_time, " / ", total_time}, context.temp_allocator)
		time_width := fx.measure_text(time_text, 16)
		time_x: f32 = volume_x - 132
		time_y := player_y + 32

		if controls_x + 200 < time_x {
			handle_time_drag(time_x, time_y, time_width, 20)

			text_color :=
				(ui_state.is_dragging_time || ui_state.is_dragging_progress) ? UI_TEXT_COLOR : UI_TEXT_SECONDARY
			fx.draw_text(time_text, time_x, time_y, 16, text_color)
		}
	}

	if player.duration > 0 {
		handle_progress_bar_drag(window_w, player_y)
	}

	progress := player.duration > 0 ? player.position / player.duration : 0
	fx.draw_rect(0, player_y, f32(window_w) * progress, 1, UI_TEXT_COLOR)
}

handle_time_drag :: proc(time_x, time_y, time_width, time_height: f32) {
	mouse_x, _ := fx.get_mouse()

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

handle_progress_bar_drag :: proc(window_w: f32, player_y: f32) {
	mouse_x, mouse_y := fx.get_mouse()

	is_over_progress := f32(mouse_y) >= player_y - 5 && f32(mouse_y) <= player_y + 15

	if fx.mouse_pressed(.LEFT) && is_over_progress && !ui_state.is_dragging_time {
		ui_state.is_dragging_progress = true
	}

	if !fx.mouse_held(.LEFT) {
		ui_state.is_dragging_progress = false
	}

	if ui_state.is_dragging_progress {
		drag_ratio := f32(mouse_x) / f32(window_w)
		drag_ratio = clamp(drag_ratio, 0, 1)

		new_position := drag_ratio * player.duration
		seek_to_position(new_position)
	} else if is_over_progress {
		fx.set_cursor(.CLICK)
	}
}
