package main

import fx "../fx"

import "core:fmt"
import "core:mem"

import "core:os"
import "core:os/os2"
import "core:strings"
import "core:math"

UI_PRIMARY_COLOR      := fx.Color{24, 14, 44, 255}
UI_SECONDARY_COLOR    := fx.Color{95, 58, 137, 255}

UI_ACCENT_COLOR       := fx.Color{118, 67, 175, 255}
UI_HOVER_COLOR        := fx.Color{105, 68, 147, 255}

UI_TEXT_COLOR         := fx.Color{235, 237, 240, 255}
UI_TEXT_SECONDARY     := fx.Color{175, 180, 195, 255}

CONTROLS_GRADIENT_BRIGHT   := fx.Color{44, 27, 71, 255}
CONTROLS_GRADIENT_DARK     := fx.Color{24, 15, 39, 255}

TRACK_GRADIENT_BRIGHT      := fx.Color{54, 35, 85, 255}
TRACK_GRADIENT_DARK        := fx.Color{44, 27, 73, 255}

BACKGROUND_GRADIENT_BRIGHT := fx.Color{44, 27, 71, 255}
BACKGROUND_GRADIENT_DARK   := fx.Color{24, 15, 39, 255}

NOW_PLAYING_BACKDROP_BRIGHT  :: fx.Color{0, 0, 0, 108}
NOW_PLAYING_BACKDROP_DARK    :: fx.Color{0, 0, 0, 196}

SIDEBAR_WIDTH : f32 : 220
TITLE_HEIGHT  : f32 : 40
PLAYER_HEIGHT : f32 : 80

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
    theme : int,

    search_query: string,
    search_focus: bool,
    search_results: [dynamic]Track,

    drag_start_mouse_y: f32,
    drag_start_scroll: f32,
    is_dragging_progress: bool,

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

switch_theme :: proc() {
    if ui_state.theme == 0 {
        UI_PRIMARY_COLOR      = fx.Color{24, 14, 44, 255}
        UI_SECONDARY_COLOR    = fx.Color{95, 58, 137, 255}

        UI_ACCENT_COLOR       = fx.Color{118, 67, 175, 255}
        UI_HOVER_COLOR        = fx.Color{105, 68, 147, 255}

        UI_TEXT_COLOR         = fx.Color{235, 237, 240, 255}
        UI_TEXT_SECONDARY = fx.Color{175, 180, 195, 255}

        CONTROLS_GRADIENT_BRIGHT   = fx.Color{44, 27, 71, 255}
        CONTROLS_GRADIENT_DARK     = fx.Color{24, 15, 39, 255}

        TRACK_GRADIENT_BRIGHT      = fx.Color{54, 35, 85, 255}
        TRACK_GRADIENT_DARK        = fx.Color{44, 27, 73, 255}

        BACKGROUND_GRADIENT_BRIGHT = fx.Color{44, 27, 71, 255}
        BACKGROUND_GRADIENT_DARK   = fx.Color{24, 15, 39, 255}
    } else if ui_state.theme == 1 {
        UI_PRIMARY_COLOR      = fx.Color{10, 42, 51, 255}
        UI_SECONDARY_COLOR    = fx.Color{25, 110, 123, 255}

        UI_ACCENT_COLOR       = fx.Color{25, 130, 145, 255}
        UI_HOVER_COLOR        = fx.Color{18, 90, 99, 255}

        UI_TEXT_COLOR         = fx.Color{220, 224, 230, 255}
        UI_TEXT_SECONDARY = fx.Color{170, 185, 190, 255}

        CONTROLS_GRADIENT_BRIGHT   = fx.Color{15, 46, 55, 255}
        CONTROLS_GRADIENT_DARK     = fx.Color{10, 35, 42, 255}

        TRACK_GRADIENT_BRIGHT      = fx.Color{25, 85, 97, 255}
        TRACK_GRADIENT_DARK        = fx.Color{18, 55, 64, 255}

        BACKGROUND_GRADIENT_BRIGHT = fx.Color{15, 46, 55, 255}
        BACKGROUND_GRADIENT_DARK   = fx.Color{8, 30, 37, 255}
    } else if ui_state.theme == 2 {
        UI_PRIMARY_COLOR      = fx.Color{12, 35, 18, 255}
        UI_SECONDARY_COLOR    = fx.Color{34, 85, 52, 255}

        UI_ACCENT_COLOR       = fx.Color{45, 160, 75, 255}
        UI_HOVER_COLOR        = fx.Color{28, 120, 45, 255}

        UI_TEXT_COLOR         = fx.Color{240, 250, 245, 255}
        UI_TEXT_SECONDARY     = fx.Color{180, 210, 190, 255}

        CONTROLS_GRADIENT_BRIGHT   = fx.Color{20, 55, 30, 255}
        CONTROLS_GRADIENT_DARK     = fx.Color{8, 25, 12, 255}

        TRACK_GRADIENT_BRIGHT      = fx.Color{25, 70, 40, 255}
        TRACK_GRADIENT_DARK        = fx.Color{15, 45, 25, 255}

        BACKGROUND_GRADIENT_BRIGHT = fx.Color{18, 45, 25, 255}
        BACKGROUND_GRADIENT_DARK   = fx.Color{6, 20, 10, 255}
    } else if ui_state.theme == 3 {
        UI_PRIMARY_COLOR      = fx.Color{30, 12, 10, 255}
        UI_SECONDARY_COLOR    = fx.Color{90, 38, 30, 255}

        UI_ACCENT_COLOR       = fx.Color{110, 50, 35, 255}
        UI_HOVER_COLOR        = fx.Color{80, 38, 28, 255}

        UI_TEXT_COLOR         = fx.Color{190, 190, 190, 255}
        UI_TEXT_SECONDARY = fx.Color{180, 175, 170, 255}

        CONTROLS_GRADIENT_BRIGHT   = fx.Color{50, 20, 15, 255}
        CONTROLS_GRADIENT_DARK     = fx.Color{30, 12, 10, 255}

        TRACK_GRADIENT_BRIGHT      = fx.Color{85, 32, 20, 255}
        TRACK_GRADIENT_DARK        = fx.Color{59, 23, 16, 255}

        BACKGROUND_GRADIENT_BRIGHT = fx.Color{50, 20, 15, 255}
        BACKGROUND_GRADIENT_DARK   = fx.Color{30, 12, 10, 255}
    } else if ui_state.theme == 4 {
        UI_PRIMARY_COLOR      = fx.Color{18, 28, 78, 255}
        UI_SECONDARY_COLOR    = fx.Color{55, 60, 155, 255}

        UI_ACCENT_COLOR       = fx.Color{80, 85, 200, 255}
        UI_HOVER_COLOR        = fx.Color{70, 80, 175, 255}

        UI_TEXT_COLOR         = fx.Color{230, 240, 255, 255}
        UI_TEXT_SECONDARY = fx.Color{175, 180, 200, 255}

        CONTROLS_GRADIENT_BRIGHT   = fx.Color{30, 35, 100, 255}
        CONTROLS_GRADIENT_DARK     = fx.Color{15, 20, 60, 255}

        TRACK_GRADIENT_BRIGHT      = fx.Color{40, 45, 120, 255}
        TRACK_GRADIENT_DARK        = fx.Color{30, 35, 100, 255}

        BACKGROUND_GRADIENT_BRIGHT = fx.Color{30, 35, 85, 255}
        BACKGROUND_GRADIENT_DARK   = fx.Color{18, 22, 40, 255}
    }
}

ease_in_out_cubic :: proc(t: f32) -> f32 {
    if t < 0.5 {
        return 4 * t * t * t
    } else {
        return 1 - math.pow(-2 * t + 2, 3) / 2
    }
}

sidebar_anim_progress: f32 = 1.0

frame :: proc(dt: f32) {
    window_w, window_h := fx.window_size()

    if fx.key_pressed(.F4) {
        ui_state.theme = (ui_state.theme + 1) % 5
        switch_theme()
    }

    if fx.key_held(.LEFT_CONTROL) && fx.key_pressed(.B) {
        ui_state.hide_sidebar = !ui_state.hide_sidebar
        fx.set_sidebar_size(ui_state.hide_sidebar ? 0 : 200)
    }

    update_player(dt)
    update_smooth_scrolling(dt)

    sidebar_anim_speed: f32 = 4.0

    if ui_state.hide_sidebar {
        sidebar_anim_progress = clamp(sidebar_anim_progress - dt * sidebar_anim_speed, 0, 1)
    } else {
        sidebar_anim_progress = clamp(sidebar_anim_progress + dt * sidebar_anim_speed, 0, 1)
    }

    eased_progress := ease_in_out_cubic(sidebar_anim_progress)
    ui_state.sidebar_width = eased_progress * SIDEBAR_WIDTH

    fx.draw_gradient_rect_rounded_vertical(0, 0, f32(window_w), f32(window_h), 8, BACKGROUND_GRADIENT_BRIGHT, BACKGROUND_GRADIENT_DARK)

    draw_sidebar(ui_state.sidebar_width - SIDEBAR_WIDTH)

    draw_main_content(ui_state.sidebar_width)
    draw_player_controls()

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

    if draw_icon_button_rect(f32(window_w) - 100, 0, 50, 25, maximize_icon, fx.BLANK, fx.Color{80, 64, 128, 255}, false, 6) {
        fx.maximize_or_restore_window()
    }

    if draw_icon_button_rect(f32(window_w) - 150, 0, 50, 25, minimize_icon, fx.BLANK, fx.Color{80, 64, 128, 255}) {
        fx.minimize_window()
    }

    if fx.is_hovering_files() {
        fx.draw_rect(0, 0, f32(window_w), f32(window_h), fx.Color{0, 0, 0, 196})
        fx.draw_text_aligned("Drop files to add to the queue", f32(window_w) / 2, f32(window_h) / 2, 32, fx.WHITE, .CENTER)
    }
}

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

previous_icon_qoi :: #load("assets/previous.qoi")
forward_icon_qoi  :: #load("assets/forward.qoi")
pause_icon_qoi    :: #load("assets/pause.qoi")
play_icon_qoi     :: #load("assets/play.qoi")
volume_icon_qoi   :: #load("assets/volume.qoi")
shuffle_icon_qoi  :: #load("assets/shuffle.qoi")
search_icon_qoi   :: #load("assets/search.qoi")
liked_icon_qoi    :: #load("assets/liked.qoi")
empty_icon_qoi    :: #load("assets/liked_empty.qoi")
queue_icon_qoi    :: #load("assets/queue.qoi")
exit_icon_qoi     :: #load("assets/exit.qoi")
maximize_icon_qoi :: #load("assets/maximize.qoi")
minimize_icon_qoi :: #load("assets/minimize.qoi")

blur_shader_hlsl :: #load("shaders/gaussian_blur.hlsl")

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
exit_icon     : fx.Texture
maximize_icon : fx.Texture
minimize_icon : fx.Texture
blur_shader   : fx.Shader
background    : fx.RenderTexture

playlists : [dynamic]Playlist

loading_covers: bool
update_background: bool
music_dir : string

main :: proc() {
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
    blur_shader   = fx.load_shader(blur_shader_hlsl)
    background    = fx.create_render_texture(1024, 1024)

    load_state()
    switch_theme()

    fx.run_manual(proc() {
        frame(0)
        fx.draw_rect(0, 0, 1280, 720, fx.Color{0, 0, 0, 196})
        fx.draw_text_aligned("Loading...", 640, 360 - 16, 32, fx.WHITE, .CENTER)
    })

    music_dir = strings.join({os.get_env("USERPROFILE"), "Music"}, "\\")

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