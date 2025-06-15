package main

import fx "../fx"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:thread"
import "core:sync"

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
    queue: Playlist,
    shuffled_indices: []int,
    shuffle_position: int,

    preload_thread: ^thread.Thread,
    preload_mutex: sync.Mutex,
    preload_active: bool,
}

player := Player {
    volume = 0.5,
    state = .STOPPED,
    queue = {
        name = "Queue",
    },
    preload_active = false,
}

load_track_audio_sync :: proc(track: ^Track) {
    sync.lock(&player.preload_mutex)
    defer sync.unlock(&player.preload_mutex)

    if track.audio_clip.loaded {
        return
    }

    clip := fx.load_audio(track.path)
    track.audio_clip = clip
    update_background = true
    fx.use_shader({})
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

preload_track_ptr: ^Track

preload_worker :: proc() {
    if preload_track_ptr != nil {
        load_track_audio_sync(preload_track_ptr)
    }

    sync.lock(&player.preload_mutex)
    player.preload_active = false
    preload_track_ptr = nil
    sync.unlock(&player.preload_mutex)
}

preload_next_track_async :: proc() {
    sync.lock(&player.preload_mutex)
    if player.preload_active {
        sync.unlock(&player.preload_mutex)
        return
    }
    player.preload_active = true
    sync.unlock(&player.preload_mutex)

    next_track_ptr: ^Track


    if len(player.queue.tracks) > 0 {
        next_track_ptr = &player.queue.tracks[len(player.queue.tracks) - 1]
        if next_track_ptr.audio_clip.loaded {
            sync.lock(&player.preload_mutex)
            player.preload_active = false
            sync.unlock(&player.preload_mutex)
            return
        }
    } else if len(player.current_playlist.tracks) > 0 {

        next_index: int

        if player.shuffle {
            if player.shuffle_position >= len(player.shuffled_indices) {
                next_index = player.shuffled_indices[0]
            } else {
                next_index = player.shuffled_indices[player.shuffle_position]
            }
        } else {
            next_index = (player.current_index + 1) % len(player.current_playlist.tracks)
        }

        next_track_ptr = &player.current_playlist.tracks[next_index]
        if next_track_ptr.audio_clip.loaded {
            sync.lock(&player.preload_mutex)
            player.preload_active = false
            sync.unlock(&player.preload_mutex)
            return
        }
    } else {
        sync.lock(&player.preload_mutex)
        player.preload_active = false
        sync.unlock(&player.preload_mutex)
        return
    }


    preload_track_ptr = next_track_ptr
    player.preload_thread = thread.create_and_start(preload_worker)
}


play_track :: proc(track: Track, playlist: Playlist, queue: bool = false) {
    if player.current_track.audio_clip.loaded {
        fx.stop_audio(&player.current_track.audio_clip)
    }

    new_track := track

    if !new_track.audio_clip.loaded {
        load_track_audio(&new_track)
    }

    new_track.lyrics = load_lyrics_for_track(new_track.path)
    player.current_track = new_track
    player.duration = fx.get_duration(&player.current_track.audio_clip)
    player.position = 0
    fx.play_audio(&player.current_track.audio_clip)
    fx.set_volume(&player.current_track.audio_clip, math.pow(player.volume, 2.0))
    player.state = .PLAYING

    if queue do return
    player.current_playlist = playlist
    for t, i in playlist.tracks {
        if track.name == t.name && track.path == t.path {
            player.current_index = i
        }
    }

    cleanup_preloaded_tracks()
    preload_next_track_async()
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
        if player.shuffle_position >= len(player.shuffled_indices) {
            rand.shuffle(player.shuffled_indices[:])
            player.shuffle_position = 0
        }
        player.current_index = player.shuffled_indices[player.shuffle_position]
        player.shuffle_position += 1
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

song_shuffle :: proc() {
    if player.shuffle {
        player.shuffled_indices = make([]int, len(player.current_playlist.tracks))
        for i in 0..<len(player.shuffled_indices) {
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

insert_as_last_track :: proc(track : Track) {
    inject_at_elem(&player.queue.tracks, 0, track)
}

insert_as_next_track :: proc(track : Track) {
    append(&player.queue.tracks, track)
}

cleanup_preloaded_tracks :: proc() {
    for &track in player.current_playlist.tracks {
        if track.path == player.current_track.path {
            continue
        }

        is_next_track := false

        if len(player.queue.tracks) > 0 {
            queue_next := &player.queue.tracks[len(player.queue.tracks) - 1]
            if track.path == queue_next.path {
                is_next_track = true
            }
        } else if len(player.current_playlist.tracks) > 0 {
            next_index: int
            if player.shuffle {
                if player.shuffle_position < len(player.shuffled_indices) {
                    next_index = player.shuffled_indices[player.shuffle_position]
                } else {
                    next_index = player.shuffled_indices[0]
                }
            } else {
                next_index = (player.current_index + 1) % len(player.current_playlist.tracks)
            }

            if &track == &player.current_playlist.tracks[next_index] {
                is_next_track = true
            }
        }

        if !is_next_track && track.audio_clip.loaded {
            unload_track_audio(&track)
        }
    }
}

cleanup_player :: proc() {
    sync.lock(&player.preload_mutex)
    defer sync.unlock(&player.preload_mutex)

    if player.preload_thread != nil && player.preload_active {
        thread.join(player.preload_thread)
        thread.destroy(player.preload_thread)
        player.preload_thread = nil
    }
}