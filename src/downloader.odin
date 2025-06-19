package main

import "fx"

import "core:os"
import "core:strings"
import "core:strconv"
import "core:path/filepath"

download_lyrics :: proc() {
    track := find_track_by_name(player.current_track.name, player.current_track.playlist)

    if track != nil && player.current_track.audio_clip.has_tags {
        title  := player.current_track.audio_clip.tags.title
        artist := player.current_track.audio_clip.tags.artist
        album  := player.current_track.audio_clip.tags.album
        duration := int(player.duration)

        url_builder := strings.builder_make()
        defer strings.builder_destroy(&url_builder)

        strings.write_string(&url_builder, "https://lrclib.net/api/get?artist_name=")
        strings.write_string(&url_builder, url_encode(artist))
        strings.write_string(&url_builder, "&track_name=")
        strings.write_string(&url_builder, url_encode(title))
        strings.write_string(&url_builder, "&album_name=")
        strings.write_string(&url_builder, url_encode(album))
        strings.write_string(&url_builder, "&duration=")
        duration_mem : [8]u8
        duration_str := strconv.itoa(duration_mem[:], duration)
        strings.write_string(&url_builder, duration_str)

        api_url := strings.to_string(url_builder)
        res := fx.get(api_url)
        
        defer delete(res.data)

        if res.status == 200 {
            synced_lyrics := extract_synced_lyrics(string(res.data))

            if len(synced_lyrics) > 0 {
                track.lyrics = load_lyrics_from_string(synced_lyrics)
                player.current_track.lyrics = track.lyrics

                save_lyrics_as_lrc(track, synced_lyrics)

                show_alert({}, "Lyrics Found", "Lyrics were successfully retrieved", 2)
            } else {
                show_alert({}, "No Synced Lyrics Found", "No synced lyrics are available for this song", 2)
            }

        } else {
            show_alert({}, "Lyrics Unavailable", "Could not retrieve lyrics for this song", 2)
        }
    } else {
        show_alert({}, "Missing Metadata", "Metadata is required to find lyrics", 2)
    }
}

url_encode :: proc(s: string) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    for r in s {
        switch r {
        case ' ':
            strings.write_string(&builder, "%20")
        case '&':
            strings.write_string(&builder, "%26")
        case '=':
            strings.write_string(&builder, "%3D")
        case '?':
            strings.write_string(&builder, "%3F")
        case '#':
            strings.write_string(&builder, "%23")
        case '+':
            strings.write_string(&builder, "%2B")
        case:
            strings.write_rune(&builder, r)
        }
    }

    return strings.clone(strings.to_string(builder), context.temp_allocator)
}

extract_synced_lyrics :: proc(json_body: string) -> string {
    synced_key := "\"syncedLyrics\":"
    start_pos := strings.index(json_body, synced_key)
    if start_pos == -1 {
        return ""
    }

    start_pos += len(synced_key)

    for start_pos < len(json_body) && (json_body[start_pos] == ' ' || json_body[start_pos] == '\t') {
        start_pos += 1
    }

    if start_pos >= len(json_body) || json_body[start_pos] != '"' {
        return ""
    }

    start_pos += 1

    end_pos := start_pos
    for end_pos < len(json_body) {
        if json_body[end_pos] == '"' {

            escape_count := 0
            check_pos := end_pos - 1
            for check_pos >= start_pos && json_body[check_pos] == '\\' {
                escape_count += 1
                check_pos -= 1
            }

            if escape_count % 2 == 0 {
                break
            }
        }
        end_pos += 1
    }

    if end_pos >= len(json_body) {
        return ""
    }

    raw_lyrics := json_body[start_pos:end_pos]

    unescaped, _ := strings.replace_all(raw_lyrics, "\\n", "\n", context.temp_allocator)
    unescaped, _ = strings.replace_all(unescaped, "\\\"", "\"", context.temp_allocator)
    unescaped, _ = strings.replace_all(unescaped, "\\\\", "\\", context.temp_allocator)

    return strings.clone(unescaped, context.temp_allocator)
}

save_lyrics_as_lrc :: proc(track: ^Track, lyrics_content: string) {
    if len(lyrics_content) == 0 {
        return
    }

    dir := filepath.dir(track.path, context.temp_allocator)

    base_name := filepath.stem(track.path)

    lrc_filename := strings.concatenate({base_name, ".lrc"}, context.temp_allocator)
    lrc_path := filepath.join({dir, lrc_filename}, context.temp_allocator)

    success := os.write_entire_file(lrc_path, transmute([]u8)lyrics_content)
}