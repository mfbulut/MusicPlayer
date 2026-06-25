package main

import "fx"

import "core:os"
import "core:math"
import "core:math/rand"


Player :: struct {
	state: enum { STOPPED, PLAYING, PAUSED },
	position:         f32,
	duration:         f32,
	volume:           f32,

	queue:            Playlist,

	current_index:    int,
	current_track:    Track,

	shuffle:          bool,
	shuffle_position: int,
	shuffled_indices: []int,
}

player := Player {
	volume = 0.5,
	queue = {name = "Queue"},
}

load_track_audio :: proc(track: ^Track) {
	clip := fx.load_audio(track.path)
	track.audio = clip
	update_background = true
	fx.use_shader({})
}

unload_track_audio :: proc(track: ^Track) {
	if !track.audio.loaded {
		return
	}
	fx.unload_audio(&track.audio)
}

play_track :: proc(track: Track, playlist: ^Playlist, queue: bool = false) {
	if player.current_track.audio.loaded {
		unload_cover(&player.current_track)
		unload_track_audio(&player.current_track)
	}

	ui_state.lyrics_scrollbar.scroll = 0
	ui_state.lyrics_scrollbar.target = 0

	if !os.exists(track.path) {
		show_alert({}, "File not found", "Ensure file exist restart the application", 2)
		return
	}

	new_track := track

	load_track_audio(&new_track)
	load_cover(&new_track, new_track.audio.file_data)

	player.current_track = new_track
	player.state = .PLAYING
	player.position = 0
	player.duration = fx.get_duration(&player.current_track.audio)

	fx.play_audio(&player.current_track.audio)
	fx.set_volume(&player.current_track.audio, math.pow(player.volume, 2.0))

	if queue do return

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
			cloned_tracks := make([dynamic]Track, len(playlist.tracks))
			copy(cloned_tracks[:], playlist.tracks[:])
			cloned_playlist.tracks = cloned_tracks
			ui_state.playing_playlist = cloned_playlist
		} else {
			ui_state.playing_playlist = playlist
		}
	}

	if !player.shuffle {
		if ui_state.playing_playlist != nil {
			for t, i in ui_state.playing_playlist.tracks {
				if track.name == t.name && track.path == t.path {
					player.current_index = i
				}
			}
		}
	}
}

toggle_playback :: proc() {
	if !player.current_track.audio.loaded {
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
		track := pop(&player.queue.tracks)
		play_track(track, ui_state.playing_playlist, true)

		if len(player.queue.tracks) == 0 do ui_state.show_queue_sidebar = false

		return
	}

	if ui_state.playing_playlist == nil || len(ui_state.playing_playlist.tracks) == 0 {
		return
	}

	if player.shuffle {
		player.shuffle_position += 1

		if player.shuffle_position >= len(player.shuffled_indices) {
			rand.shuffle(player.shuffled_indices[:])
			player.shuffle_position = 0
		}

		player.current_index = player.shuffled_indices[player.shuffle_position]
	} else {
		player.current_index = (player.current_index + 1) % len(ui_state.playing_playlist.tracks)
	}

	next_track := ui_state.playing_playlist.tracks[player.current_index]
	play_track(next_track, ui_state.playing_playlist)
}

previous_track :: proc() {
	if ui_state.playing_playlist == nil || len(ui_state.playing_playlist.tracks) == 0 {
		return
	}

	if player.shuffle {
		player.shuffle_position -= 1

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

	prev_track := ui_state.playing_playlist.tracks[player.current_index]
	play_track(prev_track, ui_state.playing_playlist)
}

seek_to_position :: proc(position: f32) {
	if !player.current_track.audio.loaded {
		return
	}
	clamped_pos := clamp(position, 0.0, player.duration)
	fx.set_time(&player.current_track.audio, clamped_pos)
	player.position = clamped_pos
}

update_player :: proc(dt: f32) {
	if !player.current_track.audio.loaded || player.state != .PLAYING {
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

insert_as_last_track :: proc(track: Track) {
	inject_at_elem(&player.queue.tracks, 0, track)
}

insert_as_next_track :: proc(track: Track) {
	append(&player.queue.tracks, track)
}
