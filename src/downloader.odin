package main

import "fx"
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"

LyricsResponse :: struct {
	id: int `json:"id"`,
	trackName: string `json:"trackName"`,
	artistName: string `json:"artistName"`,
	albumName: string `json:"albumName"`,
	duration: int `json:"duration"`,
	instrumental: bool `json:"instrumental"`,
	plainLyrics: string `json:"plainLyrics"`,
	syncedLyrics: Maybe(string) `json:"syncedLyrics"`,
}

download_lyrics :: proc() {
	track := find_track_by_name(player.current_track.name, player.current_track.playlist)

	title := player.current_track.audio_clip.tags.title
	artist := player.current_track.audio_clip.tags.artist
	album := player.current_track.audio_clip.tags.album
	duration := int(player.duration)

	has_required_metadata := len(title) > 0 && len(artist) > 0 && len(album) > 0 && duration > 0

	if track != nil && has_required_metadata {
		artist_enc := url_encode(artist)
		title_enc := url_encode(title)
		album_enc := url_encode(album)
		duration_mem: [8]u8
		duration_str := strconv.itoa(duration_mem[:], duration)

		url := fmt.tprintf("https://lrclib.net/api/get?artist_name=%s&track_name=%s&album_name=%s&duration=%s",
			artist_enc, title_enc, album_enc, duration_str)

		res := fx.get(url)

		if res.status == 0 {
			show_alert({}, "Connection Error", "Check your internet connection and try again", 2)
			return
		}

		defer delete(res.data)

		if res.status == 200 {
			if lyrics_response, ok := parse_single_lyrics_response(string(res.data)); ok {
				if synced_lyrics, has_lyrics := lyrics_response.syncedLyrics.?; has_lyrics && len(synced_lyrics) > 0 {
					track.lyrics = load_lyrics_from_string(synced_lyrics)
					player.current_track.lyrics = track.lyrics

					save_lyrics_as_lrc(track, synced_lyrics)

					show_alert({}, "Lyrics Found", "Lyrics were successfully retrieved", 2)
					return
				}
			}
		}
	}

	url := fmt.tprintf("https://lrclib.net/api/search?q=%s", url_encode(player.current_track.name))

	res := fx.get(url)

	if res.status == 0 {
		show_alert({}, "Connection Error", "Check your internet connection and try again", 2)
		return
	}

	defer delete(res.data)

	if res.status == 200 {
		if results, ok := parse_search_lyrics_response(string(res.data)); ok && len(results) > 0 {
			current_duration := int(player.duration)
			best_match: ^LyricsResponse = nil
			best_duration_diff := max(int)

			for &result in results {
				if synced_lyrics, has_lyrics := result.syncedLyrics.?; has_lyrics && len(synced_lyrics) > 0 {
					duration_diff := abs(result.duration - current_duration)
					if duration_diff < best_duration_diff {
						best_duration_diff = duration_diff
						best_match = &result
					}
				}
			}

			if best_match != nil {
				if synced_lyrics, has_lyrics := best_match.syncedLyrics.?; has_lyrics {
					if track != nil {
						track.lyrics = load_lyrics_from_string(synced_lyrics)
						player.current_track.lyrics = track.lyrics
						save_lyrics_as_lrc(track, synced_lyrics)
					}

					show_alert({}, "Lyrics Found", "Lyrics were successfully retrieved", 2)
					return
				}
			} else {
				show_alert({}, "No Synced Lyrics Found", "No synced lyrics are available for this song", 2)
				return
			}
		}
	}

	show_alert({}, "No Lyrics Found", "No lyrics are found for this song", 2)
}

parse_single_lyrics_response :: proc(json_data: string) -> (LyricsResponse, bool) {
	response := LyricsResponse{}

	if err := json.unmarshal(transmute([]u8)json_data, &response); err != nil {
		fmt.printf("Error parsing single lyrics response: %v\n", err)
		return {}, false
	}

	return response, true
}

parse_search_lyrics_response :: proc(json_data: string) -> ([]LyricsResponse, bool) {
	results: []LyricsResponse

	if err := json.unmarshal(transmute([]u8)json_data, &results); err != nil {
		fmt.printf("Error parsing search lyrics response: %v\n", err)
		return nil, false
	}

	return results, true
}

url_encode :: proc(s: string) -> string {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	for r in s {
		switch r {
		case ' ':
			strings.write_string(&builder, "%20")
		case '!':
			strings.write_string(&builder, "%21")
		case '"':
			strings.write_string(&builder, "%22")
		case '#':
			strings.write_string(&builder, "%23")
		case '$':
			strings.write_string(&builder, "%24")
		case '%':
			strings.write_string(&builder, "%25")
		case '&':
			strings.write_string(&builder, "%26")
		case '\'':
			strings.write_string(&builder, "%27")
		case '(':
			strings.write_string(&builder, "%28")
		case ')':
			strings.write_string(&builder, "%29")
		case '*':
			strings.write_string(&builder, "%2A")
		case '+':
			strings.write_string(&builder, "%2B")
		case ',':
			strings.write_string(&builder, "%2C")
		case '/':
			strings.write_string(&builder, "%2F")
		case ':':
			strings.write_string(&builder, "%3A")
		case ';':
			strings.write_string(&builder, "%3B")
		case '<':
			strings.write_string(&builder, "%3C")
		case '=':
			strings.write_string(&builder, "%3D")
		case '>':
			strings.write_string(&builder, "%3E")
		case '?':
			strings.write_string(&builder, "%3F")
		case '@':
			strings.write_string(&builder, "%40")
		case '[':
			strings.write_string(&builder, "%5B")
		case '\\':
			strings.write_string(&builder, "%5C")
		case ']':
			strings.write_string(&builder, "%5D")
		case '^':
			strings.write_string(&builder, "%5E")
		case '`':
			strings.write_string(&builder, "%60")
		case '{':
			strings.write_string(&builder, "%7B")
		case '|':
			strings.write_string(&builder, "%7C")
		case '}':
			strings.write_string(&builder, "%7D")
		case '~':
			strings.write_string(&builder, "%7E")
		// Turkish characters
		case 'ç':
			strings.write_string(&builder, "%C3%A7")
		case 'Ç':
			strings.write_string(&builder, "%C3%87")
		case 'ğ':
			strings.write_string(&builder, "%C4%9F")
		case 'Ğ':
			strings.write_string(&builder, "%C4%9E")
		case 'ı':
			strings.write_string(&builder, "%C4%B1")
		case 'İ':
			strings.write_string(&builder, "%C4%B0")
		case 'ö':
			strings.write_string(&builder, "%C3%B6")
		case 'Ö':
			strings.write_string(&builder, "%C3%96")
		case 'ş':
			strings.write_string(&builder, "%C5%9F")
		case 'Ş':
			strings.write_string(&builder, "%C5%9E")
		case 'ü':
			strings.write_string(&builder, "%C3%BC")
		case 'Ü':
			strings.write_string(&builder, "%C3%9C")
		case:
			strings.write_rune(&builder, r)
		}
	}

	return strings.clone(strings.to_string(builder), context.temp_allocator)
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