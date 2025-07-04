package main

import "fx"

import "core:fmt"
import "core:os"
import "core:os/os2"
import "core:hash"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:thread"
import "core:sync"

Lyrics :: struct {
	time: f32,
	text: string,
}

Tags :: struct {
	title:        string,
	artist:       string,
	album:        string,
	year:         string,
	genre:        string,
	track:        string,
	comment:      string,
	album_artist: string,
}

Track :: struct {
	hash:       u64,
	path:       string,
	name:       string,
	playlist:   string,

	audio: fx.Audio,

	lyrics:       [dynamic]Lyrics,

	cover:        fx.Texture,
	has_cover:    bool,

	tags:         Tags,
	has_tags:     bool,

	metadata_loaded : bool,
}

Playlist :: struct {
	path:       string,
	name:       string,
	tracks:     [dynamic]Track,
	cover:      fx.Texture,
	cover_path: string,
	loaded:     bool,
}

load_files :: proc(dir_path: string) {
	w := os2.walker_create(dir_path)
	defer os2.walker_destroy(&w)

	for info in os2.walker_walk(&w) {
		if path, err := os2.walker_error(&w); err != nil {
			fmt.eprintln("Error reading entry:", path, "->", err)
			continue
		}

		#partial switch info.type {
		case .Directory:
			// Ignore ".git", "__MACOSX", etc.
			if strings.starts_with(info.name, "_") || strings.starts_with(info.name, ".") {
				os2.walker_skip_dir(&w)
			}
		case .Regular:
			// Failing to clone into permanent allocator probably means OOM, give up.
			info := os2.file_info_clone(info, context.allocator) or_break
			process_music_file(info)
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
		hash     = hash.fnv64a(transmute([]u8)file.fullpath),
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

cover_loading_thread: ^thread.Thread

init_cover_loading :: proc() {
	cover_loading_thread = thread.create(cover_loading_worker)
	thread.start(cover_loading_thread)
}

cover_loading_worker :: proc(t: ^thread.Thread) {
	for &playlist, i in playlists {
		if !playlist.loaded && len(playlist.cover_path) > 0 {
			texture := fx.load_texture(playlist.cover_path) or_else fx.Texture{}

			playlist.cover = texture
			playlist.loaded = true
		}
	}

	cleanup_cover_loading()
}

cleanup_cover_loading :: proc() {
	thread.join(cover_loading_thread)
	thread.destroy(cover_loading_thread)
}

metadata_loading_thread : ^thread.Thread
metadata_load_mutex : sync.Mutex
metadata_thread_over : bool

init_metadata_loading :: proc() {
	metadata_loading_thread = thread.create(metadata_loading_worker)
	thread.start(metadata_loading_thread)
}

metadata_loading_worker :: proc(t: ^thread.Thread) {
	for &playlist in playlists {
		for &track in playlist.tracks {
			if !track.metadata_loaded {
				track_copy := track

				buffer, ok := os.read_entire_file_from_filename(track_copy.path, context.temp_allocator)
				if !ok {
					continue
				}

				// Setting the last bool to true makes gpu run out of memory
				// Also if you enable this you should disable cover unloading
				// Also see commented experimental code at playlist.odin

				load_metadata(&track_copy, buffer, false)

				sync.lock(&metadata_load_mutex)

				track = track_copy

				sync.unlock(&metadata_load_mutex)
			}
		}
	}

	cleanup_cover_loading()

	metadata_thread_over = true
}

cleanup_metadata_loading :: proc() {
	thread.join(metadata_loading_thread)
	thread.destroy(metadata_loading_thread)
}