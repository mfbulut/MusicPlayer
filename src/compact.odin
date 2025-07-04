package main

import "fx"

import "core:fmt"
import "core:math"

compact_mode_frame :: proc() {
	window_w, window_h := fx.window_size()

    fx.draw_gradient_rect_rounded_vertical(0, 0, window_w, window_h, 8, BACKGROUND_GRADIENT_BRIGHT, BACKGROUND_GRADIENT_DARK)

	if fx.key_pressed_global(.MEDIA_PREV_TRACK) || fx.key_pressed(.LEFT) {
		previous_track()
	}

	if fx.key_pressed_global(fx.Key.MEDIA_PLAY_PAUSE) || fx.key_pressed(.SPACE) {
		toggle_playback()
	}

	next_btn := IconButton {
		x           = window_w - 50,
		y           = window_h - 50,
		size        = 40,
		icon        = forward_icon,
		color       = UI_PRIMARY_COLOR,
		hover_color = UI_HOVER_COLOR,
	}

	if draw_icon_button(next_btn) || fx.key_pressed_global(.MEDIA_NEXT_TRACK) || fx.key_pressed(.RIGHT) {
		next_track()
	}

	if fx.key_pressed(.UP) {
		player.volume = min(player.volume + 0.05, 1)
		fx.set_volume(&player.current_track.audio, math.pow(player.volume, 2.0))
	}

	if fx.key_pressed(.DOWN) {
		player.volume = max(player.volume - 0.05, 0)
		fx.set_volume(&player.current_track.audio, math.pow(player.volume, 2.0))
	}

	scroll_delta := fx.get_mouse_scroll()
	if scroll_delta != 0 {
		if is_hovering(0, 0, window_w, window_h) {
			player.volume = clamp(player.volume + scroll_delta * 0.05, 0, 1)
			fx.set_volume(&player.current_track.audio, math.pow(player.volume, 2.0))
		}
	}

	cover := player.current_track.cover

	if !player.current_track.has_cover && len(player.current_track.playlist) > 0 {
		playlist := find_playlist_by_name(player.current_track.playlist)
		cover = playlist.cover
	}

	startX: f32 = 20
	if cover.width > 0 {
		fx.draw_texture_rounded_cropped(cover, 0, 0, window_h, window_h, 8, fx.WHITE)
		startX += window_h - 5
	}

	track := player.current_track

	selected_title := track.tags.title if track.has_tags else track.name
	selected_album := track.tags.album if track.has_tags else track.playlist

	track_title := truncate_text(selected_title, window_w - startX - 50, 28)
	fx.draw_text(track_title, startX, 10, 28, UI_TEXT_COLOR)

	track_playlist := truncate_text(selected_album, window_w - startX - 50, 16)
	fx.draw_text(track_playlist, startX + 2, 50, 16, UI_TEXT_SECONDARY)

	vol_text := fmt.tprintf("%%%d", int(player.volume * 100))
	fx.draw_text(vol_text, window_w - 50 , 40, 16, UI_TEXT_SECONDARY)

	progress := player.duration > 0 ? player.position / player.duration : 0
	fx.draw_rect(10, window_h - 1, f32(window_w - 20) * progress, 1, UI_TEXT_COLOR)

	if len(track.lyrics) > 0 {
		current_lyric_index := get_current_lyric_index(track.lyrics[:], player.position)

		if current_lyric_index >= 0 {
			current_lyric := track.lyrics[current_lyric_index].text

			track_playlist := truncate_text(current_lyric, window_w - startX - 50, 16)
			fx.draw_text(current_lyric, startX + 2, 80, 16, UI_TEXT_SECONDARY)
		}
	}

	if draw_icon_button_rect(window_w - 50, 0, 50, 25, exit_icon, fx.BLANK, fx.Color{150, 48, 64, 255}, true) {
		fx.close_window()
	}

	if draw_icon_button_rect(window_w - 100, 0, 50, 25, minimize_icon, fx.BLANK, set_alpha(UI_SECONDARY_COLOR, 0.7), false, 6) {
		fx.minimize_window()
	}
}