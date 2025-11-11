package main

import "fx"

draw_sidebar :: proc(x_offset: f32) {
	sidebar_sc  := &ui_state.sidebar_scrollbar

	window_w, window_h := fx.window_size()

	y_offset: f32 = 20

	search_btn := Button {
		x           = 20 + x_offset,
		y           = y_offset,
		w           = SIDEBAR_WIDTH - 40,
		h           = 40,
		text        = "  Search",
		color       = ui_state.current_view == .SEARCH ? UI_ACCENT_COLOR : UI_SECONDARY_COLOR,
		hover_color = ui_state.current_view == .SEARCH ? brighten(UI_ACCENT_COLOR) : UI_HOVER_COLOR,
		text_color  = UI_TEXT_COLOR,
		expand      = true,
	}

	if draw_button(search_btn, 40) {
		ui_state.current_view = .SEARCH
	}

	fx.draw_texture(
		search_icon,
		search_btn.x + 20,
		search_btn.y + search_btn.h / 2 - 8,
		16,
		16,
		UI_TEXT_COLOR,
	)

	y_offset += 50

	now_playing_btn := Button {
		x           = 20 + x_offset,
		y           = y_offset,
		w           = SIDEBAR_WIDTH - 40,
		h           = 40,
		text        = "  Now Playing",
		color       = ui_state.current_view == .NOW_PLAYING ? UI_ACCENT_COLOR : UI_SECONDARY_COLOR,
		hover_color = ui_state.current_view == .NOW_PLAYING ? brighten(UI_ACCENT_COLOR) : UI_HOVER_COLOR,
		text_color  = UI_TEXT_COLOR,
		expand      = true,
	}

	if draw_button(now_playing_btn, 40) {
		ui_state.current_view = .NOW_PLAYING
	}

	fx.draw_texture(
		play_icon,
		now_playing_btn.x + 20,
		now_playing_btn.y + now_playing_btn.h / 2 - 8,
		16,
		16,
		UI_TEXT_COLOR,
	)

	y_offset += 50

	liked_btn := Button {
		x           = 20 + x_offset,
		y           = y_offset,
		w           = SIDEBAR_WIDTH - 40,
		h           = 40,
		text        = "  Liked",
		color       = ui_state.current_view == .LIKED ? UI_ACCENT_COLOR : UI_SECONDARY_COLOR,
		hover_color = ui_state.current_view == .LIKED ? brighten(UI_ACCENT_COLOR) : UI_HOVER_COLOR,
		text_color  = UI_TEXT_COLOR,
		expand      = true,
	}

	if draw_button(liked_btn, 40) {
		load_liked_songs()
		ui_state.current_view = .LIKED
	}

	fx.draw_texture(
		liked_icon,
		liked_btn.x + 20,
		liked_btn.y + liked_btn.h / 2 - 8,
		16,
		16,
		UI_TEXT_COLOR,
	)

	y_offset += 50

	queue_btn := Button {
		x           = 20 + x_offset,
		y           = y_offset,
		w           = SIDEBAR_WIDTH - 40,
		h           = 40,
		text        = "  Queue",
		color       = ui_state.current_view == .QUEUE ? UI_ACCENT_COLOR : UI_SECONDARY_COLOR,
		hover_color = ui_state.current_view == .QUEUE ? brighten(UI_ACCENT_COLOR) : UI_HOVER_COLOR,
		text_color  = UI_TEXT_COLOR,
		expand      = true,
	}

	if draw_button(queue_btn, 40) {
		ui_state.current_view = .QUEUE
	}

	fx.draw_texture(
		queue_icon,
		queue_btn.x + 20,
		queue_btn.y + queue_btn.h / 2 - 8,
		16,
		16,
		UI_TEXT_COLOR,
	)

	y_offset += 60

	fx.draw_text_aligned(
		"Your Playlists",
		SIDEBAR_WIDTH / 2 + x_offset,
		y_offset,
		16,
		UI_TEXT_SECONDARY,
		.CENTER,
	)

	y_offset += 30

	playlist_count := len(playlists)
	sidebar_visible_height := window_h - y_offset - PLAYER_HEIGHT
	max_scroll := calculate_max_scroll(playlist_count, 41, sidebar_visible_height)

	sidebar_sc.target = clamp(sidebar_sc.target, 0, max_scroll)
	sidebar_sc.scroll = clamp(sidebar_sc.scroll, 0, max_scroll)

	fx.set_scissor(0, y_offset, SIDEBAR_WIDTH - 15, sidebar_visible_height)

	if !sidebar_sc.is_dragging {
		interaction_rect(0, y_offset, SIDEBAR_WIDTH - 15, sidebar_visible_height)
	}

	scroll_y := y_offset - sidebar_sc.scroll

	for playlist in playlists {
		if scroll_y > window_h {
			break
		}

		if scroll_y + 40 > y_offset {
			playlist_btn := Button {
				x           = 20 + x_offset,
				y           = scroll_y,
				w           = SIDEBAR_WIDTH - 40,
				h           = 40,
				text        = playlist.name,
				color       = ui_state.selected_playlist == playlist.name ? UI_ACCENT_COLOR : UI_SECONDARY_COLOR,
				hover_color = ui_state.selected_playlist == playlist.name ? brighten(UI_ACCENT_COLOR) : UI_HOVER_COLOR,
				text_color  = UI_TEXT_COLOR,
				expand      = true,
			}

			if draw_button(playlist_btn, playlist.loaded ? 42 : 15) {
				ui_state.selected_playlist = playlist.name
				ui_state.current_view = .PLAYLIST_DETAIL
				ui_state.playlist_scrollbar.scroll = 0
				ui_state.playlist_scrollbar.target = 0
			}

			if playlist.loaded {
				fx.draw_texture_rounded(
					playlist.cover,
					x_offset + 25,
					scroll_y + 5,
					30,
					30,
					4,
					UI_TEXT_COLOR,
				)
			}
		}

		scroll_y += 46
	}

	fx.disable_scissor()

	if max_scroll > 0 {
		indicator_x := SIDEBAR_WIDTH - 7 + x_offset
		indicator_y := y_offset
		indicator_h := sidebar_visible_height - 2

		if ui_state.current_view == .NOW_PLAYING {
			indicator_x -= 3
		}
		draw_scrollbar(
			sidebar_sc,
			indicator_x,
			indicator_y,
			4,
			indicator_h,
			max_scroll,
			UI_PRIMARY_COLOR,
			UI_SECONDARY_COLOR,
		)
	}

	if !sidebar_sc.is_dragging {
		interaction_rect(0, 0, window_w, window_h)

		scroll_delta := fx.get_mouse_scroll()
		if scroll_delta != 0 {
			mouse_x, mouse_y := fx.get_mouse()
			if mouse_x < SIDEBAR_WIDTH {
				sidebar_sc.target -= scroll_delta * 80
				sidebar_sc.target = clamp(sidebar_sc.target, 0, max_scroll)
			}
		}
	}
}
