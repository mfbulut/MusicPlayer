package main

import "fx"

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"

LyricsResponse :: struct {
	id:           int `json:"id"`,
	trackName:    string `json:"trackName"`,
	artistName:   string `json:"artistName"`,
	albumName:    string `json:"albumName"`,
	duration:     f32 `json:"duration"`,
	instrumental: bool `json:"instrumental"`,
	plainLyrics:  string `json:"plainLyrics"`,
	syncedLyrics: Maybe(string) `json:"syncedLyrics"`,
}

download_lyrics :: proc() {
	if player.current_track.path == "" {
		show_alert({}, "No track is playing", "Open a track before downloading lyrics", 2)
		return
	}

	track := find_track_by_name(player.current_track.name, player.current_track.playlist)

	title := player.current_track.audio_clip.tags.title
	artist := player.current_track.audio_clip.tags.artist
	album := player.current_track.audio_clip.tags.album
	duration := int(player.duration)

	has_required_metadata := len(title) > 0 && len(artist) > 0 && len(album) > 0 && duration > 0

	if track != nil && has_required_metadata {
		duration_mem: [8]u8
		duration_str := strconv.itoa(duration_mem[:], duration)

		res := fx.get(
			"https://lrclib.net/api/get",
			{
				{"title", player.current_track.audio_clip.tags.title},
				{"artist_name", player.current_track.audio_clip.tags.artist},
				{"album", player.current_track.audio_clip.tags.album},
				{"duration", strconv.itoa(duration_mem[:], duration)},
			},
		)

		if res.status == 0 {
			show_alert({}, "Network Error", "Check your internet connection and try again", 2)
			return
		}

		defer delete(res.data)

		if res.status == 200 {
			if lyrics_response, ok := parse_single_lyrics_response(string(res.data)); ok {
				if synced_lyrics, has_lyrics := lyrics_response.syncedLyrics.?;
				   has_lyrics && len(synced_lyrics) > 0 {
					track.lyrics = load_lyrics_from_string(synced_lyrics)
					player.current_track.lyrics = track.lyrics

					save_lyrics_as_lrc(track, synced_lyrics)

					show_alert({}, "Lyrics Found", "Lyrics were successfully retrieved", 2)
					return
				}
			}
		}
	}

	res := fx.get("https://lrclib.net/api/search", {{"q", player.current_track.name}})


	if res.status == 0 {
		show_alert({}, "Network Error", "Check your internet connection and try again", 2)
		return
	}

	defer delete(res.data)

	if res.status == 200 {
		if results, ok := parse_search_lyrics_response(string(res.data)); ok && len(results) > 0 {
			current_duration := int(player.duration)
			best_match: ^LyricsResponse = nil
			best_duration_diff := max(int)

			for &result in results {
				if synced_lyrics, has_lyrics := result.syncedLyrics.?;
				   has_lyrics && len(synced_lyrics) > 0 {
					duration_diff := abs(int(result.duration) - current_duration)
					if duration_diff < best_duration_diff {
						best_duration_diff = duration_diff
						best_match = &result
					}
				}
			}

			if best_duration_diff > 10 {
				show_alert({}, "No Lyrics Found", "No lyrics are found for this song", 2)
				return
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
				show_alert(
					{},
					"No Synced Lyrics Available",
					"No synced lyrics are available for this song",
					2,
				)
				return
			}
		}
	}

	show_alert({}, "Lyrics Unavailable", "No lyrics are found for this song", 2)
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

save_lyrics_as_lrc :: proc(track: ^Track, lyrics_content: string) {
	if len(lyrics_content) == 0 {
		return
	}

	dir := filepath.dir(track.path, context.temp_allocator)
	base_name := filepath.stem(track.path)
	lrc_filename := strings.concatenate({base_name, ".lrc"}, context.temp_allocator)
	lrc_path := filepath.join({dir, lrc_filename}, context.temp_allocator)

	os.write_entire_file(lrc_path, transmute([]u8)lyrics_content)
}
