package main

import "fx"

import "core:os"
import "core:strings"
import "core:strconv"
import "core:slice"

import fp "core:path/filepath"
import "core:unicode/utf8"

load_metadata :: proc(track : ^Track) {
	track.lyrics = load_lyrics_for_track(track.path)

	tags, tags_ok := load_id3_tags(track.path)

	if tags_ok {
		track.tags = tags
		track.has_tags = true
	}
}

load_cover :: proc(track : ^Track) {
	extension := fp.ext(track.path)

	if extension == ".mp3" {
		cover, ok := load_album_art_mp3(track.audio.file_data)
		if ok {
			track.cover = cover
			track.has_cover = true
		}
	} else if extension == ".flac" {
		cover, ok := load_album_art_from_flac(track.audio.file_data)
		if ok {
			track.cover = cover
			track.has_cover = true
		}
	}

	if !track.has_cover {
		stem := fp.stem(track.path)
		dir := fp.dir(track.path)
		path := strings.join({dir, "/", stem, ".qoi"}, "")

		if os.exists(path) {
			cover, ok := fx.load_texture(path)
			if ok {
				track.cover = cover
				track.has_cover = true
			}
		} else {
			delete(path)
			path = strings.join({dir, "/", stem, ".png"}, "")
			if os.exists(path) {
				cover, ok := fx.load_texture(path)
				if ok {
					track.cover = cover
					track.has_cover = true
				}
			} else {
				delete(path)
				path = strings.join({dir, "/", stem, ".jpg"}, "")
				if os.exists(path) {
					cover, ok := fx.load_texture(path)
					if ok {
						track.cover = cover
						track.has_cover = true
					}
				}
			}
		}
	}
}

unload_cover :: proc(track: ^Track) {
	if track.has_cover {
		fx.unload_texture(&track.cover)
	}
}

// Lyrics

parse_lrc_time :: proc(time_str: string) -> (f32, bool) {
	if len(time_str) < 3 || time_str[0] != '[' || time_str[len(time_str) - 1] != ']' {
		return 0, false
	}

	inner := time_str[1:len(time_str) - 1]

	parts := strings.split(inner, ":", context.temp_allocator)
	if len(parts) != 2 {
		return 0, false
	}

	minutes, min_ok := strconv.parse_int(parts[0])
	if !min_ok {
		return 0, false
	}

	seconds_part := parts[1]
	seconds_parts := strings.split(seconds_part, ".", context.temp_allocator)

	seconds: int
	milliseconds: int = 0

	sec_ok: bool
	seconds, sec_ok = strconv.parse_int(seconds_parts[0])
	if !sec_ok {
		return 0, false
	}

	if len(seconds_parts) > 1 {
		ms_str := seconds_parts[1]

		if len(ms_str) == 1 {
			ms_str = strings.concatenate({ms_str, "00"}, context.temp_allocator)
		} else if len(ms_str) == 2 {
			ms_str = strings.concatenate({ms_str, "0"}, context.temp_allocator)
		} else if len(ms_str) > 3 {
			ms_str = ms_str[:3]
		}

		ms_ok: bool
		milliseconds, ms_ok = strconv.parse_int(ms_str)
		if !ms_ok {
			milliseconds = 0
		}
	}

	total_seconds := f32(minutes) * 60.0 + f32(seconds) + f32(milliseconds) / 1000.0
	return total_seconds, true
}

get_lrc_path :: proc(music_path: string) -> string {
	extensions := []string{".mp3", ".wav", ".flac", ".opus", ".ogg"}
	for ext in extensions {
		if strings.ends_with(music_path, ext) {
			new, _ := strings.replace(music_path, ext, ".lrc", 1, context.temp_allocator)
			return new
		}
	}
	return ""
}

load_lyrics_from_string :: proc(lrc_content: string) -> [dynamic]Lyrics {
	lyrics := make([dynamic]Lyrics)

	lines := strings.split_lines(lrc_content, context.temp_allocator)

	for &line in lines {
		line = strings.trim_space(line)
		if len(line) == 0 do continue

		bracket_end := strings.index_byte(line, ']')
		if bracket_end == -1 do continue

		time_tag := line[:bracket_end + 1]
		lyric_text := strings.trim_space(line[bracket_end + 1:])

		time, time_ok := parse_lrc_time(time_tag)
		if !time_ok do continue

		lyric := Lyrics {
			time = time,
			text = lyric_text,
		}
		append(&lyrics, lyric)
	}

	// Just to make sure
	slice.sort_by(lyrics[:], proc(a, b: Lyrics) -> bool {
		return a.time < b.time
	})

	return lyrics
}

load_lyrics_for_track :: proc(music_path: string) -> [dynamic]Lyrics {
	lrc_path := get_lrc_path(music_path)

	lrc_data, read_ok := os.read_entire_file_from_filename(lrc_path, context.temp_allocator)
	if !read_ok {
		return {}
	}

	lrc_content := string(lrc_data)

	return load_lyrics_from_string(lrc_content)
}


// ID3 Tags

ID3_Frame_Header :: struct {
	id:    [4]u8,
	size:  int,
	flags: [2]u8,
}

bytes_to_string :: proc(data: []u8) -> (string, bool) {
	if len(data) == 0 {
		return "", false
	}

	start_pos := 0
	if data[0] == 0x00 || data[0] == 0x01 || data[0] == 0x02 || data[0] == 0x03 {
		start_pos = 1
	}

	end_pos := len(data)
	for i in start_pos ..< len(data) {
		if data[i] == 0 {
			end_pos = i
			break
		}
	}

	if end_pos <= start_pos {
		return "", false
	}

	text_data := data[start_pos:end_pos]
	text_str := string(text_data)

	if !utf8.valid_string(text_str) {
		return "", false
	}

	return strings.clone(text_str), true
}

load_id3_tags :: proc(path: string) -> (tags: Tags, success: bool) {
	buffer := os.read_entire_file_from_filename(path, context.temp_allocator) or_return;

	if !strings.has_prefix(string(buffer[:3]), "ID3") {
		return
	}

	version := buffer[3]
	size :=
		(int(buffer[6]) & 0x7F) << 21 |
		(int(buffer[7]) & 0x7F) << 14 |
		(int(buffer[8]) & 0x7F) << 7 |
		(int(buffer[9]) & 0x7F)

	pos := 10

	if buffer[5] & 0x40 != 0 {
		if pos + 4 > len(buffer) {
			return
		}
		extended_size :=
			int(buffer[pos]) << 24 |
			int(buffer[pos + 1]) << 16 |
			int(buffer[pos + 2]) << 8 |
			int(buffer[pos + 3])
		pos += 4 + extended_size
	}

	for pos < size && pos + 10 < len(buffer) {
		frame: ID3_Frame_Header

		frame.id[0] = buffer[pos + 0]
		frame.id[1] = buffer[pos + 1]
		frame.id[2] = buffer[pos + 2]
		frame.id[3] = buffer[pos + 3]
		frame_id := string(frame.id[:])


		if frame.id[0] == 0 && frame.id[1] == 0 && frame.id[2] == 0 && frame.id[3] == 0 {
			break
		}

		frame.size = 0
		if version >= 4 {

			frame.size =
				(int(buffer[pos + 4]) & 0x7F) << 21 |
				(int(buffer[pos + 5]) & 0x7F) << 14 |
				(int(buffer[pos + 6]) & 0x7F) << 7 |
				(int(buffer[pos + 7]) & 0x7F)
		} else {

			frame.size =
				int(buffer[pos + 4]) << 24 |
				int(buffer[pos + 5]) << 16 |
				int(buffer[pos + 6]) << 8 |
				int(buffer[pos + 7])
		}

		frame.flags[0] = buffer[pos + 8]
		frame.flags[1] = buffer[pos + 9]

		if pos + 10 + frame.size > len(buffer) {
			break
		}

		frame_data := buffer[pos + 10:pos + 10 + frame.size]


		switch frame_id {
		case "TIT2":
			tags.title = bytes_to_string(frame_data) or_return
		case "TPE1":
			tags.artist = bytes_to_string(frame_data) or_return
		case "TALB":
			tags.album = bytes_to_string(frame_data) or_return
		case "TDRC", "TYER":
			tags.year = bytes_to_string(frame_data) or_return
		case "TCON":
			genre_str := bytes_to_string(frame_data) or_return

			if strings.has_prefix(genre_str, "(") && strings.has_suffix(genre_str, ")") {

				tags.genre = genre_str
			} else {
				tags.genre = genre_str
			}
		case "TRCK":
			tags.track = bytes_to_string(frame_data) or_return
		case "COMM":
			if len(frame_data) > 4 {

				comment_start := 4

				for i in comment_start ..< len(frame_data) {
					if frame_data[i] == 0 {
						comment_start = i + 1
						break
					}
				}
				if comment_start < len(frame_data) {
					tags.comment = bytes_to_string(frame_data[comment_start:]) or_return
				}
			}
		case "TPE2":
			tags.album_artist = bytes_to_string(frame_data) or_return
		}

		pos += 10 + frame.size
	}

	has_any_tags :=
		tags.title != "" ||
		tags.artist != "" ||
		tags.album != "" ||
		tags.year != "" ||
		tags.genre != "" ||
		tags.track != "" ||
		tags.comment != "" ||
		tags.album_artist != ""

	return tags, has_any_tags
}


// Album art readers
// TODO: Add ogg cover reader

load_album_art_mp3 :: proc(buffer: []u8) -> (fx.Texture, bool) {
	if !strings.has_prefix(string(buffer[:3]), "ID3") {
		return fx.Texture{}, false
	}

	version := buffer[3]
	size :=
		(int(buffer[6]) & 0x7F) << 21 |
		(int(buffer[7]) & 0x7F) << 14 |
		(int(buffer[8]) & 0x7F) << 7 |
		(int(buffer[9]) & 0x7F)

	pos := 10
	for pos < size {
		if pos + 10 > len(buffer) {
			break
		}

		frame: ID3_Frame_Header

		frame.id[0] = buffer[pos + 0]
		frame.id[1] = buffer[pos + 1]
		frame.id[2] = buffer[pos + 2]
		frame.id[3] = buffer[pos + 3]
		frame_id := string(frame.id[:])

		frame.size = 0
		if version >= 4 {
			frame.size =
				(int(buffer[pos + 4]) & 0x7F) << 21 |
				(int(buffer[pos + 5]) & 0x7F) << 14 |
				(int(buffer[pos + 6]) & 0x7F) << 7 |
				(int(buffer[pos + 7]) & 0x7F)
		} else {
			frame.size =
				int(buffer[pos + 4]) << 24 |
				int(buffer[pos + 5]) << 16 |
				int(buffer[pos + 6]) << 8 |
				int(buffer[pos + 7])
		}

		frame.flags[0] = buffer[pos + 8]
		frame.flags[1] = buffer[pos + 9]

		if frame_id == "APIC" {
			data_pos := pos + 10

			data_pos += 1

			for buffer[data_pos] != 0 {
				data_pos += 1
			}
			data_pos += 1
			data_pos += 1

			for buffer[data_pos] != 0 {
				data_pos += 1
			}

			data_pos += 1

			image_data := buffer[data_pos:pos + 10 + frame.size]

			image := fx.load_texture_from_bytes(image_data)
			if image.width > 0 {
				return image, true
			} else {
				return fx.Texture{}, false
			}
		}

		pos += 10 + frame.size
	}

	return fx.Texture{}, false
}

FLAC_Metadata_Block_Header :: struct {
	is_last: bool,
	type:    u8,
	length:  int,
}

load_album_art_from_flac :: proc(buffer: []u8) -> (fx.Texture, bool) {
	if !strings.has_prefix(string(buffer[:4]), "fLaC") {
		return fx.Texture{}, false
	}

	pos := 4
	for pos + 4 <= len(buffer) {
		header_byte := buffer[pos]
		block: FLAC_Metadata_Block_Header
		block.is_last = (header_byte & 0x80) != 0
		block.type = header_byte & 0x7F
		block.length =
			int(buffer[pos + 1]) << 16 | int(buffer[pos + 2]) << 8 | int(buffer[pos + 3])

		pos += 4

		if pos + block.length > len(buffer) {
			break
		}

		if block.type == 6 {
			data := buffer[pos:pos + block.length]
			cursor := 0

			cursor += 4

			mime_length :=
				int(data[cursor]) << 24 |
				int(data[cursor + 1]) << 16 |
				int(data[cursor + 2]) << 8 |
				int(data[cursor + 3])
			cursor += 4

			cursor += mime_length

			desc_length :=
				int(data[cursor]) << 24 |
				int(data[cursor + 1]) << 16 |
				int(data[cursor + 2]) << 8 |
				int(data[cursor + 3])
			cursor += 4

			cursor += desc_length

			cursor += 4 * 4

			pic_data_length :=
				int(data[cursor]) << 24 |
				int(data[cursor + 1]) << 16 |
				int(data[cursor + 2]) << 8 |
				int(data[cursor + 3])
			cursor += 4

			if cursor + pic_data_length > len(data) {
				break
			}

			image_data := data[cursor:cursor + pic_data_length]

			image := fx.load_texture_from_bytes(image_data)
			if image.width > 0 {
				return image, true
			} else {
				return fx.Texture{}, false
			}
		}

		pos += block.length

		if block.is_last {
			break
		}
	}

	return fx.Texture{}, false
}


