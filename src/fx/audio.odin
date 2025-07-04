package fx

import "vendor:miniaudio"

import "core:fmt"
import "core:os"
import "core:strings"

import "core:unicode/utf8"
import fp "core:path/filepath"

Audio :: struct {
	file_data:    []byte,
	sound:        ^miniaudio.sound,
	decoder:      ^miniaudio.decoder,

	duration:     f32,
	total_frames: u64,
	sample_rate:  u32,

	loaded:       bool,
}

@(private)
audio_engine: miniaudio.engine

pCustomBackendVTables: [2][^]miniaudio.decoding_backend_vtable

opus_decoder := miniaudio.decoding_backend_vtable {
	onInit       = ma_decoding_backend_init__libopus,
	onInitFile   = ma_decoding_backend_init_file__libopus,
	onInitFileW  = nil,
	onInitMemory = nil,
	onUninit     = ma_decoding_backend_uninit__libopus,
}

vorbis_decoder := miniaudio.decoding_backend_vtable {
	onInit       = ma_decoding_backend_init__libvorbis,
	onInitFile   = ma_decoding_backend_init_file__libvorbis,
	onInitFileW  = nil,
	onInitMemory = nil,
	onUninit     = ma_decoding_backend_uninit__libvorbis,
}

init_audio :: proc() -> bool {
	result := miniaudio.engine_init(nil, &audio_engine)

	if result != .SUCCESS {
		fmt.eprintf("Failed to initialize audio engine: %v\n", result)
		return false
	}

	pCustomBackendVTables[0] = &opus_decoder
	pCustomBackendVTables[1] = &vorbis_decoder

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

	decoder_config.ppCustomBackendVTables = &pCustomBackendVTables[0]
	decoder_config.customBackendCount = 2
	decoder_config.pCustomBackendUserData = nil

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

	return clip
}

unload_audio :: proc(clip: ^Audio) {
	if !clip.loaded {
		return
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
		fmt.eprintln("Audio clip not loaded!")
		return false
	}

	result := miniaudio.sound_start(clip.sound)
	if result != .SUCCESS {
		fmt.eprintf("Failed to play audio: %v\n", result)
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