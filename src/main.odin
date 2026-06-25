package main

import "fx"

import "core:strings"
import textedit "core:text/edit"

SIDEBAR_WIDTH      :: f32(240)
QUEUE_SIDEBAR_MAX  :: f32(400)
TITLE_HEIGHT       :: f32(40)
PLAYER_HEIGHT      :: f32(80)
SIDEBAR_ANIM_SPEED :: f32(4)
UI_SCROLL_SPEED    :: f32(20)

View :: enum {
	SEARCH,
	PLAYLIST_DETAIL,
	NOW_PLAYING,
	LIKED,
}

Scrollbar :: struct {
	scroll:      f32,
	target:      f32,
	is_dragging: bool,
}

UIState :: struct {
	current_view:              View,
	selected_playlist:         ^Playlist,
	playing_playlist:          ^Playlist,
	theme:                     int,
	show_lyrics:               bool,
	follow_lyrics:             bool,
	compact_mode:              bool,

	search_box:                textedit.State,
	search_builder:            strings.Builder,
	search_results:            [dynamic]^Track,
	search_playlist:           Playlist,
	search_focus:              bool,

	hide_sidebar:              bool,
	sidebar_anim:              f32,
	show_queue_sidebar:        bool,
	queue_sidebar_anim:        f32,

	lyrics_animation_progress: f32,
	drag_start_mouse_y:        f32,
	drag_start_scroll:         f32,
	drag_start_time_x:         f32,
	drag_start_position:       f32,
	is_dragging_progress:      bool,
	is_dragging_time:          bool,
	was_dragging:              bool,

	sidebar_scrollbar:         Scrollbar,
	playlist_scrollbar:        Scrollbar,
	lyrics_scrollbar:          Scrollbar,
	search_scrollbar:          Scrollbar,
	queue_scrollbar:           Scrollbar,
}

ui_state := UIState {
	current_view   = .SEARCH,
	show_lyrics    = true,
	follow_lyrics  = true,
	sidebar_anim   = 1.0,
}

init_ui_state :: proc() {
	textedit.init(&ui_state.search_box, context.allocator, context.allocator)
	textedit.setup_once(&ui_state.search_box, &ui_state.search_builder)
	ui_state.search_box.set_clipboard = proc(user_data: rawptr, text: string) -> (ok: bool) {
		return fx.set_clipboard(text)
	}
	ui_state.search_box.get_clipboard = proc(user_data: rawptr) -> (text: string, ok: bool) {
		contents := fx.get_clipboard(context.temp_allocator) or_return
		contents, _ = strings.remove_all(contents, "\n", context.temp_allocator)
		contents, _ = strings.remove_all(contents, "\r", context.temp_allocator)
		return contents, true
	}
}



frame :: proc() {
	if loading_covers {
		loading_covers = !check_all_covers_loaded()

		if loading_covers {
			process_loaded_covers()
		} else {
			cleanup_cover_loading()
		}
	}

	if fx.key_pressed(.F4) {
		ui_state.theme = (ui_state.theme + 1) % THEME_COUNT
		switch_theme(ui_state.theme)
	}

	if fx.key_held(.LEFT_CONTROL) && fx.key_pressed(.B) {
		ui_state.hide_sidebar = !ui_state.hide_sidebar
	}

	if fx.key_held(.LEFT_CONTROL) && fx.key_pressed(.L) {
		download_lyrics()
	}

	if fx.key_held(.LEFT_CONTROL) && fx.key_pressed(.C) {
		 if ui_state.compact_mode {
			ui_state.compact_mode = false
			fx.set_window_size(1280, 720)
			fx.center_window()
			fx.compact_mode(false)
		} else {
 			if player.current_track == nil || player.current_track.path == "" {
				show_alert({}, "No track is playing", "Open a track before opening compact mode", 2)
			} else {
				ui_state.compact_mode = true
				fx.set_window_size(600, 80)
				fx.set_window_pos(0, 0)
				fx.compact_mode(true)
			}
		}
	}

	dt := min(fx.delta_time(), 0.05)

	window_w, window_h := fx.window_size()

	update_player(dt)
	update_scrollbars(dt)

	if ui_state.hide_sidebar {
		ui_state.sidebar_anim = clamp(ui_state.sidebar_anim - dt * SIDEBAR_ANIM_SPEED, 0, 1)
	} else {
		ui_state.sidebar_anim = clamp(ui_state.sidebar_anim + dt * SIDEBAR_ANIM_SPEED, 0, 1)
	}

	if ui_state.show_queue_sidebar {
		ui_state.queue_sidebar_anim = clamp(ui_state.queue_sidebar_anim + dt * SIDEBAR_ANIM_SPEED, 0, 1)
	} else {
		ui_state.queue_sidebar_anim = clamp(ui_state.queue_sidebar_anim - dt * SIDEBAR_ANIM_SPEED, 0, 1)
	}

	eased_progress := ease_in_out_cubic(ui_state.sidebar_anim)
	sidebar_width := eased_progress * SIDEBAR_WIDTH

	eased_progress = ease_in_out_cubic(ui_state.queue_sidebar_anim)
	queue_sidebar_width := eased_progress * QUEUE_SIDEBAR_MAX

	update_alert(dt)

	if ui_state.compact_mode {
		compact_mode_frame()
	} else {
		fx.draw_gradient_rect_vertical(0, 0, window_w, window_h, BACKGROUND_GRADIENT_BRIGHT, BACKGROUND_GRADIENT_DARK)
		draw_sidebar(sidebar_width - SIDEBAR_WIDTH)

		draw_player_controls()

		content_w := window_w - sidebar_width - queue_sidebar_width
		content_h := window_h - PLAYER_HEIGHT

		switch ui_state.current_view {
		case .SEARCH:
			draw_search_view(sidebar_width, 10, content_w, content_h - 10)
		case .PLAYLIST_DETAIL:
			draw_playlist_view(sidebar_width, 0, content_w, content_h, ui_state.selected_playlist)
		case .NOW_PLAYING:
			draw_now_playing_view(sidebar_width, 0, content_w, content_h)
		case .LIKED:
			draw_playlist_view(sidebar_width, 0, content_w, content_h, &liked_playlist)
		}

		draw_queue_sidebar(window_w - queue_sidebar_width, queue_sidebar_width)
		draw_alert()

		if len(player.queue.tracks) > 0 {
			queue_open_btn := IconButton {
				x           = window_w - 50,
				y           = 45,
				size        = 40,
				icon        = sidebar_icon,
				color       = fx.BLANK,
				hover_color = UI_SECONDARY_COLOR,
			}

			if draw_icon_button(queue_open_btn) {
				ui_state.show_queue_sidebar = !ui_state.show_queue_sidebar
			}
		}
	}
}

blur_shader_hlsl := #load("assets/shaders/gaussian_blur.hlsl")
blur_shader: fx.Shader
background: fx.RenderTexture
update_background: bool
loading_covers: bool
playlists: [dynamic]^Playlist

main :: proc() {
	fx.init("Music Player", 1280, 720)
	init_ui_state()
	blur_shader = fx.load_shader(blur_shader_hlsl)
	background  = fx.create_render_texture(2048, 2048)
	load_icons()
	load_state()
	load_music()
	load_liked_songs()
	sort_playlists()
	search_tracks("")
	ui_state.selected_playlist = &ui_state.search_playlist
	init_cover_loading()
	init_thumbnail_loading()
	fx.run(frame)
	save_state()
}