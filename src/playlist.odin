package main

import fx "../fx"

import "core:fmt"
import "core:encoding/json"
import "core:os"
import "core:time"
import "core:slice"

draw_track_item :: proc(track: Track, playlist: Playlist, x, y, w, h: f32) {
    mouse_x, mouse_y := fx.get_mouse()
    hover := is_hovering(x, y, w, h)
    bg_color := UI_SECONDARY_COLOR

    if player.current_track.name == track.name {
        bg_color = UI_HOVER_COLOR
    } else if hover {
        bg_color = UI_SELECTED_COLOR
        fx.set_cursor(.CLICK)
    }

    fx.draw_gradient_rect_rounded_horizontal(x, y, w, h, 12, bg_color, darken(bg_color, 30))

    text_color := UI_TEXT_COLOR
    secondary_color := hover ? UI_TEXT_COLOR : UI_TEXT_SECONDARY

    fx.draw_text(track.name, x + 20, y + 5, 20, text_color)
    fx.draw_text(track.playlist, x + 20, y + 35, 16, secondary_color)

    heart_x := x + w - 40
    heart_y := y + 15
    heart_size: f32 = 20

    is_liked := is_song_liked(track.name, track.playlist)

    heart_btn := IconButton{
        x = x + w - 60, y = y + 10, size = 40,
        icon = is_liked ? liked_icon : liked_empty,
        color = bg_color,
        hover_color = bg_color,
    }

    if draw_icon_button(heart_btn) {
        toggle_song_like(track.name, track.playlist)
    } else if hover && fx.mouse_pressed(.LEFT) {
        play_track(track, playlist)
    }

    if fx.mouse_pressed(.RIGHT) && hover {
        insert_next_track(track)
    }
}


draw_playlist_view :: proc(x, y, w, h: f32, playlist: Playlist) {
    if playlist.loaded {
        fx.use_texture(playlist.cover)
        fx.draw_texture_rounded(x + 40, y + 10, 100, 100, 12, fx.WHITE)

        fx.draw_text(playlist.name, x + 160, y + 30, 32, UI_TEXT_COLOR)
        fx.draw_text(fmt.tprintf("%d tracks", len(playlist.tracks)), x + 160, y + 70, 16, UI_TEXT_SECONDARY)
    } else {
        fx.draw_text(playlist.name, x + 40, y + 30, 32, UI_TEXT_COLOR)
        fx.draw_text(fmt.tprintf("%d tracks", len(playlist.tracks)), x + 40, y + 70, 16, UI_TEXT_SECONDARY)
    }

    list_y := y + 120
    list_h := h - 120

    track_count := len(playlist.tracks)
    track_height: f32 = 65
    playlist_max_scroll := calculate_max_scroll(track_count, track_height, list_h)

    ui_state.playlist_scrollbar.target = clamp(ui_state.playlist_scrollbar.target, 0, playlist_max_scroll)
    ui_state.playlist_scrollbar.scroll = clamp(ui_state.playlist_scrollbar.scroll, 0, playlist_max_scroll)

    fx.set_scissor(i32(x), i32(list_y), i32(w - 15), i32(list_h))

    if !ui_state.playlist_scrollbar.is_dragging {
        interaction_rect(f32(x), f32(list_y), f32(w - 15), f32(list_h))
    }

    track_y := list_y - ui_state.playlist_scrollbar.scroll

    mouse_x, mouse_y := fx.get_mouse()

    for i in 0..<len(playlist.tracks) {
        track := playlist.tracks[i]

        if track_y > y + h {
            break
        }

        if track_y + 60 > list_y {
            draw_track_item(track, playlist, x + 30, track_y, w - 70, 60)
        }

        track_y += track_height
    }

    fx.disable_scissor()

    if playlist_max_scroll > 0 {
        indicator_x := x + w - 20
        indicator_y := list_y + 5
        indicator_h := list_h - 10

        draw_scrollbar(&ui_state.playlist_scrollbar, indicator_x, indicator_y, 4, indicator_h, playlist_max_scroll, UI_PRIMARY_COLOR, UI_ACCENT_COLOR)
    }

    if !ui_state.playlist_scrollbar.is_dragging {
        window_w, window_h := fx.window_size()
        interaction_rect(0, 0, f32(window_w), f32(window_h))

        scroll_delta := fx.get_mouse_scroll()
        if scroll_delta != 0 {
            if f32(mouse_x) > x {
                ui_state.playlist_scrollbar.target -= f32(scroll_delta) * 80
                ui_state.playlist_scrollbar.target = clamp(ui_state.playlist_scrollbar.target, 0, playlist_max_scroll)
            }
        }
    }
}

LikedSong :: struct {
    name: string,
    playlist: string,
    is_liked: bool,
    timestamp: i64,
}

liked_songs: [dynamic]LikedSong

liked_playlist : Playlist = Playlist {
    name = "Liked Songs",
    tracks = make([dynamic]Track),
}

init_liked_songs :: proc(save_file: string = "liked_songs.json") -> bool {
    liked_songs = make([dynamic]LikedSong)

    if os.exists(save_file) {
        res := load_liked_songs_from_file(save_file)
        get_all_liked_songs()
        return res
    }

    return true
}

create_song_key :: proc(name: string, playlist: string) -> string {
    return fmt.tprintf("%s|%s", name, playlist, context.temp_allocator)
}

find_liked_song_index :: proc(name: string, playlist: string) -> int {
    for song, i in liked_songs {
        if song.name == name && song.playlist == playlist {
            return i
        }
    }
    return -1
}

is_song_liked :: proc(name: string, playlist: string) -> bool {
    index := find_liked_song_index(name, playlist)
    return index != -1 && liked_songs[index].is_liked
}

set_liked_song :: proc(name: string, playlist: string, liked: bool, save_file: string = "liked_songs.json") {
    index := find_liked_song_index(name, playlist)

    if liked {
        new_song := LikedSong{
            name = name,
            playlist = playlist,
            is_liked = true,
            timestamp = time.now()._nsec,
        }

        if index != -1 {
            liked_songs[index] = new_song
        } else {
            append(&liked_songs, new_song)
        }
    } else {
        if index != -1 {
            ordered_remove(&liked_songs, index)
        }
    }

    save_liked_songs_to_file(save_file)
}

get_all_liked_songs :: proc() {
    if len(liked_playlist.tracks) > 0 {
        delete(liked_playlist.tracks)
        liked_playlist.tracks = make([dynamic]Track)
    }

    for liked_song in liked_songs {
        source_playlist := find_playlist_by_name(liked_song.playlist)
        for track in source_playlist.tracks {
            if track.name == liked_song.name {

                track_copy := Track{
                    path = track.path,
                    name = track.name,
                    playlist = track.playlist,
                    lyrics = track.lyrics,
                    audio_clip = track.audio_clip,
                }

                append(&liked_playlist.tracks, track_copy)
                break
            }
        }
    }

    slice.sort_by(liked_playlist.tracks[:], proc(a, b: Track) -> bool {
        a_index := find_liked_song_index(a.name, a.playlist)
        b_index := find_liked_song_index(b.name, b.playlist)
        if a_index < 0 || b_index < 0 {
            fmt.println("ERROR: Can't find liked song")
        }
        return liked_songs[a_index].timestamp > liked_songs[b_index].timestamp
    })
}

toggle_song_like :: proc(name: string, playlist: string, save_file: string = "liked_songs.json") {
    current_state := is_song_liked(name, playlist)
    set_liked_song(name, playlist, !current_state, save_file)
}

save_liked_songs_to_file :: proc(filename: string) -> bool {
    json_data, marshal_err := json.marshal(liked_songs)
    if marshal_err != nil {
        fmt.printf("Error marshaling liked songs: %v\n", marshal_err)
        return false
    }
    defer delete(json_data)

    write_success := os.write_entire_file(filename, json_data)
    if !write_success {
        fmt.printf("Error writing liked songs to file: %s\n", filename)
        return false
    }
    return true
}

load_liked_songs_from_file :: proc(filename: string) -> bool {
    file_data, read_success := os.read_entire_file(filename)
    if !read_success {
        fmt.printf("Could not read liked songs file: %s\n", filename)
        return false
    }
    defer delete(file_data)

    unmarshal_err := json.unmarshal(file_data, &liked_songs)
    if unmarshal_err != nil {
        fmt.printf("Error parsing liked songs JSON: %v\n", unmarshal_err)
        return false
    }

    return true
}