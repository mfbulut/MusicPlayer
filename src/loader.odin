package main

import "fx"

import "base:runtime"

import "core:fmt"
import "core:os"
import "core:os/os2"
import "core:path/filepath"
import "core:slice"
import "core:strconv"
import "core:strings"

Lyrics :: struct {
	time: f32,
	text: string,
}

Track :: struct {
	path:       string,
	name:       string,
	playlist:   string,
	lyrics:     [dynamic]Lyrics,
	audio_clip: fx.Audio,
}

Playlist :: struct {
	path:       string,
	name:       string,
	tracks:     [dynamic]Track,
	cover:      fx.Texture,
	cover_path: string,
	loaded:     bool,
}

load_files :: proc(path: string, allocator: runtime.Allocator) {
	root_dir, read_err := os2.read_all_directory_by_path(path, allocator)
	if read_err != nil {
		fmt.eprintln("Error reading directory:", path, "->", read_err)
		return
	}

	context.allocator = allocator

	for file in root_dir {
		if file.type == .Directory {
			load_files(file.fullpath, allocator)
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
	return Playlist{}
}

playlist_id :: proc(name: string) -> int {
	for playlist, i in playlists {
		if playlist.name == name {
			return i
		}
	}
	return -1
}

find_track_by_name :: proc(track_name: string, playlist_name: string) -> ^Track {
	for &playlist in playlists {
		if playlist.name == playlist_name {
			for &track in playlist.tracks {
				if track.name == track_name {
					return &track
				}
			}
			return nil
		}
	}
	return nil
}

find_or_create_playlist :: proc(dir_path: string, dir_name: string) -> ^Playlist {
	for &playlist in playlists {
		if playlist.name == dir_name {
			return &playlist
		}
	}

	playlist := Playlist {
		path   = dir_path,
		name   = dir_name,
		tracks = make([dynamic]Track, 0, 16),
	}

	cover_path := filepath.join({dir_path, "cover.qoi"})

	if os.exists(cover_path) {
		playlist.cover_path = cover_path
	} else {
		delete(cover_path)
		cover_path = filepath.join({dir_path, "cover.png"})
		if os.exists(cover_path) {
			playlist.cover_path = cover_path
		} else {
			delete(cover_path)
			cover_path = filepath.join({dir_path, "cover.jpg"})
			if os.exists(cover_path) {
				playlist.cover_path = cover_path
			}
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

	music := Track {
		path     = file.fullpath,
		name     = name,
		playlist = dir_name,
	}

	if queue {
		append(&player.queue.tracks, music)
	} else {
		playlist := find_or_create_playlist(dir_path, dir_name)
		append(&playlist.tracks, music)
	}
}

parse_lrc_time :: proc(time_str: string) -> (f32, bool) {
	if len(time_str) < 3 || time_str[0] != '[' || time_str[len(time_str) - 1] != ']' {
		return 0, false
	}

	inner := time_str[1:len(time_str) - 1]

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

get_lrc_path :: proc(music_path: string) -> string {
	extensions := []string{".mp3", ".wav", ".flac", ".opus", ".ogg"}
	for ext in extensions {
		if strings.ends_with(music_path, ext) {
			new, _ := strings.replace(music_path, ext, ".lrc", 1, context.temp_allocator)
			return new
		}
	}
	return ""
}

load_lyrics_from_string :: proc(lrc_content: string) -> [dynamic]Lyrics {
	lyrics := make([dynamic]Lyrics)

	lines := strings.split_lines(lrc_content, context.temp_allocator)

	for &line in lines {
		line = strings.trim_space(line)
		if len(line) == 0 do continue

		bracket_end := strings.index_byte(line, ']')
		if bracket_end == -1 do continue

		time_tag := line[:bracket_end + 1]
		lyric_text := strings.trim_space(line[bracket_end + 1:])

		time, time_ok := parse_lrc_time(time_tag)
		if !time_ok do continue

		lyric := Lyrics {
			time = time,
			text = lyric_text,
		}
		append(&lyrics, lyric)
	}

	// Just to make sure
	slice.sort_by(lyrics[:], proc(a, b: Lyrics) -> bool {
		return a.time < b.time
	})

	return lyrics
}

load_lyrics_for_track :: proc(music_path: string) -> [dynamic]Lyrics {
	lrc_path := get_lrc_path(music_path)

	lrc_data, read_ok := os.read_entire_file_from_filename(lrc_path, context.temp_allocator)
	if !read_ok {
		return {}
	}

	lrc_content := string(lrc_data)

	return load_lyrics_from_string(lrc_content)
}

import "core:sync"
import "core:thread"
import "core:time"

Cover_Load_Result :: struct {
	playlist_index: int,
	cover_path:     string,
	texture:        fx.Texture,
	success:        bool,
}

cover_load_queue: [dynamic]Cover_Load_Result
cover_load_mutex: sync.Mutex
cover_loading_thread: ^thread.Thread
should_stop_loading: bool

init_cover_loading :: proc() {
	loading_covers = true

	clear(&cover_load_queue)

	for &playlist, i in playlists {
		if !playlist.loaded && len(playlist.cover_path) > 0 {
			append(
				&cover_load_queue,
				Cover_Load_Result {
					playlist_index = i,
					cover_path = playlist.cover_path,
					texture = {},
					success = false,
				},
			)
		}
	}

	cover_loading_thread = thread.create(cover_loading_worker)
	thread.start(cover_loading_thread)
}

cover_loading_worker :: proc(t: ^thread.Thread) {
	for i := 0; i < len(cover_load_queue) && !should_stop_loading; i += 1 {
		texture := fx.load_texture(cover_load_queue[i].cover_path) or_else fx.Texture{}

		sync.lock(&cover_load_mutex)
		cover_load_queue[i].texture = texture
		cover_load_queue[i].success = true
		sync.unlock(&cover_load_mutex)

		time.sleep(10 * time.Millisecond)
	}
}

process_loaded_covers :: proc() {
	sync.lock(&cover_load_mutex)
	defer sync.unlock(&cover_load_mutex)

	for i := 0; i < len(cover_load_queue); i += 1 {
		result := cover_load_queue[i]
		if result.success && result.playlist_index >= 0 && result.playlist_index < len(playlists) {
			playlists[result.playlist_index].cover = result.texture
			playlists[result.playlist_index].loaded = true
		}
	}
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

	// Clean up the dynamic array
	delete(cover_load_queue)
}
