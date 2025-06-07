# mfbulut's Music Player

A **minimalist**, **modern**, and **native** music player

[Download Here](https://github.com/mfbulut/MusicPlayer/releases/latest)

- **Auto-scans Music Folder**: By default, scans `C:\Users\{username}\Music\` for Music files.
- **Playlist Discovery**: Any folder containing mp3, flac, wav, opus and ogg(opus only) files is treated as a playlist.
- **Cover Art Support**:
  - Extracts embedded PNG cover art from metadata if available.
  - Otherwise it attempts to load `cover.qoi` or `cover.png` if found in the folder.
- Use right click adds songs to the **queue**
- **Hide Sidebar** using Ctrl+B

## Building

Currently only Windows is supported

Run ``` odin build src -out:music.exe -o:speed -resource:src/assets/resource.rc -subsystem:windows```

## Screenshots

![screenshot](screenshots/1.png)
![screenshot](screenshots/2.png)
![screenshot](screenshots/3.png)

## Recommended Software

Lyrics downloaders
* https://github.com/tranxuanthang/lrcget

Music downloaders
* https://cobalt.tools/
* https://github.com/yt-dlp/yt-dlp
