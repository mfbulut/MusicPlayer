package fx

import ma "vendor:miniaudio"

OPUS_SUPPORT :: #config(OPUS_SUPPORT, true)

when OPUS_SUPPORT {

    // How to compile from source
    // https://github.com/dotBlueShoes/Metronome/blob/master/notes/Compiling%20OPUSFILE%20on%20Windows.md

    foreign import decoder {
    	"deps/decoder.lib",
        "deps/opusfile/lib/opusfile.lib",
        "deps/opus/lib/opus.lib",
        "deps/ogg/lib/ogg.lib",
    }

    foreign decoder {
    	ma_decoding_backend_libopus : [^]ma.decoding_backend_vtable
    }
}


