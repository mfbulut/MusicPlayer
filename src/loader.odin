package main

import "fx"
import "core:encoding/json"
import "core:fmt"
import "core:os/os2"
import "core:hash"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

Lyrics :: struct {
	text: string `json:"text"`,
	time: f32    `json:"time"`,
}

Tags :: struct {
	title:        string `json:"title"`,
	artist:       string `json:"artist"`,
	album:        string `json:"album"`,
	year:         string `json:"year"`,
	genre:        string `json:"genre"`,
	track:        string `json:"track"`,
	comment:      string `json:"comment"`,
	album_artist: string `json:"album_artist"`,
}

Track :: struct {
	hash:       u64                `json:"hash"`,
	path:       string             `json:"path"`,
	name:       string             `json:"name"`,
	playlist:   string             `json:"playlist"`,

	audio: fx.Audio                `json:"-"`,
	lyrics:       [dynamic]Lyrics  `json:"lyrics"`,

	cover:        fx.Texture       `json:"-"`,
	has_cover:    bool             `json:"has_cover"`,

	tags:         Tags             `json:"tags"`,
	has_tags:     bool             `json:"has_tags"`,

	small_cover:     fx.Texture    `json:"-"`,
	thumbnail_loaded: bool         `json:"-"`,
}

Playlist :: struct {
	path:       string         `json:"path"`,
	name:       string         `json:"name"`,
	tracks:     [dynamic]Track `json:"tracks"`,
	cover:      fx.Texture     `json:"-"`,
	cover_path: string         `json:"cover_path"`,
	loaded:     bool           `json:"-"`,
}

save_cache :: proc(playlists: []Playlist, path: string) -> bool {
	json_data, marshal_err := json.marshal(playlists)
	if marshal_err != nil {
		fmt.eprintln("Error marshaling cache data:", marshal_err)
		return false
	}
	defer delete(json_data)

	write_err := os2.write_entire_file(path, json_data)
	if write_err != nil {
		fmt.eprintln("Error writing cache file:", write_err)
		return false
	}

	return true
}

load_cache :: proc(path: string) -> (bool) {
	if !os2.exists(path) {
		return false
	}

	json_data, read_err := os2.read_entire_file(path, context.allocator)
	if read_err != nil {
		fmt.eprintln("Error reading cache file:", read_err)
		return false
	}
	defer delete(json_data)

	unmarshal_err := json.unmarshal(json_data, &playlists)
	if unmarshal_err != nil {
		fmt.eprintln("Error unmarshaling cache data:", unmarshal_err)
		return false
	}

	return true
}

loader_query : [dynamic]string

load_files :: proc(dir_path: string, load_from_cache := true) {
	cache_path := fmt.tprintf("%s\\fxMusic\\cache.json", os2.get_env("LOCALAPPDATA", context.temp_allocator))

	if load_from_cache && load_cache(cache_path) {
		return
	}

	append(&loader_query, dir_path)

	for {
		path, ok := pop_safe(&loader_query)

		if ok {
			files, err := os2.read_all_directory_by_path(path, context.allocator)
			if err != nil {
				fmt.eprintln("Error reading directory:", path, "->", err)
				return
			}

			for file in files {
				if file.type == .Directory {
					if strings.starts_with(file.name, "_") || strings.starts_with(file.name, ".") {
						continue
					}
					append(&loader_query, file.fullpath)
				} else {
					process_music_file(file)
				}
			}
		} else {
			break
		}
	}

	save_cache(playlists[:], cache_path)
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
	}

	cover_path := filepath.join({dir_path, "cover.qoi"})

	if os2.exists(cover_path) {
		playlist.cover_path = cover_path
	} else {
		delete(cover_path)
		cover_path = filepath.join({dir_path, "cover.png"})
		if os2.exists(cover_path) {
			playlist.cover_path = cover_path
		} else {
			delete(cover_path)
			cover_path = filepath.join({dir_path, "cover.jpg"})
			if os2.exists(cover_path) {
				playlist.cover_path = cover_path
			}
		}
	}

	append(&playlists, playlist)
	return &playlists[len(playlists) - 1]
}

sort_playlists :: proc() {
	slice.sort_by(playlists[:], proc(a, b: Playlist) -> bool {
		return strings.compare(strings.to_lower(a.name), strings.to_lower(b.name)) < 0
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
		lyrics   = load_lyrics_for_track(file.fullpath),
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
					buffer := os2.read_entire_file(track.path, context.allocator) or_continue

					load_small_cover(&track, buffer)
					track.thumbnail_loaded = true
					delete(buffer)

					continue out
				}
			}
		}

		time.sleep(300 * time.Millisecond)
	}
}