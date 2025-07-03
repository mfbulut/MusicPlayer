package main

import "fx"

compact_mode_frame :: proc() {
	window_w, window_h := fx.window_size()

    fx.draw_gradient_rect_rounded_vertical(0, 0, f32(window_w), f32(window_h), 8, BACKGROUND_GRADIENT_BRIGHT, BACKGROUND_GRADIENT_DARK)

	cover := player.current_track.audio_clip.cover

	if !player.current_track.audio_clip.has_cover && len(player.current_track.playlist) > 0 {
		playlist := find_playlist_by_name(player.current_track.playlist)
		cover = playlist.cover
	}

	startX: f32 = 20
	if cover.width > 0 {
		fx.draw_texture_rounded_cropped(cover, 0, 0, f32(window_h), f32(window_h), 12, fx.WHITE)
		startX += window_h
	}

	selected_title := player.current_track.audio_clip.tags.title if player.current_track.audio_clip.has_tags else player.current_track.name
	selected_album := player.current_track.audio_clip.tags.album if player.current_track.audio_clip.has_tags else player.current_track.playlist

	track_title := truncate_text(selected_title, f32(window_w) - startX, 28)
	fx.draw_text(track_title, startX, 15, 32, UI_TEXT_COLOR)

	track_playlist := truncate_text(selected_album, f32(window_w) - startX, 20)
	fx.draw_text(track_playlist, startX + 5, 55, 18, UI_TEXT_SECONDARY)

	progress := player.duration > 0 ? player.position / player.duration : 0
	fx.draw_rect(0, window_h - 1, f32(window_w) * progress, 1, UI_TEXT_COLOR)

	if draw_icon_button_rect(f32(window_w) - 50, 0, 50, 25, exit_icon, fx.BLANK, fx.Color{150, 48, 64, 255}, true) {
		fx.close_window()
	}

	if draw_icon_button_rect(f32(window_w) - 100, 0, 50, 25, minimize_icon, fx.BLANK, set_alpha(UI_SECONDARY_COLOR, 0.7), false, 6) {
		fx.minimize_window()
	}
}