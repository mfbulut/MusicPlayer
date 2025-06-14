package main

import "core:fmt"
import "core:os"
import "core:time"

import "core:io"
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

SAVE_FILE :: "songs.ini"

load_state :: proc(){
    liked_songs = make([dynamic]LikedSong)

    if os.exists(SAVE_FILE) {
        ini_map, err, ok := ini.load_map_from_path(SAVE_FILE, context.allocator)
        if !ok {
            fmt.printf("Could not read liked songs file: %s\n", err)
            return
        }

        defer ini.delete_map(ini_map)

        clear(&liked_songs)

        if settings_data, settings_ok := ini_map["settings"]; settings_ok {
            if path_str, path_ok := settings_data["path"]; path_ok {
                music_dir = strings.clone(path_str)
            }

            if volume_str, volume_ok := settings_data["volume"]; volume_ok {
                if volume, parse_ok := strconv.parse_f32(volume_str); parse_ok {
                    player.volume = volume
                }
            }

            if theme_str, theme_ok := settings_data["theme"]; theme_ok {
                if theme, parse_ok := strconv.parse_int(theme_str); parse_ok {
                    ui_state.theme = theme
                }
            }

            if shuffle_str, shuffle_ok := settings_data["shuffle"]; shuffle_ok {
                if shuffle, parse_ok := strconv.parse_bool(shuffle_str); parse_ok {
                    player.shuffle = shuffle
                }
            }

            if hide_str, hide_ok := settings_data["hide_alerts"]; hide_ok {
                if hide, parse_ok := strconv.parse_bool(hide_str); parse_ok {
                    hide_alerts = hide
                }
            }

        }

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
    }
}

save_state :: proc() {
    builder := strings.builder_make(context.allocator)
    defer strings.builder_destroy(&builder)

    stream := strings.to_stream(&builder)

    ini.write_section(stream, "settings")
    ini.write_pair(stream, "path", music_dir)
    ini.write_pair(stream, "volume", fmt.aprintf("%.6f", player.volume))
    ini.write_pair(stream, "shuffle", "true" if player.shuffle else "false")
    ini.write_pair(stream, "theme", fmt.aprintf("%d", ui_state.theme))
    ini.write_pair(stream, "hide_alerts", "true" if hide_alerts else "false")

    io.write_string(stream, "\n")

    for song in liked_songs {
        ini.write_section(stream, song.name)
        ini.write_pair(stream, "playlist", song.playlist)
        ini.write_pair(stream, "timestamp", fmt.aprintf("%d", song.timestamp))
        io.write_string(stream, "\n")
    }

    ini_data := strings.to_string(builder)

    write_success := os.write_entire_file(SAVE_FILE, transmute([]u8)ini_data)
    if !write_success {
        fmt.printf("Error writing liked songs to file: %s\n", SAVE_FILE)
    }
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

set_liked_song :: proc(name: string, playlist: string, liked: bool) {
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

    save_state()
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

toggle_song_like :: proc(name: string, playlist: string) {
    current_state := is_song_liked(name, playlist)
    set_liked_song(name, playlist, !current_state)
}