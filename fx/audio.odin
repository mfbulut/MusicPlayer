package fx

import "vendor:miniaudio"

import "core:fmt"
import "core:os"
import "core:strings"
import fp "core:path/filepath"

Audio :: struct {
    duration: f32,
    sound: ^miniaudio.sound,
    decoder: ^miniaudio.decoder,
    file_data: []byte,
    cover: Texture,
    loaded: bool,
    has_cover: bool,

    total_frames: u64,
    sample_rate: u32,
}

@(private)
audio_engine: miniaudio.engine


when OPUS_SUPPORT {
    pCustomBackendVTables : [1][^]miniaudio.decoding_backend_vtable

    opus_decoder := miniaudio.decoding_backend_vtable {
    	onInit = ma_decoding_backend_init__libopus,
    	onInitFile = ma_decoding_backend_init_file__libopus,
    	onInitFileW = nil,
    	onInitMemory = nil,
    	onUninit = ma_decoding_backend_uninit__libopus
    }
}

init_audio :: proc() -> bool {
    result := miniaudio.engine_init(nil, &audio_engine)

    if result != .SUCCESS {
        fmt.printf("Failed to initialize audio engine: %v\n", result)
        return false
    }

    when OPUS_SUPPORT {
        pCustomBackendVTables[0] = &opus_decoder
    }

    return true
}

load_audio :: proc(filepath: string) -> Audio {
    clip := Audio{}

    file_data, read_ok := os.read_entire_file(filepath)
    if !read_ok {
        fmt.printf("Failed to read audio file '%s'\n", filepath)
        return {}
    }

    clip.file_data = file_data

    clip.decoder = new(miniaudio.decoder)

    extension := fp.ext(filepath)
    decoder_config := miniaudio.decoder_config_init(
        outputFormat = .f32,
        outputChannels = 0,
        outputSampleRate = 0,
    )

    when OPUS_SUPPORT {
        decoder_config.ppCustomBackendVTables = &pCustomBackendVTables[0]
        decoder_config.customBackendCount     = 1
        decoder_config.pCustomBackendUserData = nil
    }

    switch extension {
    case ".mp3":
        decoder_config.encodingFormat = .mp3
    case ".wav":
        decoder_config.encodingFormat = .wav
    case ".flac":
        decoder_config.encodingFormat = .flac
    case:
        decoder_config.encodingFormat = .unknown
    }

    decoder_result := miniaudio.decoder_init_memory(
        pData = raw_data(clip.file_data),
        dataSize = len(clip.file_data),
        pConfig = &decoder_config,
        pDecoder = clip.decoder,
    )

    if decoder_result != .SUCCESS {
        fmt.printf("Failed to initialize decoder for '%s': %v\n", filepath, decoder_result)

        delete(clip.file_data)
        free(clip.decoder)
        return {}
    }

    clip.sound = new(miniaudio.sound)

    result := miniaudio.sound_init_from_data_source(
        pEngine = &audio_engine,
        pDataSource = clip.decoder.ds.pCurrent,
        flags = {},
        pGroup = nil,
        pSound = clip.sound,
    )

    if result != .SUCCESS {
        fmt.printf("Failed to load audio file '%s': %v\n", filepath, result)
        miniaudio.decoder_uninit(clip.decoder)
        free(clip.decoder)
        free(clip.sound)
        delete(clip.file_data)
        return {}
    }

    miniaudio.decoder_get_length_in_pcm_frames(clip.decoder, &clip.total_frames)

    format: miniaudio.format
    channels: u32
    miniaudio.decoder_get_data_format(clip.decoder, &format, &channels, &clip.sample_rate, nil, 0)

    clip.duration = f32(clip.total_frames) / f32(clip.sample_rate)
    clip.loaded = true

    if extension == ".mp3" {
        cover, ok := load_album_art_mp3(file_data)

        if ok {
            clip.cover = cover
            clip.has_cover = true
        }
    } else if extension == ".flac" {
        cover, ok := load_album_art_from_flac(file_data)

        if ok {
            clip.cover = cover
            clip.has_cover = true
        }
    } else {
        stem := fp.stem(filepath);
        dir  := fp.dir(filepath);
        path := strings.join({dir, "/", stem, ".png"}, "");

        cover, ok := load_texture(path)
        if ok {
            clip.cover = cover
            clip.has_cover = true
        }
    }

    return clip
}

unload_audio :: proc(clip: ^Audio) {
    if !clip.loaded {
        return
    }

    if clip.has_cover {
        unload_texture(&clip.cover)
        clip.has_cover = false
    }

    if clip.sound != nil {
        miniaudio.sound_uninit(clip.sound)
        free(clip.sound)
        clip.sound = nil
    }

    if clip.decoder != nil {
        miniaudio.decoder_uninit(clip.decoder)
        free(clip.decoder)
        clip.decoder = nil
    }

    if clip.file_data != nil {
        delete(clip.file_data)
        clip.file_data = nil
    }

    clip.loaded = false
}

play_audio :: proc(clip: ^Audio) -> bool {
    if !clip.loaded {
        fmt.println("Audio clip not loaded!")
        return false
    }

    result := miniaudio.sound_start(clip.sound)
    if result != .SUCCESS {
        fmt.printf("Failed to play audio: %v\n", result)
        return false
    }

    return true
}

stop_audio :: proc(clip: ^Audio) -> bool {
    if !clip.loaded {
        return false
    }

    result := miniaudio.sound_stop(clip.sound)
    return result == .SUCCESS
}

pause_audio :: proc(clip: ^Audio) -> bool {
    if !clip.loaded {
        return false
    }

    result := miniaudio.sound_stop(clip.sound)
    return result == .SUCCESS
}

set_volume :: proc(clip: ^Audio, volume: f32) -> bool {
    if !clip.loaded {
        return false
    }

    clamped_volume := clamp(volume, 0.0, 1.0)
    miniaudio.sound_set_volume(clip.sound, clamped_volume)
    return true
}

get_volume :: proc(clip: ^Audio) -> f32 {
    if !clip.loaded {
        return 0.0
    }

    return miniaudio.sound_get_volume(clip.sound)
}

set_time :: proc(clip: ^Audio, time_seconds: f32) -> bool {
    if !clip.loaded {
        return false
    }


    frame_position := u64(time_seconds * f32(clip.sample_rate))


    if frame_position > clip.total_frames {
        frame_position = clip.total_frames
    }

    result := miniaudio.sound_seek_to_pcm_frame(clip.sound, frame_position)
    return result == .SUCCESS
}

get_time :: proc(clip: ^Audio) -> f32 {
    if !clip.loaded {
        return 0.0
    }

    cursor: u64
    result := miniaudio.sound_get_cursor_in_pcm_frames(clip.sound, &cursor)

    if result != .SUCCESS {
        return 0.0
    }


    if cursor > clip.total_frames {
        cursor = clip.total_frames
    }

    return f32(cursor) / f32(clip.sample_rate)
}

get_duration :: proc(clip: ^Audio) -> f32 {
    if !clip.loaded {
        return 0.0
    }


    return clip.duration
}

is_playing :: proc(clip: ^Audio) -> bool {
    if !clip.loaded {
        return false
    }

    return bool(miniaudio.sound_is_playing(clip.sound))
}

set_looping :: proc(clip: ^Audio, loop: bool) -> bool {
    if !clip.loaded {
        return false
    }

    miniaudio.sound_set_looping(clip.sound, b32(loop))
    return true
}

is_looping :: proc(clip: ^Audio) -> bool {
    if !clip.loaded {
        return false
    }

    return bool(miniaudio.sound_is_looping(clip.sound))
}

ID3_Frame_Header :: struct {
    id: [4]u8,
    size: int,
    flags: [2]u8,
}

load_album_art_mp3 :: proc(buffer: []u8) -> (Texture, bool) {
    if !strings.has_prefix(string(buffer[:3]), "ID3") {
        return Texture{}, false
    }

    version := buffer[3]
    size := (int(buffer[6]) & 0x7F) << 21 |
            (int(buffer[7]) & 0x7F) << 14 |
            (int(buffer[8]) & 0x7F) << 7  |
            (int(buffer[9]) & 0x7F)

    pos := 10
    for pos < size {
        if pos + 10 > len(buffer) {
            break
        }

        frame: ID3_Frame_Header

        frame.id[0] = buffer[pos+0]
        frame.id[1] = buffer[pos+1]
        frame.id[2] = buffer[pos+2]
        frame.id[3] = buffer[pos+3]
        frame_id := string(frame.id[:])

        frame.size = 0
        if version >= 4 {
            frame.size = (int(buffer[pos+4]) & 0x7F) << 21 |
                        (int(buffer[pos+5]) & 0x7F) << 14 |
                        (int(buffer[pos+6]) & 0x7F) << 7  |
                        (int(buffer[pos+7]) & 0x7F)
        } else {
            frame.size = int(buffer[pos+4]) << 24 |
                        int(buffer[pos+5]) << 16 |
                        int(buffer[pos+6]) << 8  |
                        int(buffer[pos+7])
        }

        frame.flags[0] = buffer[pos+8]
        frame.flags[1] = buffer[pos+9]

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

            image_data := buffer[data_pos:pos+10+frame.size]

            image := load_texture_from_bytes(image_data)
            if image.width > 0 {
                return image, true
            } else {
                return Texture{}, false
            }
        }

        pos += 10 + frame.size
    }

    return Texture{}, false
}

FLAC_Metadata_Block_Header :: struct {
    is_last: bool,
    type: u8,
    length: int,
}

load_album_art_from_flac :: proc(buffer: []u8) -> (Texture, bool) {
    if !strings.has_prefix(string(buffer[:4]), "fLaC") {
        return Texture{}, false
    }

    pos := 4
    for pos + 4 <= len(buffer) {
        header_byte := buffer[pos]
        block: FLAC_Metadata_Block_Header
        block.is_last = (header_byte & 0x80) != 0
        block.type = header_byte & 0x7F
        block.length = int(buffer[pos+1]) << 16 |
                       int(buffer[pos+2]) << 8 |
                       int(buffer[pos+3])

        pos += 4

        if pos + block.length > len(buffer) {
            break
        }

        if block.type == 6 {
            data := buffer[pos : pos + block.length]
            cursor := 0

            cursor += 4

            mime_length := int(data[cursor]) << 24 |
                           int(data[cursor+1]) << 16 |
                           int(data[cursor+2]) << 8 |
                           int(data[cursor+3])
            cursor += 4

            cursor += mime_length

            desc_length := int(data[cursor]) << 24 |
                           int(data[cursor+1]) << 16 |
                           int(data[cursor+2]) << 8 |
                           int(data[cursor+3])
            cursor += 4

            cursor += desc_length


            cursor += 4 * 4

            pic_data_length := int(data[cursor]) << 24 |
                               int(data[cursor+1]) << 16 |
                               int(data[cursor+2]) << 8 |
                               int(data[cursor+3])
            cursor += 4

            if cursor + pic_data_length > len(data) {
                break
            }

            image_data := data[cursor : cursor + pic_data_length]

            image := load_texture_from_bytes(image_data)
            if image.width > 0 {
                return image, true
            } else {
                return Texture{}, false
            }
        }

        pos += block.length

        if block.is_last {
            break
        }
    }

    return Texture{}, false
}