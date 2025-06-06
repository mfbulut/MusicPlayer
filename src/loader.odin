package main

import fx "../fx"

import "core:fmt"
import "core:path/filepath"
import "core:os"
import "core:os/os2"
import "core:strings"
import "core:strconv"
import "core:slice"

Lyrics :: struct {
    time: f32,
    text: string,
}

Track :: struct {
    path:      string,
    name:      string,
    playlist:  string,
    lyrics:    [dynamic]Lyrics,
    audio_clip: fx.Audio,
}

Playlist :: struct {
    path:      string,
    name:      string,
    tracks:    [dynamic]Track,
    cover:     fx.Texture,
    cover_path:string,
    loaded: bool,
}

playlists : [dynamic]Playlist

load_files :: proc(path: string) {
    root_dir, read_err := os2.read_all_directory_by_path(path, context.allocator)
    if read_err != nil {
        fmt.eprintln("Error reading directory:", path, "->", read_err)
        return
    }
    defer delete(root_dir)

    for file in root_dir {
        if file.type == .Directory {
            load_files(file.fullpath)
        } else {
            process_music_file(file)
        }
    }
}

find_playlist_by_name :: proc(name: string) -> Playlist {
    for playlist in playlists {
        if playlist.name == name {
            return playlist
        }
    }
    fmt.println("Can't find playlist: ", name)
    return Playlist{}
}

find_or_create_playlist :: proc(dir_path: string, dir_name: string) -> ^Playlist {
    for &playlist in playlists {
        if playlist.name == dir_name {
            return &playlist
        }
    }

    playlist := Playlist{
        path   = dir_path,
        name   = dir_name,
        tracks = make([dynamic]Track, 0, 128),
    }

    cover_path := filepath.join({dir_path, "cover.qoi"})

    if os.exists(cover_path) {
        playlist.cover_path = cover_path
    } else {
        delete(cover_path)
        cover_path = filepath.join({dir_path, "cover.png"})
        if os.exists(cover_path) {
            playlist.cover_path = cover_path
        }
    }

    append(&playlists, playlist)
    return &playlists[len(playlists) - 1]
}

sort_playlists :: proc() {
    slice.sort_by(playlists[:], proc(a, b: Playlist) -> bool {
        return strings.compare(a.name, b.name) < 0
    })
}

process_music_file :: proc(file: os2.File_Info, queue := false) {
    dir_path, filename := os2.split_path(file.fullpath)
    name, ext := os2.split_filename(filename)

    if ext != "mp3" && ext != "wav" && ext != "flac" && ext != "opus" && ext != "ogg" do return

    name, _ = strings.replace_all(name, "[", "(")
    name, _ = strings.replace_all(name, "]", ")")
    name, _ = strings.replace_all(name, "=", "-")

    dir_name := filepath.base(dir_path)
    playlist := find_or_create_playlist(dir_path, dir_name)

    music := Track{
        path     = file.fullpath,
        name     = name,
        playlist = dir_name,
        lyrics   = load_lyrics_for_track(file.fullpath),
    }
    if queue {
        append(&player.queue.tracks, music)
    } else {
        append(&playlist.tracks, music)
    }
}

parse_lrc_time :: proc(time_str: string) -> (f32, bool) {
    if len(time_str) < 3 || time_str[0] != '[' || time_str[len(time_str)-1] != ']' {
        return 0, false
    }

    inner := time_str[1:len(time_str)-1]

    parts := strings.split(inner, ":", context.temp_allocator)
    if len(parts) != 2 {
        return 0, false
    }

    minutes, min_ok := strconv.parse_int(parts[0])
    if !min_ok {
        return 0, false
    }

    seconds_part := parts[1]
    seconds_parts := strings.split(seconds_part, ".", context.temp_allocator)

    seconds: int
    milliseconds: int = 0

    sec_ok: bool
    seconds, sec_ok = strconv.parse_int(seconds_parts[0])
    if !sec_ok {
        return 0, false
    }

    if len(seconds_parts) > 1 {
        ms_str := seconds_parts[1]

        if len(ms_str) == 1 {
            ms_str = strings.concatenate({ms_str, "00"}, context.temp_allocator)
        } else if len(ms_str) == 2 {
            ms_str = strings.concatenate({ms_str, "0"}, context.temp_allocator)
        } else if len(ms_str) > 3 {
            ms_str = ms_str[:3]
        }

        ms_ok: bool
        milliseconds, ms_ok = strconv.parse_int(ms_str)
        if !ms_ok {
            milliseconds = 0
        }
    }

    total_seconds := f32(minutes) * 60.0 + f32(seconds) + f32(milliseconds) / 1000.0
    return total_seconds, true
}

load_lyrics_for_track :: proc(music_path: string) -> [dynamic]Lyrics {
    lyrics := make([dynamic]Lyrics, 0, 64)

    lrc_path, _ := strings.replace(music_path, ".mp3", ".lrc", 1, context.temp_allocator)

    lrc_data, read_ok := os.read_entire_file_from_filename(lrc_path, context.temp_allocator)
    if !read_ok {
		return lyrics
    }

    lrc_content := string(lrc_data)
    lines := strings.split_lines(lrc_content, context.temp_allocator)

    for &line in lines {
        line = strings.trim_space(line)
        if len(line) == 0 do continue

        bracket_end := strings.index_byte(line, ']')
        if bracket_end == -1 do continue

        time_tag := line[:bracket_end+1]
        lyric_text := strings.trim_space(line[bracket_end+1:])

        time, time_ok := parse_lrc_time(time_tag)
        if !time_ok do continue

        lyric := Lyrics{
            time = time,
            text = lyric_text,
        }
        append(&lyrics, lyric)
    }

    slice.sort_by(lyrics[:], proc(a, b: Lyrics) -> bool {
        return a.time < b.time
    })

    return lyrics
}

print_playlist :: proc() {
    for playlist in playlists {
        fmt.printf("Playlist: %s (%d tracks)\n", playlist.name, len(playlist.tracks))
        for track, i in playlist.tracks {
            if i < 3 {
                lyrics_info := len(track.lyrics) > 0 ? fmt.tprintf(" [%d lyrics]", len(track.lyrics)) : ""
                fmt.printf("  %d. %s%s\n", i+1, track.name, lyrics_info)
            } else if i == 3 {
                fmt.printf("  ... and %d more tracks\n", len(playlist.tracks) - 3)
                break
            }
        }
        fmt.println()
    }
}

import "core:thread"
import "core:sync"
import "core:time"

Cover_Load_Result :: struct {
    playlist_index: int,
    texture: fx.Texture,
    success: bool,
}

cover_load_queue: [dynamic]Cover_Load_Result
cover_load_mutex: sync.Mutex
cover_loading_thread: ^thread.Thread
should_stop_loading: bool

cover_loading_worker :: proc(t: ^thread.Thread) {
    for !should_stop_loading {
        playlist_index := -1
        cover_path: string
        found := false

        for &playlist, i in playlists {
            if !playlist.loaded && len(playlist.cover_path) > 0 {
                playlist_index = i
                cover_path = playlist.cover_path
                found = true
                break
            }
        }

        if !found {
            time.sleep(100 * time.Millisecond)
            continue
        }

        texture := fx.load_texture(cover_path)

        result := Cover_Load_Result{
            playlist_index = playlist_index,
            texture = texture,
            success = true,
        }

        sync.lock(&cover_load_mutex)
        append(&cover_load_queue, result)
        sync.unlock(&cover_load_mutex)

        time.sleep(10 * time.Millisecond)
    }
}

init_cover_loading :: proc() {
    cover_load_queue = make([dynamic]Cover_Load_Result)
    cover_loading_thread = thread.create(cover_loading_worker)
    thread.start(cover_loading_thread)
}

process_loaded_covers :: proc() {
    sync.lock(&cover_load_mutex)
    defer sync.unlock(&cover_load_mutex)

    for result in cover_load_queue {
        if result.success && result.playlist_index >= 0 && result.playlist_index < len(playlists) {
            playlists[result.playlist_index].cover = result.texture
            playlists[result.playlist_index].loaded = true
        }
    }

    clear(&cover_load_queue)
}

check_all_covers_loaded :: proc() -> bool {
    for playlist in playlists {
        if !playlist.loaded && len(playlist.cover_path) > 0 {
            return false
        }
    }
    return true
}

cleanup_cover_loading :: proc() {
    should_stop_loading = true
    thread.join(cover_loading_thread)
    thread.destroy(cover_loading_thread)
    delete(cover_load_queue)
}