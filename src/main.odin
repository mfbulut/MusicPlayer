package main

import fx "../fx"

import "core:fmt"
import "core:mem"

import "core:os"
import "core:os/os2"
import "core:strings"

UI_PRIMARY_COLOR      :: fx.Color{9, 17, 45, 255}
UI_SECONDARY_COLOR    :: fx.Color{30, 30, 90, 255}

UI_ACCENT_COLOR       :: fx.Color{83, 82, 145, 255}
UI_HOVER_COLOR        :: fx.Color{66, 64, 135, 255}
UI_SELECTED_COLOR     :: fx.Color{86, 84, 155, 255}

UI_TEXT_COLOR         :: fx.Color{235, 237, 240, 255}
UI_TEXT_SECONDARY     :: fx.Color{147, 154, 168, 255}

SIDEBAR_WIDTH : f32 : 220
PLAYER_HEIGHT : f32 : 80
TITLE_HEIGHT  : f32 : 40

View :: enum {
    SEARCH,
    PLAYLIST_DETAIL,
    NOW_PLAYING,
    LIKED,
    QUEUE,
}

Scrollbar :: struct {
    scroll: f32,
    target: f32,
    is_dragging: bool,
}

UIState :: struct {
    current_view: View,
    selected_playlist: string,

    show_lyrics: bool,
    follow_lyrics: bool,

    search_query: string,
    search_focus: bool,
    search_results: [dynamic]Track,

    drag_start_mouse_y: f32,
    drag_start_scroll: f32,

    is_dragging_time: bool,
    drag_start_time_x: f32,
    drag_start_position: f32,

    hide_sidebar : bool,
    sidebar_width: f32,

    sidebar_scrollbar: Scrollbar,
    playlist_scrollbar: Scrollbar,
    lyrics_scrollbar: Scrollbar,
    search_scrollbar: Scrollbar,
}

ui_state := UIState {
    current_view = .LIKED,
    show_lyrics = true,
    follow_lyrics = true,
    search_query = "",
    sidebar_width = SIDEBAR_WIDTH,
    search_results = make([dynamic]Track),
}

draw_main_content :: proc(sidebar_width: f32) {
    window_w, window_h := fx.window_size()

    content_x := sidebar_width
    content_w := f32(window_w) - sidebar_width
    content_h := f32(window_h) - PLAYER_HEIGHT

    switch ui_state.current_view {
    case .SEARCH:
        draw_search_view(content_x, 0, content_w, content_h)
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

frame :: proc(dt: f32) {
    window_w, window_h := fx.window_size()

    if fx.key_held(.LEFT_CONTROL) && fx.key_pressed(.B) {
        ui_state.hide_sidebar = !ui_state.hide_sidebar
        fx.set_sidebar_size(ui_state.hide_sidebar ? 0 : 200)
    }

    update_player(dt)
    update_smooth_scrolling(dt)

    if ui_state.hide_sidebar {
        ui_state.sidebar_width = clamp(ui_state.sidebar_width - dt * 2500, 0, SIDEBAR_WIDTH)
    } else {
        ui_state.sidebar_width = clamp(ui_state.sidebar_width + dt * 2500, 0, SIDEBAR_WIDTH)
    }

    fx.draw_rect_rounded(0, 0, f32(window_w), f32(window_h), 8, UI_PRIMARY_COLOR)

    draw_sidebar(ui_state.sidebar_width - SIDEBAR_WIDTH)

    draw_main_content(ui_state.sidebar_width)
    draw_player_controls()

    if !all_covers_loaded {
        if !loading_covers do return
        all_covers_loaded = check_all_covers_loaded()
        if !all_covers_loaded {
            process_loaded_covers()
        } else {
            cleanup_cover_loading()
        }
    }

    if draw_icon_button_rect(f32(window_w) - 50, 0, 50, 25, exit_icon, fx.Color{0, 0, 0, 0}, fx.Color{150, 48, 64, 255}, true) {
        fx.close_window()
    }

    if draw_icon_button_rect(f32(window_w) - 100, 0, 50, 25, maximize_icon, fx.Color{0, 0, 0, 0}, fx.Color{64, 64, 128, 255}, false, 6) {
        fx.maximize_or_restore_window()
    }

    if draw_icon_button_rect(f32(window_w) - 150, 0, 50, 25, minimize_icon, fx.Color{0, 0, 0, 0}, fx.Color{64, 64, 128, 255}) {
        fx.minimize_window()
    }
    if fx.is_hovering_files() {
        fx.draw_rect(0, 0, f32(window_w), f32(window_h), fx.Color{0, 0, 0, 196})
        fx.draw_text_aligned("Drop files to add to the queue", f32(window_w) / 2, f32(window_h) / 2, 32, fx.WHITE, .CENTER)
    }
}

previous_icon_qoi := #load("assets/previous.qoi")
forward_icon_qoi  := #load("assets/forward.qoi")
pause_icon_qoi    := #load("assets/pause.qoi")
play_icon_qoi     := #load("assets/play.qoi")
volume_icon_qoi   := #load("assets/volume.qoi")
shuffle_icon_qoi  := #load("assets/shuffle.qoi")
search_icon_qoi   := #load("assets/search.qoi")
liked_icon_qoi    := #load("assets/liked.qoi")
empty_icon_qoi    := #load("assets/liked_empty.qoi")
queue_icon_qoi    := #load("assets/queue.qoi")

exit_icon_qoi     := #load("assets/exit.qoi")
maximize_icon_qoi := #load("assets/maximize.qoi")
minimize_icon_qoi := #load("assets/minimize.qoi")

previous_icon : fx.Texture
forward_icon  : fx.Texture
pause_icon    : fx.Texture
play_icon     : fx.Texture
volume_icon   : fx.Texture
shuffle_icon  : fx.Texture
liked_icon    : fx.Texture
liked_empty   : fx.Texture
search_icon   : fx.Texture
queue_icon    : fx.Texture

exit_icon       : fx.Texture
maximize_icon   : fx.Texture
minimize_icon   : fx.Texture

bokeh_shader_hlsl : []u8 = #load("shaders/bokeh_blur.hlsl")
gaussian_shader_hlsl : []u8 = #load("shaders/gaussian_blur.hlsl")

use_gaussian : bool
gaussian_shader : fx.Shader
bokeh_shader : fx.Shader

loading_covers: bool
all_covers_loaded: bool
background : fx.RenderTexture
music_dir : string

drop_callback  :: proc(files: []string) {
    for filepath in files {
        file := os2.stat(filepath, context.allocator) or_continue
        if file.type == .Directory {
            load_files(filepath, context.allocator)
            ui_state.selected_playlist = file.name
            ui_state.current_view = .PLAYLIST_DETAIL
        } else {
            process_music_file(file, true)
        }
    }
}

main :: proc() {
	when false {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			if len(track.bad_free_array) > 0 {
				fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
				for entry in track.bad_free_array {
					fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

    fx.init("Music Player", 1280, 720)

    previous_icon = fx.load_texture_from_bytes(previous_icon_qoi)
    forward_icon  = fx.load_texture_from_bytes(forward_icon_qoi)
    pause_icon    = fx.load_texture_from_bytes(pause_icon_qoi)
    play_icon     = fx.load_texture_from_bytes(play_icon_qoi)
    volume_icon   = fx.load_texture_from_bytes(volume_icon_qoi)
    shuffle_icon  = fx.load_texture_from_bytes(shuffle_icon_qoi)
    liked_icon    = fx.load_texture_from_bytes(liked_icon_qoi)
    search_icon   = fx.load_texture_from_bytes(search_icon_qoi)
    liked_empty   = fx.load_texture_from_bytes(empty_icon_qoi)
    exit_icon     = fx.load_texture_from_bytes(exit_icon_qoi)
    maximize_icon = fx.load_texture_from_bytes(maximize_icon_qoi)
    minimize_icon = fx.load_texture_from_bytes(minimize_icon_qoi)
    queue_icon    = fx.load_texture_from_bytes(queue_icon_qoi)
    background    = fx.create_render_texture(1024, 1024)
    bokeh_shader  = fx.load_shader(bokeh_shader_hlsl)
    gaussian_shader = fx.load_shader(gaussian_shader_hlsl)

    fx.run_manual(proc() {
        frame(0)
        fx.draw_rect(0, 0, 1280, 720, fx.Color{0, 0, 0, 196})
        fx.draw_text_aligned("Loading...", 640, 360 - 16, 32, fx.WHITE, .CENTER)
    })

    music_dir = strings.join({os.get_env("USERPROFILE"), "Music"}, "\\")

    load_state()

    if len(os.args) > 1 {
        music_dir = os.args[1]
    }

    arena_mem := make([]byte, 8 * mem.Megabyte)
    arena: mem.Arena
    mem.arena_init(&arena, arena_mem)
    arena_alloc := mem.arena_allocator(&arena)

    load_files(music_dir, arena_alloc)

    sort_playlists()
    get_all_liked_songs()
    init_cover_loading()
    loading_covers = true
    search_tracks("")

    fx.set_file_drop_callback(drop_callback)

    fx.run(frame)

    save_state()
}