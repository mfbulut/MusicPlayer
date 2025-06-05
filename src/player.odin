package main

import fx "../fx"

import "core:math/rand"

PlayerState :: enum {
    STOPPED,
    PLAYING,
    PAUSED,
}

Player :: struct {
    current_track: Track,
    state: PlayerState,
    position: f32,
    duration: f32,
    volume: f32,
    shuffle: bool,
    current_playlist: Playlist,
    current_index: int,
    queue: Playlist
}

player := Player {
    volume = 0.5,
    state = .STOPPED,
    queue = {
        name = "Queue",
    }
}

load_track_audio :: proc(track: ^Track) {
    clip := fx.load_audio(track.path)
    track.audio_clip = clip
    update_background = true
    fx.use_shader({})
}

unload_track_audio :: proc(track: ^Track) {
    if !track.audio_clip.loaded {
        return
    }
    fx.unload_audio(&track.audio_clip)
}

play_track :: proc(track: Track, playlist: Playlist, queue: bool = false) {
    if player.current_track.audio_clip.loaded {
        fx.stop_audio(&player.current_track.audio_clip)
        fx.unload_audio(&player.current_track.audio_clip)
    }

    new_track := track
    load_track_audio(&new_track)
    player.current_track = new_track
    player.duration = fx.get_duration(&player.current_track.audio_clip)
    player.position = 0
    fx.set_volume(&player.current_track.audio_clip, player.volume)
    fx.play_audio(&player.current_track.audio_clip)
    player.state = .PLAYING

    if queue do return

    // clear(&player.queue.tracks)

    player.current_playlist = playlist
    for t, i in playlist.tracks {
        if track.name == t.name && track.path == t.path {
            player.current_index = i
        }
    }
}

toggle_playback :: proc() {
    if !player.current_track.audio_clip.loaded {
        return
    }
    switch player.state {
    case .PLAYING:
        fx.pause_audio(&player.current_track.audio_clip)
        player.state = .PAUSED
    case .PAUSED, .STOPPED:
        fx.play_audio(&player.current_track.audio_clip)
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
        player.current_index = rand.int_max(len(player.current_playlist.tracks))
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
        player.current_index = rand.int_max(len(player.current_playlist.tracks))
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
    if !player.current_track.audio_clip.loaded {
        return
    }
    clamped_pos := clamp(position, 0.0, player.duration)
    fx.set_time(&player.current_track.audio_clip, clamped_pos)
    player.position = clamped_pos
}

update_player :: proc(dt: f32) {
    if !player.current_track.audio_clip.loaded || player.state != .PLAYING {
        return
    }
    player.position = fx.get_time(&player.current_track.audio_clip)
    if !fx.is_playing(&player.current_track.audio_clip) && player.position >= player.duration - 0.1 {
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

toggle_shuffle :: proc() {
    player.shuffle = !player.shuffle
}

insert_next_track :: proc(track : Track) {
    inject_at_elem(&player.queue.tracks, 0, track)
}
