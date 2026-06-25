package main

import "fx"

import "core:os"
import "core:math"
import "core:math/rand"
import "core:sync"

Player :: struct {
	state: enum { STOPPED, PLAYING, PAUSED },
	position:         f32,
	duration:         f32,
	volume:           f32,

	queue:            Playlist,

	current_index:    int,
	current_track:    ^Track,
	track_mutex:      sync.Mutex,

	shuffle:          bool,
	shuffle_position: int,
	shuffled_indices: []int,
}

player := Player {
	volume = 0.5,
	queue = {name = "Queue"},
}

load_track :: proc(track: ^Track) {
	clip := fx.load_audio(track.path)
	track.audio = clip
	load_cover(track, track.audio.file_data)

	fx.begin_render_to_texture(&background, {0, 128, 0, 0})
	fx.set_scissor(0, 0, 2048, 2048)
	fx.use_shader(blur_shader)
	fx.draw_texture_cropped(track.cover, 0, 0, 2048, 2048, fx.WHITE)
	fx.end_render_to_texture()
	fx.use_shader({})
}

unload_track_audio :: proc(track: ^Track) {
	if !track.audio.loaded {
		return
	}
	fx.unload_audio(&track.audio)
}

play_track :: proc(track: ^Track, playlist: ^Playlist, queue: bool = false) {
	if player.current_track != nil && player.current_track.audio.loaded {
		unload_cover(player.current_track)
		unload_track_audio(player.current_track)
	}

	ui_state.lyrics_scrollbar.scroll = 0
	ui_state.lyrics_scrollbar.target = 0

	if !os.exists(track.path) {
		show_alert({}, "File not found", "Ensure file exist then refresh using F5", 2)
		return
	}

	track := track

	if !queue {
		is_from_ui := true
		if playlist == ui_state.playing_playlist {
			is_from_ui = false
		}

		if is_from_ui {
			if ui_state.playing_playlist != nil && (ui_state.playing_playlist.name == "Search Results" || ui_state.playing_playlist.name == "Liked Songs") {
				delete(ui_state.playing_playlist.tracks)
				free(ui_state.playing_playlist)
			}

			if playlist != nil && (playlist.name == "Search Results" || playlist.name == "Liked Songs") {
				cloned_playlist := new(Playlist)
				cloned_playlist^ = playlist^
				cloned_tracks := make([dynamic]^Track, len(playlist.tracks))
				copy(cloned_tracks[:], playlist.tracks[:])
				cloned_playlist.tracks = cloned_tracks
				ui_state.playing_playlist = cloned_playlist

				index := -1
				for t, i in playlist.tracks {
					if t == track {
						index = i
						break
					}
				}

				if index != -1 {
					track = cloned_playlist.tracks[index]
				}
			} else {
				ui_state.playing_playlist = playlist
			}
		}

		if ui_state.playing_playlist != nil {
			for t, i in ui_state.playing_playlist.tracks {
				if track == t {
					player.current_index = i
					break
				}
			}
		}
	}

	track.playlist = ui_state.playing_playlist
	load_track(track)

	player.current_track = track
	player.duration = fx.get_duration(&player.current_track.audio)
	player.state = .PLAYING
	fx.play_audio(&player.current_track.audio)
	fx.set_volume(&player.current_track.audio, math.pow(player.volume, 2.0))
}

toggle_playback :: proc() {
	if player.current_track == nil || !player.current_track.audio.loaded {
		return
	}

	switch player.state {
	case .PLAYING:
		fx.pause_audio(&player.current_track.audio)
		player.state = .PAUSED
	case .PAUSED, .STOPPED:
		fx.play_audio(&player.current_track.audio)
		player.state = .PLAYING
	}
}

next_track :: proc() {
	if len(player.queue.tracks) > 0 {
		popped_track := pop(&player.queue.tracks)
		play_track(popped_track, ui_state.playing_playlist, true)

		if len(player.queue.tracks) == 0 do ui_state.show_queue_sidebar = false

		return
	}

	if ui_state.playing_playlist == nil || len(ui_state.playing_playlist.tracks) == 0 {
		return
	}

	if player.shuffle {
		player.shuffle_position = player.shuffle_position + 1

		if player.shuffle_position >= len(player.shuffled_indices) {
			player.shuffle_position = 0
		}

		player.current_index = player.shuffled_indices[player.shuffle_position]
	} else {
		player.current_index = player.current_index + 1
		if player.current_index >= len(ui_state.playing_playlist.tracks) {
			player.current_index = 0
		}
	}

	next_track_ptr := ui_state.playing_playlist.tracks[player.current_index]
	play_track(next_track_ptr, ui_state.playing_playlist)
}

previous_track :: proc() {
	if ui_state.playing_playlist == nil || len(ui_state.playing_playlist.tracks) == 0 {
		return
	}

	if player.shuffle {
		player.shuffle_position = player.shuffle_position - 1

		if player.shuffle_position < 0 {
			player.shuffle_position = len(player.shuffled_indices) - 1
		}

		player.current_index = player.shuffled_indices[player.shuffle_position]
	} else {
		player.current_index = player.current_index - 1
		if player.current_index < 0 {
			player.current_index = len(ui_state.playing_playlist.tracks) - 1
		}
	}

	prev_track_ptr := ui_state.playing_playlist.tracks[player.current_index]
	play_track(prev_track_ptr, ui_state.playing_playlist)
}

seek_to_position :: proc(position: f32) {
	if player.current_track == nil || !player.current_track.audio.loaded {
		return
	}
	clamped_pos := clamp(position, 0.0, player.duration)
	fx.set_time(&player.current_track.audio, clamped_pos)
	player.position = clamped_pos
}

update_player :: proc(dt: f32) {
	if player.current_track == nil || !player.current_track.audio.loaded || player.state != .PLAYING {
		return
	}
	player.position = fx.get_time(&player.current_track.audio)
	if !fx.is_playing(&player.current_track.audio) &&
	   player.position >= player.duration - 0.1 {
		next_track()
	}
}

get_current_lyric_index :: proc(lyrics: []Lyrics, current_time: f32) -> int {
	if len(lyrics) == 0 do return -1
	current_index := -1
	for lyric, i in lyrics {
		if lyric.time <= current_time {
			current_index = i
		} else {
			break
		}
	}
	return current_index
}

seek_to_lyric :: proc(lyric_index: int, lyrics: []Lyrics) {
	if lyric_index >= 0 && lyric_index < len(lyrics) {
		seek_to_position(lyrics[lyric_index].time)
		ui_state.follow_lyrics = true
	}
}

song_shuffle :: proc() {
	if player.shuffle && ui_state.playing_playlist != nil {
		player.shuffled_indices = make([]int, len(ui_state.playing_playlist.tracks))
		for i in 0 ..< len(player.shuffled_indices) {
			player.shuffled_indices[i] = i
		}
		rand.shuffle(player.shuffled_indices[:])
		player.shuffle_position = 0
	}
}

toggle_shuffle :: proc() {
	player.shuffle = !player.shuffle
	song_shuffle()
}

insert_as_last_track :: proc(track: ^Track) {
	inject_at_elem(&player.queue.tracks, 0, track)
}

insert_as_next_track :: proc(track: ^Track) {
	append(&player.queue.tracks, track)
}
