package fx

import ma "vendor:miniaudio"

OPUS_SUPPORT :: #config(OPUS_SUPPORT, false)

when OPUS_SUPPORT {
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


