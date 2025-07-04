package main

import "fx"

import "core:fmt"

draw_track_item :: proc(track: Track, playlist: Playlist, x, y, w, h: f32, queue := false) {
	hover := is_hovering(x, y, w, h)
	bg_color := UI_TRACK_COLOR

	if player.current_track.hash == track.hash {
		bg_color = UI_SECONDARY_COLOR
	}

	hover_color := brighten(bg_color, 8)

	track_btn := Button {
		x           = x,
		y           = y,
		w           = w,
		h           = h,
		text        = "",
		color       = bg_color,
		hover_color = hover_color,
		text_color  = UI_TEXT_COLOR,
		gradient    = -5,
	}

	draw_button(track_btn, 0, false)

	text_color := UI_TEXT_COLOR
	secondary_color := hover ? UI_TEXT_COLOR : UI_TEXT_SECONDARY

	selected_title := track.tags.title if track.has_tags && len(track.tags.title) > 0 else track.name
	selected_album := track.tags.album if track.has_tags && len(track.tags.album) > 0 else track.playlist

	startX : f32 = x + 5

	/*

	// Experimental code

	if track.cover.width > 0 {
		padding :: 8

		fx.draw_texture_rounded_cropped(
			track.cover,
			startX + padding,
			y + padding,
			h - padding * 2,
			h - padding * 2,
			12,
			fx.WHITE,
		)

		startX += 45
	}

	*/

	track_title := truncate_text(selected_title, w - 70, 20)
	fx.draw_text(track_title, startX + 15, y + 9, 20, text_color)

	track_playlist := truncate_text(selected_album, w - 70, 15)
	fx.draw_text(track_playlist, startX + 15, y + 35, 15, secondary_color)

	is_liked := is_song_liked(track.name, track.playlist)

	heart_btn := IconButton {
		x           = x + w - 60,
		y           = y + 10,
		size        = 40,
		icon        = is_liked ? liked_icon : liked_empty,
		color       = bg_color,
		hover_color = brighten(bg_color),
	}

	if len(track.playlist) > 0 && draw_icon_button(heart_btn) {
		toggle_song_like(track.name, track.playlist)
	} else if hover && fx.mouse_pressed(.LEFT) && !fx.key_held(.LEFT_CONTROL) {
		play_track(track, playlist)
		song_shuffle()
	}

	if hover && fx.mouse_pressed(.RIGHT) {
		playlist := find_playlist_by_name(track.playlist)
		if fx.key_held(.LEFT_CONTROL) {
			insert_as_next_track(track)
			show_alert(playlist.cover, track.name, "Added to the start of the queue", 1)
		} else {
			insert_as_last_track(track)
			show_alert(playlist.cover, track.name, "Added to the end of the queue", 1)
		}
	}

	if queue && hover && fx.mouse_pressed(.LEFT) && fx.key_held(.LEFT_CONTROL) {
		for q_track, i in player.queue.tracks {
			if q_track.name == track.name {
				ordered_remove(&player.queue.tracks, i)
				playlist := find_playlist_by_name(track.playlist)
				show_alert(playlist.cover, track.name, "Removed from the queue", 1)
			}
		}
	}
}

draw_playlist_view :: proc(x, y, w, h: f32, playlist: Playlist, queue := false) {
	playlist_sc := &ui_state.playlist_scrollbar

	list_y := y + 120
	list_h := h - 120

	if playlist.loaded {
		fx.draw_texture_rounded(playlist.cover, x + 40, y + 15, 100, 100, 12, fx.WHITE)
		list_y += 10
		list_h -= 10
		playlist_title := truncate_text(playlist.name, w - 180, 32)
		fx.draw_text(playlist_title, x + 160, y + 35, 32, UI_TEXT_COLOR)
		track_count := fmt.tprintf("%d tracks", len(playlist.tracks))
		fx.draw_text(track_count, x + 162, y + 75, 16, UI_TEXT_SECONDARY)
	} else {
		playlist_title := truncate_text(playlist.name, w - 60, 32)
		fx.draw_text(playlist_title, x + 40, y + 35, 32, UI_TEXT_COLOR)
		track_count := fmt.tprintf("%d tracks", len(playlist.tracks))
		fx.draw_text(track_count, x + 42, y + 75, 16, UI_TEXT_SECONDARY)
	}

	track_count  := len(playlist.tracks)
	track_height : f32 = 65
	max_scroll   := calculate_max_scroll(track_count, track_height, list_h)

	playlist_sc.target = clamp(playlist_sc.target, 0, max_scroll)
	playlist_sc.scroll = clamp(playlist_sc.scroll, 0, max_scroll)

	fx.set_scissor(x, list_y, w - 15, list_h)

	if !playlist_sc.is_dragging {
		interaction_rect(x, list_y, w - 15, list_h - 15)
	}

	track_y := list_y - playlist_sc.scroll

	mouse_x, mouse_y := fx.get_mouse()

	for i in 0 ..< len(playlist.tracks) {
		track := playlist.tracks[i]

		if queue {
			track = playlist.tracks[len(playlist.tracks) - 1 - i]
		}

		if track_y > y + h {
			break
		}

		if track_y + 60 > list_y {
			draw_track_item(track, playlist, x + 30, track_y, w - 70, 60, queue)
		}

		track_y += track_height
	}

	fx.disable_scissor()

	if max_scroll > 0 {
		indicator_x := x + w - 20
		indicator_y := list_y + 5
		indicator_h := list_h - 15

		draw_scrollbar(
			playlist_sc,
			indicator_x,
			indicator_y,
			4,
			indicator_h,
			max_scroll,
			UI_PRIMARY_COLOR,
			UI_SECONDARY_COLOR,
		)
	}

	if !playlist_sc.is_dragging {
		window_w, window_h := fx.window_size()
		interaction_rect(0, 0, window_w, window_h)

		scroll_delta := fx.get_mouse_scroll()
		if scroll_delta != 0 {
			if mouse_x > x && mouse_y < y + h {
				playlist_sc.target -= scroll_delta * 80
				playlist_sc.target = clamp(playlist_sc.target, 0, max_scroll)
			}
		}
	}
}
