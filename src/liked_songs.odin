package main

import "core:fmt"
import "core:os"
import "core:time"

import "core:strings"
import "core:strconv"
import "core:slice"

import "core:encoding/ini"

LikedSong :: struct {
    name: string,
    playlist: string,
    timestamp: i64,
}

liked_songs: [dynamic]LikedSong

liked_playlist : Playlist = Playlist {
    name = "Liked Songs",
    tracks = make([dynamic]Track),
}

init_liked_songs :: proc(save_file: string = "songs.ini") -> bool {
    liked_songs = make([dynamic]LikedSong)

    if os.exists(save_file) {
        res := load_liked_songs_from_file(save_file)
        get_all_liked_songs()
        return res
    }

    return true
}

create_song_key :: proc(name: string, playlist: string) -> string {
    return fmt.tprintf("%s|%s", name, playlist, context.temp_allocator)
}

find_liked_song_index :: proc(name: string, playlist: string) -> int {
    for song, i in liked_songs {
        if song.name == name && song.playlist == playlist {
            return i
        }
    }
    return -1
}

is_song_liked :: proc(name: string, playlist: string) -> bool {
    index := find_liked_song_index(name, playlist)
    return index != -1
}

set_liked_song :: proc(name: string, playlist: string, liked: bool, save_file: string = "songs.ini") {
    index := find_liked_song_index(name, playlist)

    if liked {
        new_song := LikedSong{
            name = name,
            playlist = playlist,
            timestamp = time.now()._nsec,
        }

        if index != -1 {
            liked_songs[index] = new_song
        } else {
            append(&liked_songs, new_song)
        }
    } else {
        if index != -1 {
            ordered_remove(&liked_songs, index)
        }
    }

    save_liked_songs_to_file(save_file)
}

get_all_liked_songs :: proc() {
    if len(liked_playlist.tracks) > 0 {
        delete(liked_playlist.tracks)
        liked_playlist.tracks = make([dynamic]Track)
    }

    for liked_song in liked_songs {
        source_playlist := find_playlist_by_name(liked_song.playlist)
        for track in source_playlist.tracks {
            if track.name == liked_song.name {

                track_copy := Track{
                    path = track.path,
                    name = track.name,
                    playlist = track.playlist,
                    lyrics = track.lyrics,
                    audio_clip = track.audio_clip,
                }

                append(&liked_playlist.tracks, track_copy)
                break
            }
        }
    }

    slice.sort_by(liked_playlist.tracks[:], proc(a, b: Track) -> bool {
        a_index := find_liked_song_index(a.name, a.playlist)
        b_index := find_liked_song_index(b.name, b.playlist)
        if a_index < 0 || b_index < 0 {
            fmt.println("ERROR: Can't find liked song")
        }
        return liked_songs[a_index].timestamp > liked_songs[b_index].timestamp
    })
}

toggle_song_like :: proc(name: string, playlist: string, save_file: string = "songs.ini") {
    current_state := is_song_liked(name, playlist)
    set_liked_song(name, playlist, !current_state, save_file)
}

save_liked_songs_to_file :: proc(filename: string = "songs.ini") -> bool {
    ini_map := make(ini.Map)
    defer delete(ini_map)

    // Save settings section
    settings_section := make(map[string]string)
    settings_section["volume"] = fmt.aprintf("%.6f", player.volume)
    settings_section["use_gaussian"] = use_gaussian ? "true" : "false"
    ini_map["settings"] = settings_section

    // Save liked songs
    for song, i in liked_songs {
        // Todo: Fix this
        // if song has [] or = in the title this can fail
        song_section := make(map[string]string)

        song_section["playlist"] = song.playlist
        song_section["timestamp"] = fmt.aprintf("%d", song.timestamp)

        ini_map[song.name] = song_section
    }

    ini_data := ini.save_map_to_string(ini_map, context.allocator)
    defer delete(ini_data)

    write_success := os.write_entire_file(filename, transmute([]u8)ini_data)
    if !write_success {
        fmt.printf("Error writing liked songs to file: %s\n", filename)
        return false
    }
    return true
}

load_liked_songs_from_file :: proc(filename: string) -> bool {
    ini_map, err, ok := ini.load_map_from_path(filename, context.allocator)
    if !ok {
        fmt.printf("Could not read liked songs file: %s\n", err)
        return false
    }

    defer ini.delete_map(ini_map)

    clear(&liked_songs)

    if settings_data, settings_ok := ini_map["settings"]; settings_ok {
        if volume_str, volume_ok := settings_data["volume"]; volume_ok {
            if volume, parse_ok := strconv.parse_f32(volume_str); parse_ok {
                player.volume = volume
            }
        }

        if use_gaussian_str, gaussian_ok := settings_data["use_gaussian"]; gaussian_ok {
            use_gaussian = use_gaussian_str == "true"
        }
    }

    // Load liked songs (skip settings section)
    for section_name, section_data in ini_map {
        if section_name == "settings" do continue

        song := LikedSong{}

        song.name = strings.clone(section_name)

        if playlist, ok := section_data["playlist"]; ok {
            song.playlist = strings.clone(playlist)
        }

        if timestamp_str, ok := section_data["timestamp"]; ok {
            if timestamp, parse_ok := strconv.parse_i64(timestamp_str); parse_ok {
                song.timestamp = timestamp
            }
        }

        append(&liked_songs, song)
    }

    return true
}