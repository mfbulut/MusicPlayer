package main

import "fx"

import "core:os"
import "core:os/os2"
import "core:strings"
import fp "core:path/filepath"
import textedit "core:text/edit"

SIDEBAR_WIDTH   : f32 : 220
TITLE_HEIGHT    : f32 : 40
PLAYER_HEIGHT   : f32 : 80
SIDEBAR_ANIM_SPEED : f32 = 4
UI_SCROLL_SPEED    : f32 : 20

View :: enum {
	SEARCH,
	PLAYLIST_DETAIL,
	NOW_PLAYING,
	LIKED,
	QUEUE,
}

Scrollbar :: struct {
	scroll:      f32,
	target:      f32,
	is_dragging: bool,
}

UIState :: struct {
	current_view:              View,
	selected_playlist:         string,
	show_lyrics:               bool,
	follow_lyrics:             bool,
	theme:                     int,

	search_box:                textedit.State,
	search_builder:            strings.Builder,
	search_focus:              bool,
	search_results:            [dynamic]Track,

	hide_sidebar:              bool,
	sidebar_width:             f32,
	sidebar_anim:              f32,

	drag_start_mouse_y:        f32,
	drag_start_scroll:         f32,
	is_dragging_progress:      bool,
	is_dragging_time:          bool,
	drag_start_time_x:         f32,
	drag_start_position:       f32,
	lyrics_animation_progress: f32,

	sidebar_scrollbar:         Scrollbar,
	playlist_scrollbar:        Scrollbar,
	lyrics_scrollbar:          Scrollbar,
	search_scrollbar:          Scrollbar,
}

ui_state := UIState {
	current_view   = .LIKED,
	show_lyrics    = true,
	follow_lyrics  = true,
	sidebar_width  = SIDEBAR_WIDTH,
	sidebar_anim   = 1.0,
}

@(init)
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

draw_main_content :: proc(sidebar_width: f32) {
	window_w, window_h := fx.window_size()

	content_x := sidebar_width
	content_w := f32(window_w) - sidebar_width
	content_h := f32(window_h) - PLAYER_HEIGHT

	switch ui_state.current_view {
	case .SEARCH:
		draw_search_view(content_x, 10, content_w, content_h - 10)
	case .PLAYLIST_DETAIL:
		draw_playlist_view(content_x, 0, content_w, content_h, find_playlist_by_name(ui_state.selected_playlist))
	case .NOW_PLAYING:
		draw_now_playing_view(content_x, 0, content_w, content_h)
	case .LIKED:
		draw_playlist_view(content_x, 0, content_w, content_h, liked_playlist)
	case .QUEUE:
		draw_playlist_view(content_x, 0, content_w, content_h, player.queue, true)
	}
}

frame :: proc() {
	dt := min(fx.delta_time(), 0.05)

	window_w, window_h := fx.window_size()

	if fx.key_pressed(.F4) {
		ui_state.theme = (ui_state.theme + 1) % THEME_COUNT
		switch_theme(ui_state.theme)
	}

	if fx.key_held(.LEFT_CONTROL) && fx.key_pressed(.B) {
		ui_state.hide_sidebar = !ui_state.hide_sidebar
		fx.set_sidebar_size(ui_state.hide_sidebar ? 0 : 200)
	}

	if fx.key_held(.LEFT_CONTROL) && fx.key_pressed(.L) {
		download_lyrics()
	}

	update_player(dt)
	update_scrollbars(dt)

	if ui_state.hide_sidebar {
		ui_state.sidebar_anim = clamp(ui_state.sidebar_anim - dt * SIDEBAR_ANIM_SPEED, 0, 1)
	} else {
		ui_state.sidebar_anim = clamp(ui_state.sidebar_anim + dt * SIDEBAR_ANIM_SPEED, 0, 1)
	}

	eased_progress := ease_in_out_cubic(ui_state.sidebar_anim)
	ui_state.sidebar_width = eased_progress * SIDEBAR_WIDTH

	fx.draw_gradient_rect_rounded_vertical(0, 0, f32(window_w), f32(window_h), 8, BACKGROUND_GRADIENT_BRIGHT, BACKGROUND_GRADIENT_DARK)

	draw_sidebar(ui_state.sidebar_width - SIDEBAR_WIDTH)

	draw_main_content(ui_state.sidebar_width)
	draw_player_controls()

	update_alert(dt)
	draw_alert()

	if loading_covers {
		loading_covers = !check_all_covers_loaded()

		if loading_covers {
			process_loaded_covers()
		} else {
			cleanup_cover_loading()
		}
	}

	if draw_icon_button_rect(f32(window_w) - 50, 0, 50, 25, exit_icon, fx.BLANK, fx.Color{150, 48, 64, 255}, true) {
		fx.close_window()
	}

	if draw_icon_button_rect(f32(window_w) - 100, 0, 50, 25, maximize_icon, fx.BLANK, set_alpha(UI_SECONDARY_COLOR, 0.7), false, 6) {
		fx.maximize_or_restore_window()
	}

	if draw_icon_button_rect(f32(window_w) - 150, 0, 50, 25, minimize_icon, fx.BLANK, set_alpha(UI_SECONDARY_COLOR, 0.7)) {
		fx.minimize_window()
	}

	if fx.is_hovering_files() {
		fx.draw_rect(0, 0, f32(window_w), f32(window_h), fx.Color{0, 0, 0, 196})
		fx.draw_text_aligned("Drop files to add to the queue", f32(window_w) / 2, f32(window_h) / 2, 32, fx.WHITE, .CENTER)
	}
}

drop_callback :: proc(files: []string) {
	for filepath in files {
		file := os2.stat(filepath, context.allocator) or_continue
		if file.type == .Directory {
			load_files(filepath)
			ui_state.selected_playlist = file.name
			ui_state.current_view = .PLAYLIST_DETAIL

			playlist_id := playlist_id(file.name)

			if playlist_id >= 0 {
				ok: bool
				playlists[playlist_id].cover, ok = fx.load_texture(playlists[playlist_id].cover_path)
				playlists[playlist_id].loaded = ok
			}

			sort_playlists()
		} else {
			if is_audio_file(file.name) {
				process_music_file(file, true)
			} else if is_image_file(file.name) {
				track := find_track_by_name(player.current_track.name, player.current_track.playlist)

				track.audio_clip.cover, _ = fx.load_texture(file.fullpath)
				player.current_track.audio_clip.cover = track.audio_clip.cover
				update_background = true

				dest_dir := fp.dir(track.path)
				dest_stem := fp.stem(track.path)
				dest_ext := fp.ext(file.fullpath)

				dest_path := strings.join({dest_dir, "\\", dest_stem, dest_ext}, "")

				copy_file(file.fullpath, dest_path)
			}
		}
	}
}

blur_shader_hlsl :: #load("assets/shaders/gaussian_blur.hlsl")
blur_shader: fx.Shader
background: fx.RenderTexture

playlists: [dynamic]Playlist

loading_covers: bool
update_background: bool
music_dir: string

main :: proc() {
	fx.init("Music Player", 1280, 720)

	blur_shader = fx.load_shader(blur_shader_hlsl)
	background = fx.create_render_texture(2048, 2048)
	music_dir = strings.join({os.get_env("USERPROFILE"), "Music"}, "\\")

	load_icons()
	load_state()

	fx.run_manual(proc() {
		frame()
		window_w, window_h := fx.window_size()
		fx.draw_rect(0, 0, f32(window_w), f32(window_h), fx.Color{0, 0, 0, 196})
		fx.draw_text_aligned("Loading...", f32(window_w) / 2, f32(window_h) / 2 - 16, 32, fx.WHITE, .CENTER)
	})

	load_files(music_dir)

	load_liked_songs()

	sort_playlists()
	init_cover_loading()
	search_tracks("")

	fx.drop_callback(drop_callback)
	fx.run(frame)

	save_state()
}
