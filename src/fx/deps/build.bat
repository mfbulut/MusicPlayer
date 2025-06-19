call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
cl /c /O2 miniaudio_libopus.c /Iopusfile/include /Iopus/include /Iogg/include
cl /c /O2 miniaudio_libvorbis.c /Ivorbisfile/include /Iogg/include
lib miniaudio_libopus.obj miniaudio_libvorbis.obj /OUT:decoder.lib
del miniaudio_libopus.obj miniaudio_libvorbis.obj
