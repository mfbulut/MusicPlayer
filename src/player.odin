package main

import "fx"

import "core:os/os2"
import "core:math"
import "core:math/rand"
import "core:sync"

PlayerState :: enum {
	STOPPED,
	PLAYING,
	PAUSED,
}

Player :: struct {
	state:            PlayerState,
	position:         f32,
	duration:         f32,
	volume:           f32,

	queue:            Playlist,

	current_index:    int,
	current_track:    Track,
	current_playlist: Playlist,

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

play_track :: proc(track: Track, playlist: Playlist, queue: bool = false) {
	if player.current_track.audio.loaded {
		unload_cover(&player.current_track)
		unload_track_audio(&player.current_track)
	}

	ui_state.lyrics_scrollbar.scroll = 0
	ui_state.lyrics_scrollbar.target = 0

	if !os2.exists(track.path) {
		show_alert({}, "File not found", "Ensure file exist then refresh using F5", 2)
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
	player.current_playlist = playlist

	if !player.shuffle {
		for t, i in playlist.tracks {
			if track.name == t.name && track.path == t.path {
				player.current_index = i
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
		play_track(track, player.current_playlist, true)
		return
	}

	if len(player.current_playlist.tracks) == 0 {
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
		player.current_index = (player.current_index + 1) % len(player.current_playlist.tracks)
	}

	next_track := player.current_playlist.tracks[player.current_index]
	play_track(next_track, player.current_playlist)
}

previous_track :: proc() {
	if len(player.current_playlist.tracks) == 0 {
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
			player.current_index = len(player.current_playlist.tracks) - 1
		}
	}

	prev_track := player.current_playlist.tracks[player.current_index]
	play_track(prev_track, player.current_playlist)
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
	if player.shuffle {
		player.shuffled_indices = make([]int, len(player.current_playlist.tracks))
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
