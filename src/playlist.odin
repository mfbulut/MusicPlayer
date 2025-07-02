package main

import "fx"

import "core:fmt"

draw_track_item :: proc(track: Track, playlist: Playlist, x, y, w, h: f32, queue := false) {
	hover := is_hovering(x, y, w, h)
	bg_color := UI_TRACK_COLOR

	if player.current_track.path == track.path {
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
	track_title := truncate_text(track.name, w - 70, 20)
	fx.draw_text(track_title, x + 20, y + 9, 20, text_color)
	fx.draw_text(track.playlist, x + 20, y + 35, 15, secondary_color)

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
	list_y := y + 120
	list_h := h - 120

	if playlist.loaded {
		fx.draw_texture_rounded(playlist.cover, x + 40, y + 15, 100, 100, 12, fx.WHITE)
		list_y += 10
		list_h -= 10
		playlist_title := truncate_text(playlist.name, w - 180, 32)
		fx.draw_text(playlist_title, x + 160, y + 35, 32, UI_TEXT_COLOR)
		fx.draw_text(
			fmt.tprintf("%d tracks", len(playlist.tracks)),
			x + 160,
			y + 75,
			16,
			UI_TEXT_SECONDARY,
		)
	} else {
		playlist_title := truncate_text(playlist.name, w - 60, 32)
		fx.draw_text(playlist_title, x + 40, y + 35, 32, UI_TEXT_COLOR)
		fx.draw_text(
			fmt.tprintf("%d tracks", len(playlist.tracks)),
			x + 40,
			y + 75,
			16,
			UI_TEXT_SECONDARY,
		)
	}

	track_count := len(playlist.tracks)
	track_height: f32 = 65
	playlist_max_scroll := calculate_max_scroll(track_count, track_height, list_h)

	ui_state.playlist_scrollbar.target = clamp(
		ui_state.playlist_scrollbar.target,
		0,
		playlist_max_scroll,
	)
	ui_state.playlist_scrollbar.scroll = clamp(
		ui_state.playlist_scrollbar.scroll,
		0,
		playlist_max_scroll,
	)

	fx.set_scissor(i32(x), i32(list_y), i32(w - 15), i32(list_h))

	if !ui_state.playlist_scrollbar.is_dragging {
		interaction_rect(f32(x), f32(list_y), f32(w - 15), f32(list_h - 15))
	}

	track_y := list_y - ui_state.playlist_scrollbar.scroll

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

	if playlist_max_scroll > 0 {
		indicator_x := x + w - 20
		indicator_y := list_y + 5
		indicator_h := list_h - 15

		draw_scrollbar(
			&ui_state.playlist_scrollbar,
			indicator_x,
			indicator_y,
			4,
			indicator_h,
			playlist_max_scroll,
			UI_PRIMARY_COLOR,
			UI_SECONDARY_COLOR,
		)
	}

	if !ui_state.playlist_scrollbar.is_dragging {
		window_w, window_h := fx.window_size()
		interaction_rect(0, 0, f32(window_w), f32(window_h))

		scroll_delta := fx.get_mouse_scroll()
		if scroll_delta != 0 {
			if f32(mouse_x) > x && f32(mouse_y) < y + h {
				ui_state.playlist_scrollbar.target -= f32(scroll_delta) * 80
				ui_state.playlist_scrollbar.target = clamp(
					ui_state.playlist_scrollbar.target,
					0,
					playlist_max_scroll,
				)
			}
		}
	}
}
