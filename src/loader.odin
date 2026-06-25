package main

import "fx"
import "core:os"
import "core:hash"
import "core:slice"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import "core:strconv"

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
	hash:             u64,
	path:             string,
	name:             string,
	playlist:         ^Playlist,

	audio:            fx.Audio,
	lyrics:           [dynamic]Lyrics,

	cover:            fx.Texture,
	has_cover:        bool,

	tags:             Tags,
	has_tags:         bool,

	small_cover:      fx.Texture,
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

load_music :: proc() {
	music_dir := os.user_music_dir(context.allocator) or_else panic("Couldn't find music dir")
	defer delete(music_dir)

	w := os.walker_create(music_dir)
	defer os.walker_destroy(&w)

	for info in os.walker_walk(&w) {
		if info.type == .Directory {
			if strings.starts_with(info.name, "_") || strings.starts_with(info.name, ".") {
				os.walker_skip_dir(&w)
			}
		} else {
			process_music_file(info)
		}
	}

	for &playlist in playlists {
		sort_playlist_tracks(playlist)
	}
}

find_or_create_playlist :: proc(dir_path: string, dir_name: string) -> ^Playlist {
	dir_name := strings.clone(dir_name)

	for &playlist in playlists {
		if playlist.name == dir_name {
			return playlist
		}
	}

	playlist := new(Playlist)
	playlist.path   = dir_path
	playlist.name   = dir_name

	cover_path, _ := os.join_path({dir_path, "cover.qoi"}, context.allocator)

	if os.exists(cover_path) {
		playlist.cover_path = cover_path
	} else {
		delete(cover_path)
		cover_path, _ = os.join_path({dir_path, "cover.png"}, context.allocator)
		if os.exists(cover_path) {
			playlist.cover_path = cover_path
		} else {
			delete(cover_path)
			cover_path, _ = os.join_path({dir_path, "cover.jpg"}, context.allocator)
			if os.exists(cover_path) {
				playlist.cover_path = cover_path
			}
		}
	}

	append(&playlists, playlist)
	return playlist
}

sort_playlists :: proc() {
	slice.sort_by(playlists[:], proc(a, b: ^Playlist) -> bool {
		return strings.compare(strings.to_lower(a.name), strings.to_lower(b.name)) < 0
	})
}

sort_playlist_tracks :: proc(playlist: ^Playlist) {
	if playlist == nil || len(playlist.tracks) == 0 {
		return
	}

	same_album := true
	first_album := playlist.tracks[0].tags.album

	for track in playlist.tracks {
		if track.tags.album != first_album {
			same_album = false
			break
		}
	}

	if same_album && len(first_album) > 0 {
		slice.sort_by(playlist.tracks[:], proc(a, b: Track) -> bool {
			a_track := parse_track_number(a.tags.track)
			b_track := parse_track_number(b.tags.track)

			if a_track != b_track {
				return a_track < b_track
			}

			return strings.compare(strings.to_lower(a.name), strings.to_lower(b.name)) < 0
		})
	} else {
		slice.sort_by(playlist.tracks[:], proc(a, b: Track) -> bool {
			return strings.compare(strings.to_lower(a.name), strings.to_lower(b.name)) < 0
		})
	}
}

parse_track_number :: proc(track_str: string) -> int {
	if len(track_str) == 0 {
		return -1
	}

	parts := strings.split(track_str, "/", context.temp_allocator)
	number_str := parts[0] if len(parts) > 0 else track_str

	track_num, ok := strconv.parse_int(strings.trim_space(number_str))
	if ok {
		return track_num
	}

	return -1
}

process_music_file :: proc(file: os.File_Info) {
	dir_path, filename := os.split_path(file.fullpath)
	name, ext := os.split_filename(filename)

	if ext != "mp3" && ext != "wav" && ext != "flac" && ext != "opus" && ext != "ogg" do return

	dir_name := os.base(dir_path)
	playlist := find_or_create_playlist(dir_path, dir_name)

	music := Track {
		hash     = hash.fnv64a(transmute([]u8)file.fullpath),
		path     = strings.clone(file.fullpath),
		name     = strings.clone(name),
		lyrics   = load_lyrics_for_track(file.fullpath),
		playlist = playlist
	}

	tags: Tags
	tags_ok: bool

	switch ext {
	case "mp3":
		tags, tags_ok = load_id3_tags(music.path)
	case "flac":
		tags, tags_ok = load_flac_vorbis_comment_tags(music.path)
	case "opus":
		tags, tags_ok = load_opus_tags(music.path)
	case "ogg":
		tags, tags_ok = load_ogg_vorbis_tags(music.path)
	}

	if tags_ok {
		music.tags = tags
		music.has_tags = true
	}

	append(&playlist.tracks, music)
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
	should_stop_loading = false

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
		playlist := ui_state.selected_playlist

		if playlist != nil {
			for &track in playlist.tracks {
				if !track.thumbnail_loaded {
					buffer := os.read_entire_file(track.path, context.allocator) or_continue
					load_small_cover(&track, buffer)
					delete(buffer)
					continue out
				}
			}
		}

		time.sleep(300 * time.Millisecond)
	}
}