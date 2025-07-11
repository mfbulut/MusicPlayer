package fx

import ma "vendor:miniaudio"

// How to compile from source
// https://github.com/dotBlueShoes/Metronome/blob/master/notes/Compiling%20OPUSFILE%20on%20Windows.md

@(extra_linker_flags = "/nodefaultlib:libcmt")
foreign import decoder {"deps/decoder.lib", "deps/opusfile/lib/opusfile.lib", "deps/vorbisfile/lib/vorbis.lib", "deps/vorbisfile/lib/vorbisfile.lib"}

@(default_calling_convention = "c")
foreign decoder {
	ma_decoding_backend_init__libopus :: proc(pUserData: rawptr, onRead: ma.decoder_read_proc, onSeek: ma.decoder_seek_proc, onTell: ma.decoder_tell_proc, pReadSeekTellUserData: rawptr, pConfig: ^ma.decoding_backend_config, pAllocationCallbacks: ^ma.allocation_callbacks, ppBackend: ^^ma.data_source) -> ma.result ---
	ma_decoding_backend_init_file__libopus :: proc(pUserData: rawptr, pFilePath: cstring, pConfig: ^ma.decoding_backend_config, pAllocationCallbacks: ^ma.allocation_callbacks, ppBackend: ^^ma.data_source) -> ma.result ---
	ma_decoding_backend_uninit__libopus :: proc(pUserData: rawptr, pBackend: ^ma.data_source, pAllocationCallbacks: ^ma.allocation_callbacks) ---

	ma_decoding_backend_init__libvorbis :: proc(pUserData: rawptr, onRead: ma.decoder_read_proc, onSeek: ma.decoder_seek_proc, onTell: ma.decoder_tell_proc, pReadSeekTellUserData: rawptr, pConfig: ^ma.decoding_backend_config, pAllocationCallbacks: ^ma.allocation_callbacks, ppBackend: ^^ma.data_source) -> ma.result ---
	ma_decoding_backend_init_file__libvorbis :: proc(pUserData: rawptr, pFilePath: cstring, pConfig: ^ma.decoding_backend_config, pAllocationCallbacks: ^ma.allocation_callbacks, ppBackend: ^^ma.data_source) -> ma.result ---
	ma_decoding_backend_uninit__libvorbis :: proc(pUserData: rawptr, pBackend: ^ma.data_source, pAllocationCallbacks: ^ma.allocation_callbacks) ---
}
