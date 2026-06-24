package fx

import "base:runtime"
import "core:c"
import ma "vendor:miniaudio"

@(extra_linker_flags = "/nodefaultlib:libcmt")
foreign import opusfile_lib  "deps/opusfile.lib"
foreign import vorbisfile_lib {
    "deps/vorbis.lib",
    "deps/vorbisfile.lib",
}

OggOpusFile :: struct{}

OpusFileCallbacks :: struct {
    read  : proc "c" (stream: rawptr, ptr: [^]u8, nbytes: c.int) -> c.int,
    seek  : proc "c" (stream: rawptr, offset: i64, whence: c.int) -> c.int,
    tell  : proc "c" (stream: rawptr) -> i64,
    close : proc "c" (stream: rawptr) -> c.int,
}

OpusTags :: struct {
    user_comments   : [^]cstring,
    comment_lengths : [^]c.int,
    comments        : c.int,
    vendor          : cstring,
}

OpusPictureTag :: struct {
    type        : i32,
    mime_type   : cstring,
    description : cstring,
    width       : u32,
    height      : u32,
    depth       : u32,
    colors      : u32,
    data_length : u32,
    data        : [^]u8,
    format      : c.int,
}

@(default_calling_convention = "c")
foreign opusfile_lib {
    op_open_callbacks :: proc(stream: rawptr, cb: ^OpusFileCallbacks, initial_data: [^]u8, initial_bytes: c.size_t, error: ^c.int) -> ^OggOpusFile ---
    op_open_file      :: proc(path: cstring, error: ^c.int) -> ^OggOpusFile ---
    op_free           :: proc(of: ^OggOpusFile) ---
    op_read_float     :: proc(of: ^OggOpusFile, pcm: [^]f32, buf_size: c.int, li: ^c.int) -> c.int ---
    op_read           :: proc(of: ^OggOpusFile, pcm: [^]i16, buf_size: c.int, li: ^c.int) -> c.int ---
    op_pcm_seek       :: proc(of: ^OggOpusFile, sample_offset: i64) -> c.int ---
    op_pcm_tell       :: proc(of: ^OggOpusFile) -> i64 ---
    op_pcm_total      :: proc(of: ^OggOpusFile, li: c.int) -> i64 ---
    op_channel_count  :: proc(of: ^OggOpusFile, li: c.int) -> c.int ---

    // Metadata functions
    op_tags              :: proc(of: ^OggOpusFile, li: c.int) -> ^OpusTags ---
    opus_tags_query       :: proc(tags: ^OpusTags, tag: cstring, count: c.int) -> cstring ---
    opus_tags_query_count :: proc(tags: ^OpusTags, tag: cstring) -> c.int ---

    // Picture tag functions
    opus_picture_tag_parse :: proc(pic: ^OpusPictureTag, tag: cstring) -> c.int ---
    opus_picture_tag_init  :: proc(pic: ^OpusPictureTag) ---
    opus_picture_tag_clear :: proc(pic: ^OpusPictureTag) ---
}

OP_ENOSEEK :: -133
OP_EINVAL  :: -131

OggVorbis_File :: struct { _pad: [840]u8 }

VorbisInfo :: struct {
    version         : c.int,
    channels        : c.int,
    rate            : c.long,
    bitrate_upper   : c.long,
    bitrate_nominal : c.long,
    bitrate_lower   : c.long,
    bitrate_window  : c.long,
    codec_setup     : rawptr,
}

OvCallbacks :: struct {
    read_func  : proc "c" (ptr: rawptr, size: c.size_t, nmemb: c.size_t, stream: rawptr) -> c.size_t,
    seek_func  : proc "c" (stream: rawptr, offset: i64, whence: c.int) -> c.int,
    close_func : proc "c" (stream: rawptr) -> c.int,
    tell_func  : proc "c" (stream: rawptr) -> c.long,
}

VorbisComment :: struct {
    user_comments   : [^]cstring,
    comment_lengths : [^]c.int,
    comments        : c.int,
    vendor          : cstring,
}

@(default_calling_convention = "c")
foreign vorbisfile_lib {
    ov_open_callbacks :: proc(datasource: rawptr, vf: ^OggVorbis_File, initial: rawptr, ibytes: c.long, callbacks: OvCallbacks) -> c.int ---
    ov_fopen          :: proc(path: cstring, vf: ^OggVorbis_File) -> c.int ---
    ov_clear          :: proc(vf: ^OggVorbis_File) -> c.int ---
    ov_info           :: proc(vf: ^OggVorbis_File, link: c.int) -> ^VorbisInfo ---
    ov_read           :: proc(vf: ^OggVorbis_File, buffer: [^]u8, length: c.int, bigendianp: c.int, word: c.int, sgned: c.int, bitstream: ^c.int) -> c.long ---
    ov_read_float     :: proc(vf: ^OggVorbis_File, pcm_channels: ^[^][^]f32, samples: c.int, bitstream: ^c.int) -> c.long ---
    ov_pcm_seek       :: proc(vf: ^OggVorbis_File, pos: i64) -> c.int ---
    ov_pcm_tell       :: proc(vf: ^OggVorbis_File) -> i64 ---

    // Comment / metadata functions
    ov_comment             :: proc(vf: ^OggVorbis_File, link: c.int) -> ^VorbisComment ---
    vorbis_comment_query   :: proc(vc: ^VorbisComment, tag: cstring, count: c.int) -> cstring ---
    vorbis_comment_query_count :: proc(vc: ^VorbisComment, tag: cstring) -> c.int ---
}

OV_ENOSEEK :: -150
OV_EINVAL  :: -131

SEEK_SET :: 0
SEEK_CUR :: 1
SEEK_END :: 2

// ---------------------------------------------------------------------------
// ma_libopus – internal state
// ---------------------------------------------------------------------------

ma_libopus :: struct {
    ds                   : ma.data_source_base,
    onRead               : ma.decoder_read_proc,
    onSeek               : ma.decoder_seek_proc,
    onTell               : ma.decoder_tell_proc,
    pReadSeekTellUserData: rawptr,
    format               : ma.format,
    of                   : ^OggOpusFile,
}

// data-source vtable callbacks
g_ma_libopus_ds_vtable := ma.data_source_vtable{
    onRead          = ma_libopus_read_pcm_frames,
    onSeek          = ma_libopus_seek_to_pcm_frame,
    onGetDataFormat = ma_libopus_get_data_format,
    onGetCursor     = ma_libopus_get_cursor_in_pcm_frames,
    onGetLength     = ma_libopus_get_length_in_pcm_frames,
    onSetLooping    = nil,
    flags           = {},
}

_opus_cb_read :: proc "c" (pUserData: rawptr, pBufferOut: [^]u8, bytesToRead: c.int) -> c.int {
    pOpus := (^ma_libopus)(pUserData)
    bytesRead: c.size_t
    result := pOpus.onRead((^ma.decoder)(pOpus.pReadSeekTellUserData), pBufferOut, auto_cast bytesToRead, &bytesRead)
    if result != .SUCCESS { return -1 }
    return c.int(bytesRead)
}

_opus_cb_seek :: proc "c" (pUserData: rawptr, offset: i64, whence: c.int) -> c.int {
    pOpus := (^ma_libopus)(pUserData)
    origin: ma.seek_origin
    switch whence {
    case SEEK_SET: origin = .start
    case SEEK_END: origin = .end
    case:          origin = .current
    }
    if pOpus.onSeek((^ma.decoder)(pOpus.pReadSeekTellUserData), offset, origin) != .SUCCESS { return -1 }
    return 0
}

_opus_cb_tell :: proc "c" (pUserData: rawptr) -> i64 {
    pOpus := (^ma_libopus)(pUserData)
    if pOpus.onTell == nil { return -1 }
    cursor: i64
    if pOpus.onTell((^ma.decoder)(pOpus.pReadSeekTellUserData), &cursor) != .SUCCESS { return -1 }
    return cursor
}

ma_libopus_init_internal :: proc "c" (pConfig: ^ma.decoding_backend_config, pOpus: ^ma_libopus) -> ma.result {
    if pOpus == nil { return .INVALID_ARGS }
    pOpus^ = {}
    pOpus.format = .f32
    if pConfig != nil && (pConfig.preferredFormat == .f32 || pConfig.preferredFormat == .s16) {
        pOpus.format = pConfig.preferredFormat
    }
    dsCfg := ma.data_source_config_init()
    dsCfg.vtable = &g_ma_libopus_ds_vtable
    return ma.data_source_init(&dsCfg, (^ma.data_source)(&pOpus.ds))
}

ma_libopus_init :: proc "c" (onRead: ma.decoder_read_proc, onSeek: ma.decoder_seek_proc, onTell: ma.decoder_tell_proc, pReadSeekTellUserData: rawptr, pConfig: ^ma.decoding_backend_config, pAllocationCallbacks: ^ma.allocation_callbacks, pOpus: ^ma_libopus) -> ma.result {
    result := ma_libopus_init_internal(pConfig, pOpus)
    if result != .SUCCESS { return result }
    if onRead == nil || onSeek == nil { return .INVALID_ARGS }
    pOpus.onRead                = onRead
    pOpus.onSeek                = onSeek
    pOpus.onTell                = onTell
    pOpus.pReadSeekTellUserData = pReadSeekTellUserData

    cbs := OpusFileCallbacks{
        read  = _opus_cb_read,
        seek  = _opus_cb_seek,
        tell  = _opus_cb_tell,
        close = nil,
    }
    err: c.int
    pOpus.of = op_open_callbacks(pOpus, &cbs, nil, 0, &err)
    if pOpus.of == nil { return .INVALID_FILE }
    return .SUCCESS
}

ma_libopus_init_file :: proc "c" (pFilePath: cstring, pConfig: ^ma.decoding_backend_config, pAllocationCallbacks: ^ma.allocation_callbacks, pOpus: ^ma_libopus) -> ma.result {
    result := ma_libopus_init_internal(pConfig, pOpus)
    if result != .SUCCESS { return result }
    err: c.int
    pOpus.of = op_open_file(pFilePath, &err)
    if pOpus.of == nil { return .INVALID_FILE }
    return .SUCCESS
}

ma_libopus_uninit :: proc "c" (pOpus: ^ma_libopus, pAllocationCallbacks: ^ma.allocation_callbacks) {
    if pOpus == nil { return }
    op_free(pOpus.of)
    ma.data_source_uninit((^ma.data_source)(&pOpus.ds))
}

ma_libopus_read_pcm_frames :: proc "c" (pDataSource: ^ma.data_source, pFramesOut: rawptr, frameCount: u64, pFramesRead: ^u64) -> ma.result {
    pOpus := (^ma_libopus)(pDataSource)
    if pFramesRead != nil { pFramesRead^ = 0 }
    if frameCount == 0 || pOpus == nil { return .INVALID_ARGS }

    fmt: ma.format; ch: u32
    ma_libopus_get_data_format((^ma.data_source)(pOpus), &fmt, &ch, nil, nil, 0)

    totalRead: u64
    result: ma.result = .SUCCESS
    for totalRead < frameCount {
        remaining := frameCount - totalRead
        batch := u64(1024)
        if batch > remaining { batch = remaining }

        libResult: c.int
        if fmt == .f32 {
            ptr := ma.offset_pcm_frames_ptr(pFramesOut, totalRead, fmt, ch)
            libResult = op_read_float(pOpus.of, (^f32)(ptr), c.int(batch * u64(ch)), nil)
        } else {
            ptr := ma.offset_pcm_frames_ptr(pFramesOut, totalRead, fmt, ch)
            libResult = op_read(pOpus.of, (^i16)(ptr), c.int(batch * u64(ch)), nil)
        }

        if libResult < 0 { result = .ERROR; break }
        totalRead += u64(libResult)
        if libResult == 0 { result = .AT_END; break }
    }

    if pFramesRead != nil { pFramesRead^ = totalRead }
    if result == .SUCCESS && totalRead == 0 { return .AT_END }
    return result
}

ma_libopus_seek_to_pcm_frame :: proc "c" (pDataSource: ^ma.data_source, frameIndex: u64) -> ma.result {
    pOpus := (^ma_libopus)(pDataSource)
    if pOpus == nil { return .INVALID_ARGS }
    r := op_pcm_seek(pOpus.of, i64(frameIndex))
    if r != 0 {
        switch r {
        case OP_ENOSEEK: return .INVALID_OPERATION
        case OP_EINVAL:  return .INVALID_ARGS
        case:            return .ERROR
        }
    }
    return .SUCCESS
}

ma_libopus_get_data_format :: proc "c" (pDataSource: ^ma.data_source, pFormat: ^ma.format, pChannels: ^u32, pSampleRate: ^u32, pChannelMap: [^]ma.channel, channelMapCap: c.size_t) -> ma.result {
    pOpus := (^ma_libopus)(pDataSource)
    if pFormat     != nil { pFormat^     = .unknown }
    if pChannels   != nil { pChannels^   = 0 }
    if pSampleRate != nil { pSampleRate^ = 0 }
    if pChannelMap != nil { runtime.memset(pChannelMap, 0, int(channelMapCap) * size_of(ma.channel)) }
    if pOpus == nil { return .INVALID_OPERATION }

    if pFormat != nil { pFormat^ = pOpus.format }

    ch := u32(op_channel_count(pOpus.of, -1))
    if pChannels   != nil { pChannels^   = ch }
    if pSampleRate != nil { pSampleRate^ = 48000 }
    if pChannelMap != nil { ma.channel_map_init_standard(.vorbis, pChannelMap, uint(channelMapCap), ch) }
    return .SUCCESS
}

ma_libopus_get_cursor_in_pcm_frames :: proc "c" (pDataSource: ^ma.data_source, pCursor: ^u64) -> ma.result {
    pOpus := (^ma_libopus)(pDataSource)
    if pCursor == nil { return .INVALID_ARGS }
    pCursor^ = 0
    if pOpus == nil { return .INVALID_ARGS }
    offset := op_pcm_tell(pOpus.of)
    if offset < 0 { return .INVALID_FILE }
    pCursor^ = u64(offset)
    return .SUCCESS
}

ma_libopus_get_length_in_pcm_frames :: proc "c" (pDataSource: ^ma.data_source, pLength: ^u64) -> ma.result {
    pOpus := (^ma_libopus)(pDataSource)
    if pLength == nil { return .INVALID_ARGS }
    pLength^ = 0
    if pOpus == nil { return .INVALID_ARGS }
    length := op_pcm_total(pOpus.of, -1)
    if length < 0 { return .ERROR }
    pLength^ = u64(length)
    return .SUCCESS
}

// ---------------------------------------------------------------------------
// ma_libvorbis – internal state
// ---------------------------------------------------------------------------

ma_libvorbis :: struct {
    ds                   : ma.data_source_base,
    onRead               : ma.decoder_read_proc,
    onSeek               : ma.decoder_seek_proc,
    onTell               : ma.decoder_tell_proc,
    pReadSeekTellUserData: rawptr,
    format               : ma.format,
    vf                   : ^OggVorbis_File,
}

g_ma_libvorbis_ds_vtable := ma.data_source_vtable{
    onRead          = ma_libvorbis_read_pcm_frames,
    onSeek          = ma_libvorbis_seek_to_pcm_frame,
    onGetDataFormat = ma_libvorbis_get_data_format,
    onGetCursor     = ma_libvorbis_get_cursor_in_pcm_frames,
    onGetLength     = ma_libvorbis_get_length_in_pcm_frames,
    onSetLooping    = nil,
    flags           = {},
}

_vorbis_cb_read :: proc "c" (ptr: rawptr, size: c.size_t, nmemb: c.size_t, stream: rawptr) -> c.size_t {
    pVorbis := (^ma_libvorbis)(stream)
    if size == 0 || nmemb == 0 { return 0 }
    bytesToRead := size * nmemb
    bytesRead: c.size_t
    result := pVorbis.onRead((^ma.decoder)(pVorbis.pReadSeekTellUserData), ptr, bytesToRead, &bytesRead)
    if result != .SUCCESS { return 0 }
    return bytesRead / size
}

_vorbis_cb_seek :: proc "c" (stream: rawptr, offset: i64, whence: c.int) -> c.int {
    pVorbis := (^ma_libvorbis)(stream)
    origin: ma.seek_origin
    switch whence {
    case SEEK_SET: origin = .start
    case SEEK_END: origin = .end
    case:          origin = .current
    }
    if pVorbis.onSeek((^ma.decoder)(pVorbis.pReadSeekTellUserData), offset, origin) != .SUCCESS { return -1 }
    return 0
}

_vorbis_cb_tell :: proc "c" (stream: rawptr) -> c.long {
    pVorbis := (^ma_libvorbis)(stream)
    cursor: i64
    if pVorbis.onTell((^ma.decoder)(pVorbis.pReadSeekTellUserData), &cursor) != .SUCCESS { return -1 }
    return c.long(cursor)
}

ma_libvorbis_init_internal :: proc "c" (pConfig: ^ma.decoding_backend_config, pAllocationCallbacks: ^ma.allocation_callbacks, pVorbis: ^ma_libvorbis) -> ma.result {
    if pVorbis == nil { return .INVALID_ARGS }
    pVorbis^ = {}
    pVorbis.format = .f32
    if pConfig != nil && (pConfig.preferredFormat == .f32 || pConfig.preferredFormat == .s16) {
        pVorbis.format = pConfig.preferredFormat
    }
    dsCfg := ma.data_source_config_init()
    dsCfg.vtable = &g_ma_libvorbis_ds_vtable
    result := ma.data_source_init(&dsCfg, (^ma.data_source)(&pVorbis.ds))
    if result != .SUCCESS { return result }

    pVorbis.vf = (^OggVorbis_File)(ma.malloc(size_of(OggVorbis_File), pAllocationCallbacks))
    if pVorbis.vf == nil {
        ma.data_source_uninit((^ma.data_source)(&pVorbis.ds))
        return .OUT_OF_MEMORY
    }
    return .SUCCESS
}

ma_libvorbis_init :: proc "c" (onRead: ma.decoder_read_proc, onSeek: ma.decoder_seek_proc, onTell: ma.decoder_tell_proc, pReadSeekTellUserData: rawptr, pConfig: ^ma.decoding_backend_config, pAllocationCallbacks: ^ma.allocation_callbacks, pVorbis: ^ma_libvorbis) -> ma.result {
    result := ma_libvorbis_init_internal(pConfig, pAllocationCallbacks, pVorbis)
    if result != .SUCCESS { return result }
    if onRead == nil || onSeek == nil { return .INVALID_ARGS }

    pVorbis.onRead                = onRead
    pVorbis.onSeek                = onSeek
    pVorbis.onTell                = onTell
    pVorbis.pReadSeekTellUserData = pReadSeekTellUserData

    cbs := OvCallbacks{
        read_func  = _vorbis_cb_read,
        seek_func  = _vorbis_cb_seek,
        close_func = nil,
        tell_func  = _vorbis_cb_tell,
    }
    if ov_open_callbacks(pVorbis, pVorbis.vf, nil, 0, cbs) < 0 { return .INVALID_FILE }
    return .SUCCESS
}

ma_libvorbis_init_file :: proc "c" (pFilePath: cstring, pConfig: ^ma.decoding_backend_config, pAllocationCallbacks: ^ma.allocation_callbacks, pVorbis: ^ma_libvorbis) -> ma.result {
    result := ma_libvorbis_init_internal(pConfig, pAllocationCallbacks, pVorbis)
    if result != .SUCCESS { return result }
    if ov_fopen(pFilePath, pVorbis.vf) < 0 { return .INVALID_FILE }
    return .SUCCESS
}

ma_libvorbis_uninit :: proc "c" (pVorbis: ^ma_libvorbis, pAllocationCallbacks: ^ma.allocation_callbacks) {
    if pVorbis == nil { return }
    ov_clear(pVorbis.vf)
    ma.data_source_uninit((^ma.data_source)(&pVorbis.ds))
    ma.free(pVorbis.vf, pAllocationCallbacks)
}

ma_libvorbis_read_pcm_frames :: proc "c" (pDataSource: ^ma.data_source, pFramesOut: rawptr, frameCount: u64, pFramesRead: ^u64) -> ma.result {
    pVorbis := (^ma_libvorbis)(pDataSource)
    if pFramesRead != nil { pFramesRead^ = 0 }
    if frameCount == 0 || pVorbis == nil { return .INVALID_ARGS }

    fmt: ma.format; ch: u32
    ma_libvorbis_get_data_format((^ma.data_source)(pVorbis), &fmt, &ch, nil, nil, 0)

    totalRead: u64
    result: ma.result = .SUCCESS

    for totalRead < frameCount {
        remaining := frameCount - totalRead
        batch := u64(4096)
        if batch > remaining { batch = remaining }

        libResult: c.long
        if fmt == .f32 {
            // ov_read_float returns de-interleaved channel pointers; we must interleave manually.
            channels_ptr: [^][^]f32
            libResult = ov_read_float(pVorbis.vf, &channels_ptr, c.int(batch), nil)
            if libResult > 0 {
                dst := (^f32)(ma.offset_pcm_frames_ptr(pFramesOut, totalRead, fmt, ch))
                nframes := int(libResult)
                nch     := int(ch)
                for f in 0..<nframes {
                    for c_idx in 0..<nch {
                        ch_buf := channels_ptr[c_idx]
                        (cast([^]f32)dst)[f * nch + c_idx] = ch_buf[f]
                    }
                }
            }
        } else {
            ptr      := ma.offset_pcm_frames_ptr(pFramesOut, totalRead, fmt, ch)
            bytesCap := c.int(batch) * c.int(ma.get_bytes_per_frame(fmt, ch))
            libResult = ov_read(pVorbis.vf, (^u8)(ptr), bytesCap, 0, 2, 1, nil)
            if libResult > 0 {
                libResult = c.long(libResult) / c.long(ma.get_bytes_per_frame(fmt, ch))
            }
        }

        if libResult < 0 { result = .ERROR; break }
        totalRead += u64(libResult)
        if libResult == 0 { result = .AT_END; break }
    }

    if pFramesRead != nil { pFramesRead^ = totalRead }
    if result == .SUCCESS && totalRead == 0 { return .AT_END }
    return result
}

ma_libvorbis_seek_to_pcm_frame :: proc "c" (pDataSource: ^ma.data_source, frameIndex: u64) -> ma.result {
    pVorbis := (^ma_libvorbis)(pDataSource)
    if pVorbis == nil { return .INVALID_ARGS }
    r := ov_pcm_seek(pVorbis.vf, i64(frameIndex))
    if r != 0 {
        switch r {
        case OV_ENOSEEK: return .INVALID_OPERATION
        case OV_EINVAL:  return .INVALID_ARGS
        case:            return .ERROR
        }
    }
    return .SUCCESS
}

ma_libvorbis_get_data_format :: proc "c" (pDataSource: ^ma.data_source, pFormat: ^ma.format, pChannels: ^u32, pSampleRate: ^u32, pChannelMap: [^]ma.channel, channelMapCap: c.size_t) -> ma.result {
    pVorbis := (^ma_libvorbis)(pDataSource)
    if pFormat     != nil { pFormat^     = .unknown }
    if pChannels   != nil { pChannels^   = 0 }
    if pSampleRate != nil { pSampleRate^ = 0 }
    if pChannelMap != nil { runtime.memset(pChannelMap, 0, int(channelMapCap) * size_of(ma.channel)) }
    if pVorbis == nil { return .INVALID_OPERATION }

    if pFormat != nil { pFormat^ = pVorbis.format }

    info := ov_info(pVorbis.vf, 0)
    if info == nil { return .INVALID_OPERATION }

    ch := u32(info.channels)
    if pChannels   != nil { pChannels^   = ch }
    if pSampleRate != nil { pSampleRate^ = u32(info.rate) }
    if pChannelMap != nil { ma.channel_map_init_standard(.vorbis, pChannelMap, uint(channelMapCap), ch) }
    return .SUCCESS
}

ma_libvorbis_get_cursor_in_pcm_frames :: proc "c" (pDataSource: ^ma.data_source, pCursor: ^u64) -> ma.result {
    pVorbis := (^ma_libvorbis)(pDataSource)
    if pCursor == nil { return .INVALID_ARGS }
    pCursor^ = 0
    if pVorbis == nil { return .INVALID_ARGS }
    offset := ov_pcm_tell(pVorbis.vf)
    if offset < 0 { return .INVALID_FILE }
    pCursor^ = u64(offset)
    return .SUCCESS
}

ma_libvorbis_get_length_in_pcm_frames :: proc "c" (pDataSource: ^ma.data_source, pLength: ^u64) -> ma.result {
    pVorbis := (^ma_libvorbis)(pDataSource)
    if pLength == nil { return .INVALID_ARGS }
    pLength^ = 0
    return .SUCCESS
}

ma_decoding_backend_init__libopus :: proc "c" (pUserData: rawptr, onRead: ma.decoder_read_proc, onSeek: ma.decoder_seek_proc, onTell: ma.decoder_tell_proc, pReadSeekTellUserData: rawptr, pConfig: ^ma.decoding_backend_config, pAllocationCallbacks: ^ma.allocation_callbacks, ppBackend: ^^ma.data_source) -> ma.result {
    pOpus := (^ma_libopus)(ma.malloc(size_of(ma_libopus), pAllocationCallbacks))
    if pOpus == nil { return .OUT_OF_MEMORY }
    result := ma_libopus_init(onRead, onSeek, onTell, pReadSeekTellUserData, pConfig, pAllocationCallbacks, pOpus)
    if result != .SUCCESS { ma.free(pOpus, pAllocationCallbacks); return result }
    ppBackend^ = (^ma.data_source)(pOpus)
    return .SUCCESS
}

ma_decoding_backend_init_file__libopus :: proc "c" (pUserData: rawptr, pFilePath: cstring, pConfig: ^ma.decoding_backend_config, pAllocationCallbacks: ^ma.allocation_callbacks, ppBackend: ^^ma.data_source) -> ma.result {
    pOpus := (^ma_libopus)(ma.malloc(size_of(ma_libopus), pAllocationCallbacks))
    if pOpus == nil { return .OUT_OF_MEMORY }
    result := ma_libopus_init_file(pFilePath, pConfig, pAllocationCallbacks, pOpus)
    if result != .SUCCESS { ma.free(pOpus, pAllocationCallbacks); return result }
    ppBackend^ = (^ma.data_source)(pOpus)
    return .SUCCESS
}

ma_decoding_backend_uninit__libopus :: proc "c" (pUserData: rawptr, pBackend: ^ma.data_source, pAllocationCallbacks: ^ma.allocation_callbacks) {
    pOpus := (^ma_libopus)(pBackend)
    ma_libopus_uninit(pOpus, pAllocationCallbacks)
    ma.free(pOpus, pAllocationCallbacks)
}

ma_decoding_backend_init__libvorbis :: proc "c" (pUserData: rawptr, onRead: ma.decoder_read_proc, onSeek: ma.decoder_seek_proc, onTell: ma.decoder_tell_proc, pReadSeekTellUserData: rawptr, pConfig: ^ma.decoding_backend_config, pAllocationCallbacks: ^ma.allocation_callbacks, ppBackend: ^^ma.data_source) -> ma.result {
    pVorbis := (^ma_libvorbis)(ma.malloc(size_of(ma_libvorbis), pAllocationCallbacks))
    if pVorbis == nil { return .OUT_OF_MEMORY }
    result := ma_libvorbis_init(onRead, onSeek, onTell, pReadSeekTellUserData, pConfig, pAllocationCallbacks, pVorbis)
    if result != .SUCCESS { ma.free(pVorbis, pAllocationCallbacks); return result }
    ppBackend^ = (^ma.data_source)(pVorbis)
    return .SUCCESS
}

ma_decoding_backend_init_file__libvorbis :: proc "c" (pUserData: rawptr, pFilePath: cstring, pConfig: ^ma.decoding_backend_config, pAllocationCallbacks: ^ma.allocation_callbacks, ppBackend: ^^ma.data_source) -> ma.result {
    pVorbis := (^ma_libvorbis)(ma.malloc(size_of(ma_libvorbis), pAllocationCallbacks))
    if pVorbis == nil { return .OUT_OF_MEMORY }
    result := ma_libvorbis_init_file(pFilePath, pConfig, pAllocationCallbacks, pVorbis)
    if result != .SUCCESS { ma.free(pVorbis, pAllocationCallbacks); return result }
    ppBackend^ = (^ma.data_source)(pVorbis)
    return .SUCCESS
}

ma_decoding_backend_uninit__libvorbis :: proc "c" (pUserData: rawptr, pBackend: ^ma.data_source, pAllocationCallbacks: ^ma.allocation_callbacks) {
    pVorbis := (^ma_libvorbis)(pBackend)
    ma_libvorbis_uninit(pVorbis, pAllocationCallbacks)
    ma.free(pVorbis, pAllocationCallbacks)
}


// Miniaudio vorbis and opus backends

_libopus_vtable := ma.decoding_backend_vtable{
    onInit      = ma_decoding_backend_init__libopus,
    onInitFile  = ma_decoding_backend_init_file__libopus,
    onInitFileW = nil,
    onInitMemory= nil,
    onUninit    = ma_decoding_backend_uninit__libopus,
}

_libvorbis_vtable := ma.decoding_backend_vtable{
    onInit      = ma_decoding_backend_init__libvorbis,
    onInitFile  = ma_decoding_backend_init_file__libvorbis,
    onInitFileW = nil,
    onInitMemory= nil,
    onUninit    = ma_decoding_backend_uninit__libvorbis,
}
