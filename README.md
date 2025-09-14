# mfbulut's Music Player

A **minimalist**, **modern**, and **native** music player

### [Download Here](https://github.com/mfbulut/MusicPlayer/releases/latest)

### Features
- **Supported formats**: mp3, flac, wav and ogg
- **Music Folder**:
  - By default, scans `C:\Users\{username}\Music\` for music files.
  - Each subfolder treated as a playlist
  - Uses `cover{.png .jpg .qoi}` as album cover
- **Cover Art Support**:
  - Uses embedded cover art from track
  - Fallbacks to `songname{.png .jpg .qoi}`
- **Lyrics**: Supports **synced** lyrics via **lrcget** or local **.lrc** files
- **Fuzzy Search**, **Queue**, **Likes** etc.

### Controls

| Action                | Shortcut             |
| --------------------- | -------------------- |
| Toggle Sidebar        | `Ctrl + B`           |
| Toggle Compact Mode   | `Ctrl + C`           |
| Add to End of Queue   | `Right-Click`        |
| Add to Start of Queue | `Ctrl + Right-Click` |
| Remove from Queue     | `Ctrl + Left-Click`  |
| Cycle Themes          | `F4`                 |
| Reload Files          | `F5`                 |

## Screenshots

![Screenshot](screenshots/1.png)
![Screenshot](screenshots/2.png)
![Screenshot](screenshots/3.png)
![Screenshot](screenshots/4.png)

## Building

Currently only Windows is supported

[Install Odin compiler](https://odin-lang.org/docs/install/) and run

```odin build src -out:music.exe -o:speed -resource:src/assets/resource.rc -subsystem:windows```

## Recommended Tools

**Metadata:**
* https://picard.musicbrainz.org/

**Lyrics:**
* https://github.com/tranxuanthang/lrcget

**Album covers**
* https://covers.musichoarders.xyz/

**Audio files:**
* https://cobalt.tools/
* https://github.com/yt-dlp/yt-dlp
