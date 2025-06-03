# mfbulut's Music Player

A **minimalist**, **modern**, and **native** music player

[Download Here](https://github.com/mfbulut/MusicPlayer/releases/latest)

- **Auto-scans Music Folder**: By default, scans `C:\Users\{username}\Music\` for Music files.
- **Playlist Discovery**: Any folder containing mp3, flac and wav files is treated as a playlist.
- **Cover Art Support**:
  - Attempts to load `cover.qoi` or `cover.png` if found in the folder.
  - Extracts embedded PNG cover art from MP3 metadata if available otherview it uses playlist cover.
- Use right click adds songs to the **queue**
- **Hide Sidebar** using Ctrl+B

## Building

Currently only Windows is supported

Run ``` odin build src -out:music.exe -o:speed -resource:src/assets/resource.rc -subsystem:windows ```

## Screenshots

![Screenshot](screenshots/1.png)
![Screenshot](screenshots/2.png)
![Screenshot](screenshots/3.png)

## Recommended Software

Lyrics downloaders
* https://github.com/tranxuanthang/lrcget

Music downloaders
* https://github.com/yt-dlp/yt-dlp
* https://cobalt.tools/
