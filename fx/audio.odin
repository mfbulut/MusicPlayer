package fx

import "vendor:miniaudio"
import "core:fmt"
import "core:strings"
import "core:os"

Audio :: struct {
    duration: f32,
    sound: ^miniaudio.sound,
    cover: Texture,
    loaded: bool,
    has_cover: bool,
}

@(private)
audio_engine: miniaudio.engine

init_audio :: proc() -> bool {
    result := miniaudio.engine_init(nil, &audio_engine)

    if result != .SUCCESS {
        fmt.printf("Failed to initialize audio engine: %v\n", result)
        return false
    }

    return true
}

ID3_Frame_Header :: struct {
    id: [4]u8,
    size: int,
    flags: [2]u8,
}

load_album_art :: proc(file: string) -> (Texture, bool) {
    buffer, ok := os.read_entire_file(file)
    if !ok {
        return Texture{}, false
    }
    defer delete(buffer)

    if !strings.has_prefix(string(buffer[:3]), "ID3") {
        return Texture{}, false
    }

    version := buffer[3]
    revision := buffer[4]
    flags := buffer[5]
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
            return image, true
        }

        pos += 10 + frame.size
    }

    return Texture{}, false
}

load_audio :: proc(filepath: string) -> Audio {
    clip := Audio{}

    filepath_cstr := strings.clone_to_cstring(filepath)
    defer delete(filepath_cstr)

    clip.sound = new(miniaudio.sound)

    result := miniaudio.sound_init_from_file(&audio_engine, filepath_cstr, {}, nil, nil, clip.sound)
    if result != .SUCCESS {
        fmt.printf("Failed to load audio file '%s': %v\n", filepath, result)
        return {}
    }

    length_in_frames: u64
    miniaudio.sound_get_length_in_pcm_frames(clip.sound, &length_in_frames)
    sample_rate := miniaudio.engine_get_sample_rate(&audio_engine)
    clip.duration = f32(length_in_frames) / f32(sample_rate)

    clip.loaded = true

    cover, ok := load_album_art(filepath)

    if ok {
        clip.cover = cover
        clip.has_cover = true
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

    miniaudio.sound_uninit(clip.sound)
    clip.loaded = false
    free(clip.sound)
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

    sample_rate := miniaudio.engine_get_sample_rate(&audio_engine)
    frame_position := u64(time_seconds * f32(sample_rate))

    result := miniaudio.sound_seek_to_pcm_frame(clip.sound, frame_position)
    return result == .SUCCESS
}


get_time :: proc(clip: ^Audio) -> f32 {
    if !clip.loaded {
        return 0.0
    }

    cursor: u64
    miniaudio.sound_get_cursor_in_pcm_frames(clip.sound, &cursor)
    sample_rate := miniaudio.engine_get_sample_rate(&audio_engine)

    return f32(cursor) / f32(sample_rate)
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
