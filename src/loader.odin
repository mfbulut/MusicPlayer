package main

import "fx"

import "core:fmt"
import "core:os"
import "core:os/os2"
import "core:hash"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

Lyrics :: struct {
	text: string,
	time: f32,
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

	small_cover:     fx.Texture,
	thumbnail_loaded: bool,
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

find_playlist_by_name :: proc(name: string) -> ^Playlist {
	for playlist, i in playlists {
		if playlist.name == name {
			return &playlists[i]
		}
	}
	return nil
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
		lyrics   = load_lyrics_for_track(file.fullpath)
	}

	tags, tags_ok := load_id3_tags(music.path)

	if tags_ok {
		music.tags = tags
		music.has_tags = true
	}

	if queue {
		append(&player.queue.tracks, music)
	} else {
		playlist := find_or_create_playlist(dir_path, dir_name)
		append(&playlist.tracks, music)
	}
}


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

	delete(cover_load_queue)
}

//////////////////////////////////////

init_thumbnail_loading :: proc() {
	thumbnail_loading_thread := thread.create(thumbnail_loading_worker)
	thread.start(thumbnail_loading_thread)
}

thumbnail_loading_worker :: proc(t: ^thread.Thread) {
	out: for {
		playlist := find_playlist_by_name(ui_state.selected_playlist)

		if ui_state.current_view == .LIKED {
			playlist = &liked_playlist
		}

		if playlist != nil {
			for &track in playlist.tracks {
				if !track.thumbnail_loaded {
					buffer := os.read_entire_file_from_filename(track.path, context.allocator) or_continue

					load_small_cover(&track, buffer)
					track.thumbnail_loaded = true

					delete(buffer)

					// Don't stress cpu too much
					time.sleep(10 * time.Millisecond)
					continue out
				}
			}
		}

		time.sleep(300 * time.Millisecond)
	}
}

