package main

import "fx"

import "core:fmt"
import "core:math"

compact_mode_frame :: proc() {
	if fx.key_pressed(.MEDIA_PREV_TRACK) {
		previous_track()
	}

	if fx.key_pressed(fx.Key.MEDIA_PLAY_PAUSE) || fx.key_pressed(.SPACE) {
		toggle_playback()
	}

	if fx.key_pressed(.MEDIA_NEXT_TRACK) {
		next_track()
	}

	if fx.key_pressed(.UP) {
		player.volume = min(player.volume + 0.05, 1)
		fx.set_volume(&player.current_track.audio_clip, math.pow(player.volume, 2.0))
	}

	if fx.key_pressed(.DOWN) {
		player.volume = max(player.volume - 0.05, 0)
		fx.set_volume(&player.current_track.audio_clip, math.pow(player.volume, 2.0))
	}

	window_w, window_h := fx.window_size()

    fx.draw_gradient_rect_rounded_vertical(0, 0, f32(window_w), f32(window_h), 8, BACKGROUND_GRADIENT_BRIGHT, BACKGROUND_GRADIENT_DARK)

	cover := player.current_track.audio_clip.cover

	if !player.current_track.audio_clip.has_cover && len(player.current_track.playlist) > 0 {
		playlist := find_playlist_by_name(player.current_track.playlist)
		cover = playlist.cover
	}

	startX: f32 = 20
	if cover.width > 0 {
		fx.draw_texture_rounded_cropped(cover, 0, 0, f32(window_h), f32(window_h), 8, fx.WHITE)
		startX += window_h
	}

	selected_title := player.current_track.audio_clip.tags.title if player.current_track.audio_clip.has_tags else player.current_track.name
	selected_album := player.current_track.audio_clip.tags.album if player.current_track.audio_clip.has_tags else player.current_track.playlist

	track_title := truncate_text(selected_title, f32(window_w) - startX - 50, 28)
	fx.draw_text(track_title, startX, 15, 28, UI_TEXT_COLOR)

	track_playlist := truncate_text(selected_album, f32(window_w) - startX - 50, 16)
	fx.draw_text(track_playlist, startX + 2, 55, 16, UI_TEXT_SECONDARY)

	progress := player.duration > 0 ? player.position / player.duration : 0
	fx.draw_rect(10, window_h - 1, f32(window_w - 20) * progress, 1, UI_TEXT_COLOR)

	if next_track, ok := get_next_track(); ok {
		fx.draw_text(fmt.tprintf("Next track: %s\n", next_track.name), startX + 2, 85, 16, UI_TEXT_SECONDARY)
	}

	if draw_icon_button_rect(f32(window_w) - 50, 0, 50, 25, exit_icon, fx.BLANK, fx.Color{150, 48, 64, 255}, true) {
		fx.close_window()
	}

	if draw_icon_button_rect(f32(window_w) - 100, 0, 50, 25, minimize_icon, fx.BLANK, set_alpha(UI_SECONDARY_COLOR, 0.7), false, 6) {
		fx.minimize_window()
	}
}