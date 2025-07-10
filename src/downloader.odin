package main

import "fx"

import sa "core:container/small_array"
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

// Special casing for file naming formats like:
// > "00 - Artist - Title"
// > "00 - Title"
// > "Artist - Title"
// > "Title"
// See: https://lrclib.net/docs.
guess_search_opts :: proc(title: string) -> (opts: [2]fx.Request_Query_Param, opts_count: int) {
	// Literally every dash I can find; https://www.compart.com/en/unicode/category/Pd.
	DASHES :: [?]rune {
		'-',
		0x1806,
		0x2010,
		0x2011,
		0x2012,
		0x2013,
		0x2014,
		0xFE58,
		0xFE63,
		0xFF0D,
		0x002D,
	}

	attempt: for v in DASHES {
		title := title
		pieces: sa.Small_Array(2, string)

		for title != "" {
			off := strings.index_rune(title, v)
			piece: string

			if off < 0 {
				piece = title
				title = title[len(title):]
			} else {
				piece = title[:off]
				title = title[off + utf8.rune_size(v):]
			}

			piece = strings.trim_space(piece)

			// Filter pieces that are all unsigned ints.
			// We'll assume they're track numbers, which aren't used for searches.
			if _, is_uint := strconv.parse_uint(piece); !is_uint {
				sa.append(&pieces, piece) or_break
			}
		}

		switch sa.len(pieces) {
		case 0:
			continue attempt
		case 1:
			opts[0] = {"track_name", sa.get(pieces, 0)}
			return opts, 1
		case:
			opts[0] = {"artist_name", sa.get(pieces, 0)}
			opts[1] = {"track_name", sa.get(pieces, 1)}
			return opts, 2
		}
	}

	opts[0] = {"track_name", title}
	return opts, 1
}

download_lyrics :: proc() {
	if player.current_track.path == "" {
		show_alert({}, "No track is playing", "Open a track before downloading lyrics", 2)
		return
	}

	track := find_track_by_name(player.current_track.name, player.current_track.playlist)

	title := player.current_track.tags.title
	artist := player.current_track.tags.artist
	album := player.current_track.tags.album
	duration := int(player.duration)

	has_required_metadata := len(title) > 0 && len(artist) > 0 && len(album) > 0 && duration > 0

	if track != nil && has_required_metadata {
		duration_mem: [8]u8

		res, ok := fx.get(
			"https://lrclib.net/api/get",
			{
				{"title", player.current_track.tags.title},
				{"artist_name", player.current_track.tags.artist},
				{"album", player.current_track.tags.album},
				{"duration", strconv.itoa(duration_mem[:], duration)},
			},
		)

		if !ok {
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

	opts, opts_count := guess_search_opts(player.current_track.name)
	res, ok := fx.get("https://lrclib.net/api/search", opts[:opts_count])


	if !ok {
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

			if best_duration_diff > 5 {
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
