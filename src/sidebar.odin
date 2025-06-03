package main

import fx "../fx"

draw_sidebar :: proc() {
    window_w, window_h := fx.window_size()

    fx.draw_rect(0, 0, sidebar_width, f32(window_h), UI_PRIMARY_COLOR)

    y_offset: f32 = 10

    search_btn := Button{
        x = 20, y = y_offset, w = sidebar_width - 40, h = 40,
        text = "Search",
        color = ui_state.current_view == .SEARCH ? UI_ACCENT_COLOR : UI_SECONDARY_COLOR,
        hover_color = ui_state.current_view == .SEARCH ? brighten(UI_ACCENT_COLOR) : UI_HOVER_COLOR,
        text_color = UI_TEXT_COLOR,
    }

    if draw_button(search_btn) {
        ui_state.current_view = .SEARCH
    }

    y_offset += 50

    now_playing_btn := Button{
        x = 20, y = y_offset, w = sidebar_width - 40, h = 40,
        text = "Now Playing",
        color = ui_state.current_view == .NOW_PLAYING ? UI_ACCENT_COLOR : UI_SECONDARY_COLOR,
        hover_color = ui_state.current_view == .NOW_PLAYING ? brighten(UI_ACCENT_COLOR) : UI_HOVER_COLOR,
        text_color = UI_TEXT_COLOR,
    }

    if draw_button(now_playing_btn) {
        ui_state.current_view = .NOW_PLAYING
    }

    y_offset += 50

    liked_btn := Button{
        x = 20, y = y_offset, w = sidebar_width - 40, h = 40,
        text = "Liked",
        color = ui_state.current_view == .LIKED ? UI_ACCENT_COLOR : UI_SECONDARY_COLOR,
        hover_color = ui_state.current_view == .LIKED ? brighten(UI_ACCENT_COLOR) : UI_HOVER_COLOR,
        text_color = UI_TEXT_COLOR,
    }

    if draw_button(liked_btn) {
        get_all_liked_songs()
        ui_state.current_view = .LIKED
    }

    y_offset += 50

    fx.draw_text_aligned("Your Playlists", sidebar_width / 2, y_offset, 16, UI_TEXT_SECONDARY, .CENTER)
    y_offset += 30

    playlist_count := len(playlists)
    sidebar_visible_height := f32(window_h) - y_offset - player_height
    sidebar_max_scroll := calculate_max_scroll(playlist_count, 40, sidebar_visible_height)

    ui_state.sidebar_scrollbar.target = clamp(ui_state.sidebar_scrollbar.target, 0, sidebar_max_scroll)
    ui_state.sidebar_scrollbar.scroll = clamp(ui_state.sidebar_scrollbar.scroll, 0, sidebar_max_scroll)

    fx.set_scissor(0, i32(y_offset), i32(sidebar_width - 15), i32(sidebar_visible_height))

    if !ui_state.sidebar_scrollbar.is_dragging {
        interaction_rect(0, f32(y_offset), f32(sidebar_width - 15), sidebar_visible_height)
    }

    scroll_y := y_offset - ui_state.sidebar_scrollbar.scroll

    for playlist in playlists {
        if scroll_y > f32(window_h) {
            break
        }

        if scroll_y + 35 > y_offset {
            playlist_btn := Button{
                x = 20, y = scroll_y, w = sidebar_width - 40, h = 35,
                text = playlist.name,
                color = ui_state.selected_playlist == playlist.name ? UI_ACCENT_COLOR : UI_SECONDARY_COLOR,
                hover_color = ui_state.selected_playlist == playlist.name ? brighten(UI_ACCENT_COLOR) : UI_HOVER_COLOR,
                text_color = UI_TEXT_COLOR,
            }

            if draw_button(playlist_btn) {
                ui_state.selected_playlist = playlist.name
                ui_state.current_view = .PLAYLIST_DETAIL
                ui_state.playlist_scrollbar.scroll = 0
                ui_state.playlist_scrollbar.target = 0
            }
        }

        scroll_y += 40
    }

    fx.disable_scissor()

    if sidebar_max_scroll > 0 {
        indicator_x := sidebar_width - 15
        indicator_y := y_offset
        indicator_h := sidebar_visible_height - 2

        draw_scrollbar(&ui_state.sidebar_scrollbar, indicator_x, indicator_y, 4, indicator_h, sidebar_max_scroll, UI_PRIMARY_COLOR, UI_ACCENT_COLOR)
    }

    if !ui_state.sidebar_scrollbar.is_dragging {
        interaction_rect(0, 0, f32(window_w), f32(window_h))

        scroll_delta := fx.get_mouse_scroll()
        if scroll_delta != 0 {
            mouse_x, _ := fx.get_mouse()
            if f32(mouse_x) < sidebar_width {
                ui_state.sidebar_scrollbar.target -= f32(scroll_delta) * 80
                ui_state.sidebar_scrollbar.target = clamp(ui_state.sidebar_scrollbar.target, 0, sidebar_max_scroll)
            }
        }
    }
}