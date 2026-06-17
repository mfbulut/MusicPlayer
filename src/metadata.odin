package main

import "fx"

import "core:c"
import "core:os"
import "core:strings"
import "core:strconv"
import "core:slice"
import "core:encoding/base64"
import "core:encoding/endian"

import "core:unicode/utf8"
import "core:unicode/utf16"

load_small_cover :: proc(track : ^Track, buffer : []u8) {
	extension := os.ext(track.path)

	if extension == ".mp3" {
		cover, ok := load_album_art_mp3(buffer, true)
		if ok {
			track.small_cover = cover
			track.thumbnail_loaded = true
		}
	} else if extension == ".flac" {
		cover, ok := load_album_art_from_flac(buffer, true)
		if ok {
			track.small_cover = cover
			track.thumbnail_loaded = true
		}
	} else if extension == ".opus" || extension == ".ogg" {
		cover, ok := load_album_art_from_ogg(track.path, extension, true)
		if ok {
			track.small_cover = cover
			track.thumbnail_loaded = true
		}
	}
}

load_cover :: proc(track : ^Track, buffer : []u8) {
	extension := os.ext(track.path)

	if extension == ".mp3" {
		cover, ok := load_album_art_mp3(buffer)
		if ok {
			track.cover = cover
			track.has_cover = true
		}
	} else if extension == ".flac" {
		cover, ok := load_album_art_from_flac(buffer)
		if ok {
			track.cover = cover
			track.has_cover = true
		}
	} else if extension == ".opus" || extension == ".ogg" {
		cover, ok := load_album_art_from_ogg(track.path, extension)
		if ok {
			track.cover = cover
			track.has_cover = true
		}
	}
}

unload_cover :: proc(track: ^Track) {
	if track.has_cover {
		fx.unload_texture(&track.cover)
	}

	track.has_cover = false
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

	lrc_data, err:= os.read_entire_file(lrc_path, context.temp_allocator)

	if err != nil {
		return {}
	}

	lrc_content := string(lrc_data)

	return load_lyrics_from_string(lrc_content)
}

// ID3 Tags

read_u32_be :: #force_inline proc(data: []u8) -> int {
	v, _ := endian.get_u32(data, .Big)
	return int(v)
}

read_u32_le :: #force_inline proc(data: []u8) -> int {
	v, _ := endian.get_u32(data, .Little)
	return int(v)
}

read_id3_syncsafe_size :: #force_inline proc(data: []u8) -> int {
	return (int(data[0]) & 0x7F) << 21 | (int(data[1]) & 0x7F) << 14 | (int(data[2]) & 0x7F) << 7 | (int(data[3]) & 0x7F)
}

decode_id3_string :: proc(data: []u8) -> (string, bool) {
	if len(data) == 0 do return "", false

	encoding := data[0]
	str_data := data[1:]

	if len(str_data) == 0 do return "", false

	switch encoding {
	case 0: // ISO-8859-1 (Latin-1)
		length := 0
		for i in 0..<len(str_data) {
			if str_data[i] == 0 {
				length = i
				break
			}
			length = i + 1
		}
		if length == 0 do return "", false

		utf8_buf := make([]u8, length * 2, context.temp_allocator)
		utf8_len := 0
		for i in 0..<length {
			c := str_data[i]
			if c < 0x80 {
				utf8_buf[utf8_len] = c
				utf8_len += 1
			} else {
				utf8_buf[utf8_len] = 0xC0 | (c >> 6)
				utf8_len += 1
				utf8_buf[utf8_len] = 0x80 | (c & 0x3F)
				utf8_len += 1
			}
		}
		return strings.clone(string(utf8_buf[:utf8_len])), true

	case 1, 2: // UTF-16 with BOM or UTF-16BE
		length := 0
		for i := 0; i < len(str_data) - 1; i += 2 {
			if str_data[i] == 0 && str_data[i+1] == 0 {
				length = i
				break
			}
			length = i + 2
		}
		if length == 0 do return "", false

		is_be := encoding == 2
		start_idx := 0

		if encoding == 1 && length >= 2 {
			if str_data[0] == 0xFE && str_data[1] == 0xFF {
				is_be = true
				start_idx = 2
			} else if str_data[0] == 0xFF && str_data[1] == 0xFE {
				is_be = false
				start_idx = 2
			}
		}

		u16_len := (length - start_idx) / 2
		u16_data := make([]u16, u16_len, context.temp_allocator)
		for i in 0..<u16_len {
			if is_be {
				u16_data[i] = u16(str_data[start_idx + i*2]) << 8 | u16(str_data[start_idx + i*2 + 1])
			} else {
				u16_data[i] = u16(str_data[start_idx + i*2]) | u16(str_data[start_idx + i*2 + 1]) << 8
			}
		}

		runes_count := utf16.rune_count(u16_data)
		runes := make([]rune, runes_count, context.temp_allocator)
		utf16.decode(runes, u16_data)

		utf8_str, err := utf8.runes_to_string(runes, context.temp_allocator)
		if err != nil do return "", false
		return strings.clone(utf8_str), true

	case 3: // UTF-8
		length := 0
		for i in 0..<len(str_data) {
			if str_data[i] == 0 {
				length = i
				break
			}
			length = i + 1
		}
		if length == 0 do return "", false

		s := string(str_data[:length])
		if !utf8.valid_string(s) do return "", false
		return strings.clone(s), true

	case:
		return "", false
	}
}

load_id3_tags :: proc(filepath: string) -> (tags: Tags, success: bool) {
	file, err := os.open(filepath)
	if err != os.ERROR_NONE {
		return
	}
	defer os.close(file)

	header_buffer : [10]u8

	bytes_read, read_err := os.read(file, header_buffer[:10])
	if read_err != os.ERROR_NONE || bytes_read < 10 {
		return
	}

	if !strings.has_prefix(string(header_buffer[:3]), "ID3") {
		return
	}

	version := header_buffer[3]

	size := read_id3_syncsafe_size(header_buffer[6:10])

	pos := 10

	if header_buffer[5] & 0x40 != 0 {
		ext_header_size_buf : [4]u8

		bytes_read, read_err = os.read(file, ext_header_size_buf[:4])
		if read_err != os.ERROR_NONE || bytes_read < 4 {
			return
		}

		extended_size := read_u32_be(ext_header_size_buf[:4])

		os.seek(file, i64(extended_size), .Current)
		pos += 4 + extended_size
	}

	frame_header_buf : [10]u8

	for pos < size {
		bytes_read, read_err = os.read(file, frame_header_buf[:10])
		if read_err != nil || bytes_read < 10 {
			break
		}

		frame_id_bytes := frame_header_buf[0:4]
		frame_id := string(frame_id_bytes)

		if frame_id_bytes[0] == 0 && frame_id_bytes[1] == 0 && frame_id_bytes[2] == 0 && frame_id_bytes[3] == 0 {
			break
		}

		frame_size := 0
		if version >= 4 {
			frame_size = read_id3_syncsafe_size(frame_header_buf[4:8])
		} else {
			frame_size = read_u32_be(frame_header_buf[4:8])
		}

		switch frame_id {
		case "TIT2", "TPE1", "TALB", "TDRC", "TYER", "TCON", "TRCK", "COMM", "TPE2":
			frame_data := make([]u8, frame_size)
			defer delete(frame_data)

			bytes_read, read_err = os.read(file, frame_data)
			if read_err != os.ERROR_NONE || bytes_read < frame_size {
				break
			}

			switch frame_id {
			case "TIT2":
				tags.title = decode_id3_string(frame_data) or_return
			case "TPE1":
				tags.artist = decode_id3_string(frame_data) or_return
			case "TALB":
				tags.album = decode_id3_string(frame_data) or_return
			case "TDRC", "TYER":
				tags.year = decode_id3_string(frame_data) or_return
			case "TCON":
				genre_str := decode_id3_string(frame_data) or_return
				tags.genre = genre_str
			case "TRCK":
				tags.track = decode_id3_string(frame_data) or_return
			case "COMM":
				if len(frame_data) > 4 {
					// Comments typically have: [Encoding byte] + [3-byte language code] + [Short description] + [null] + [actual text]
					// This simple approach skips to actual text for standard cases.
					encoding := frame_data[0]

					comment_start := 4
					if encoding == 1 || encoding == 2 {
						// UTF-16, find double null
						for i := 4; i < len(frame_data) - 1; i += 2 {
							if frame_data[i] == 0 && frame_data[i+1] == 0 {
								comment_start = i + 2
								break
							}
						}
					} else {
						// Latin-1 or UTF-8, find single null
						for i in 4 ..< len(frame_data) {
							if frame_data[i] == 0 {
								comment_start = i + 1
								break
							}
						}
					}

					if comment_start < len(frame_data) {
						// Re-attach encoding byte to the actual text payload
						actual_text_data := make([]u8, len(frame_data) - comment_start + 1, context.temp_allocator)
						actual_text_data[0] = encoding
						copy(actual_text_data[1:], frame_data[comment_start:])

						tags.comment = decode_id3_string(actual_text_data) or_return
					}
				}
			case "TPE2":
				tags.album_artist = decode_id3_string(frame_data) or_return
			}
		case:
			os.seek(file, i64(frame_size), .Current)
		}

		pos += 10 + frame_size
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

load_album_art_mp3 :: proc(buffer: []u8, downsample := false) -> (fx.Texture, bool) {
	if !strings.has_prefix(string(buffer[:3]), "ID3") {
		return fx.Texture{}, false
	}

	version := buffer[3]
	size := read_id3_syncsafe_size(buffer[6:10])

	pos := 10
	for pos < size {
		if pos + 10 > len(buffer) {
			break
		}

		frame_id_bytes := buffer[pos:pos+4]
		frame_id := string(frame_id_bytes)

		frame_size := 0
		if version >= 4 {
			frame_size = read_id3_syncsafe_size(buffer[pos+4:pos+8])
		} else {
			frame_size = read_u32_be(buffer[pos+4:pos+8])
		}

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

			image_data := buffer[data_pos:pos + 10 + frame_size]

			image := fx.load_texture_from_bytes(image_data, !downsample, downsample)
			if image.width > 0 {
				return image, true
			} else {
				return fx.Texture{}, false
			}
		}

		pos += 10 + frame_size
	}

	return fx.Texture{}, false
}


load_flac_vorbis_comment_tags :: proc(filepath: string) -> (tags: Tags, success: bool) {
	buffer, err := os.read_entire_file(filepath, context.temp_allocator)
	if err != nil {
		return
	}

	if len(buffer) < 4 || !strings.has_prefix(string(buffer[:4]), "fLaC") {
		return
	}

	pos := 4
	for pos + 4 <= len(buffer) {
		header_byte := buffer[pos]
		is_last := (header_byte & 0x80) != 0
		block_type := header_byte & 0x7F
		block_length := int(buffer[pos + 1]) << 16 | int(buffer[pos + 2]) << 8 | int(buffer[pos + 3])
		pos += 4

		if pos + block_length > len(buffer) {
			break
		}

		// Type 4 = VORBIS_COMMENT
		if block_type == 4 {
			data := buffer[pos:pos + block_length]
			tags = parse_vorbis_comment_block(data)
			has_any := tags.title != "" || tags.artist != "" || tags.album != "" ||
				tags.year != "" || tags.genre != "" || tags.track != "" ||
				tags.comment != "" || tags.album_artist != ""
			return tags, has_any
		}

		pos += block_length
		if is_last do break
	}

	return
}

// Parse a raw Vorbis Comment block (as found in FLAC metadata block type 4)
parse_vorbis_comment_block :: proc(data: []u8) -> (tags: Tags) {
	if len(data) < 4 do return

	cursor := 0

	// Vendor string length (little-endian u32)
	vendor_len := read_u32_le(data[cursor:cursor+4])
	cursor += 4
	if cursor + vendor_len > len(data) do return
	cursor += vendor_len

	// Comment count
	if cursor + 4 > len(data) do return
	comment_count := read_u32_le(data[cursor:cursor+4])
	cursor += 4

	for _ in 0..<comment_count {
		if cursor + 4 > len(data) do break
		comment_len := read_u32_le(data[cursor:cursor+4])
		cursor += 4
		if cursor + comment_len > len(data) do break

		comment_str := string(data[cursor:cursor + comment_len])
		cursor += comment_len

		if !utf8.valid_string(comment_str) do continue

		eq_idx := strings.index_byte(comment_str, '=')
		if eq_idx < 0 do continue

		key := strings.to_upper(comment_str[:eq_idx], context.temp_allocator)
		value := comment_str[eq_idx + 1:]

		switch key {
		case "TITLE":       tags.title = strings.clone(value)
		case "ARTIST":      tags.artist = strings.clone(value)
		case "ALBUM":       tags.album = strings.clone(value)
		case "DATE":        tags.year = strings.clone(value)
		case "GENRE":       tags.genre = strings.clone(value)
		case "TRACKNUMBER": tags.track = strings.clone(value)
		case "COMMENT":     tags.comment = strings.clone(value)
		case "ALBUMARTIST": tags.album_artist = strings.clone(value)
		}
	}

	return
}

load_opus_tags :: proc(filepath: string) -> (tags: Tags, success: bool) {
	cpath := strings.clone_to_cstring(filepath, context.temp_allocator)
	err: c.int
	of := fx.op_open_file(cpath, &err)
	if of == nil do return
	defer fx.op_free(of)

	opus_tags := fx.op_tags(of, -1)
	if opus_tags == nil do return

	query_opus_tag :: proc(opus_tags: ^fx.OpusTags, key: cstring) -> string {
		val := fx.opus_tags_query(opus_tags, key, 0)
		if val == nil do return ""
		s := string(val)
		if !utf8.valid_string(s) do return ""
		return strings.clone(s)
	}

	tags.title        = query_opus_tag(opus_tags, "TITLE")
	tags.artist       = query_opus_tag(opus_tags, "ARTIST")
	tags.album        = query_opus_tag(opus_tags, "ALBUM")
	tags.year         = query_opus_tag(opus_tags, "DATE")
	tags.genre        = query_opus_tag(opus_tags, "GENRE")
	tags.track        = query_opus_tag(opus_tags, "TRACKNUMBER")
	tags.comment      = query_opus_tag(opus_tags, "COMMENT")
	tags.album_artist = query_opus_tag(opus_tags, "ALBUMARTIST")

	has_any := tags.title != "" || tags.artist != "" || tags.album != "" ||
		tags.year != "" || tags.genre != "" || tags.track != "" ||
		tags.comment != "" || tags.album_artist != ""

	return tags, has_any
}

load_ogg_vorbis_tags :: proc(filepath: string) -> (tags: Tags, success: bool) {
	cpath := strings.clone_to_cstring(filepath, context.temp_allocator)
	vf := new(fx.OggVorbis_File)
	if vf == nil do return
	if fx.ov_fopen(cpath, vf) < 0 {
		free(vf)
		return
	}
	defer {
		fx.ov_clear(vf)
		free(vf)
	}

	vc := fx.ov_comment(vf, -1)
	if vc == nil do return

	query_vorbis_tag :: proc(vc: ^fx.VorbisComment, key: cstring) -> string {
		val := fx.vorbis_comment_query(vc, key, 0)
		if val == nil do return ""
		s := string(val)
		if !utf8.valid_string(s) do return ""
		return strings.clone(s)
	}

	tags.title        = query_vorbis_tag(vc, "TITLE")
	tags.artist       = query_vorbis_tag(vc, "ARTIST")
	tags.album        = query_vorbis_tag(vc, "ALBUM")
	tags.year         = query_vorbis_tag(vc, "DATE")
	tags.genre        = query_vorbis_tag(vc, "GENRE")
	tags.track        = query_vorbis_tag(vc, "TRACKNUMBER")
	tags.comment      = query_vorbis_tag(vc, "COMMENT")
	tags.album_artist = query_vorbis_tag(vc, "ALBUMARTIST")

	has_any := tags.title != "" || tags.artist != "" || tags.album != "" ||
		tags.year != "" || tags.genre != "" || tags.track != "" ||
		tags.comment != "" || tags.album_artist != ""

	return tags, has_any
}

load_album_art_from_ogg :: proc(filepath: string, extension: string, downsample := false) -> (fx.Texture, bool) {
	if extension == ".opus" {
		return load_album_art_from_opus(filepath, downsample)
	} else if extension == ".ogg" {
		return load_album_art_from_ogg_vorbis(filepath, downsample)
	}
	return fx.Texture{}, false
}

load_album_art_from_opus :: proc(filepath: string, downsample := false) -> (fx.Texture, bool) {
	cpath := strings.clone_to_cstring(filepath, context.temp_allocator)
	err: c.int
	of := fx.op_open_file(cpath, &err)
	if of == nil do return fx.Texture{}, false
	defer fx.op_free(of)

	opus_tags := fx.op_tags(of, -1)
	if opus_tags == nil do return fx.Texture{}, false

	prefix :: "METADATA_BLOCK_PICTURE="

	for i in 0..<int(opus_tags.comments) {
		comment := string(opus_tags.user_comments[i])

		if len(comment) <= len(prefix) do continue

		comment_upper := strings.to_upper(comment[:len(prefix)], context.temp_allocator)
		if comment_upper != prefix do continue

		b64_data := comment[len(prefix):]

		decoded, decode_err := base64.decode(b64_data, allocator = context.temp_allocator)
		if decode_err != nil do continue
		if len(decoded) < 32 do continue

		image_data, pic_ok := parse_flac_picture_block(decoded)
		if !pic_ok do continue

		image := fx.load_texture_from_bytes(image_data, !downsample, downsample)
		if image.width > 0 {
			return image, true
		}
	}

	return fx.Texture{}, false
}

load_album_art_from_ogg_vorbis :: proc(filepath: string, downsample := false) -> (fx.Texture, bool) {
	cpath := strings.clone_to_cstring(filepath, context.temp_allocator)

	vf := new(fx.OggVorbis_File)
	defer free(vf)
	if fx.ov_fopen(cpath, vf) < 0 {
		return fx.Texture{}, false
	}
	defer fx.ov_clear(vf)

	vc := fx.ov_comment(vf, -1)
	if vc == nil do return fx.Texture{}, false

	prefix :: "METADATA_BLOCK_PICTURE="

	for i in 0..<int(vc.comments) {
		comment := string(vc.user_comments[i])

		if len(comment) <= len(prefix) do continue

		comment_upper := strings.to_upper(comment[:len(prefix)], context.temp_allocator)
		if comment_upper != prefix do continue

		b64_data := comment[len(prefix):]

		decoded, decode_err := base64.decode(b64_data, allocator = context.temp_allocator)
		if decode_err != nil do continue
		if len(decoded) < 32 do continue

		image_data, pic_ok := parse_flac_picture_block(decoded)
		if !pic_ok do continue

		image := fx.load_texture_from_bytes(image_data, !downsample, downsample)
		if image.width > 0 {
			return image, true
		}
	}

	return fx.Texture{}, false
}

parse_flac_picture_block :: proc(data: []u8) -> ([]u8, bool) {
	if len(data) < 8 do return nil, false

	cursor := 0
	cursor += 4

	if cursor + 4 > len(data) do return nil, false
	mime_len := read_u32_be(data[cursor:cursor+4])
	cursor += 4
	if cursor + mime_len > len(data) do return nil, false
	cursor += mime_len

	if cursor + 4 > len(data) do return nil, false
	desc_len := read_u32_be(data[cursor:cursor+4])
	cursor += 4
	if cursor + desc_len > len(data) do return nil, false
	cursor += desc_len

	if cursor + 16 > len(data) do return nil, false
	cursor += 16

	if cursor + 4 > len(data) do return nil, false
	pic_data_len := read_u32_be(data[cursor:cursor+4])
	cursor += 4

	if cursor + pic_data_len > len(data) do return nil, false

	return data[cursor:cursor + pic_data_len], true
}

load_album_art_from_flac :: proc(buffer: []u8, downsample := false) -> (fx.Texture, bool) {
	if !strings.has_prefix(string(buffer[:4]), "fLaC") {
		return fx.Texture{}, false
	}

	pos := 4
	for pos + 4 <= len(buffer) {
		header_byte := buffer[pos]
		block_is_last := (header_byte & 0x80) != 0
		block_type := header_byte & 0x7F
		block_length := int(buffer[pos + 1]) << 16 | int(buffer[pos + 2]) << 8 | int(buffer[pos + 3])

		pos += 4

		if pos + block_length > len(buffer) {
			break
		}

		if block_type == 6 {
			data := buffer[pos:pos + block_length]
			cursor := 0

			cursor += 4

			mime_length := read_u32_be(data[cursor:cursor+4])
			cursor += 4

			cursor += mime_length

			desc_length := read_u32_be(data[cursor:cursor+4])
			cursor += 4

			cursor += desc_length

			cursor += 4 * 4

			pic_data_length := read_u32_be(data[cursor:cursor+4])
			cursor += 4

			if cursor + pic_data_length > len(data) {
				break
			}

			image_data := data[cursor:cursor + pic_data_length]

			image := fx.load_texture_from_bytes(image_data, !downsample, downsample)
			if image.width > 0 {
				return image, true
			} else {
				return fx.Texture{}, false
			}
		}

		pos += block_length

		if block_is_last {
			break
		}
	}

	return fx.Texture{}, false
}