# mfbulut's Music Player

A **minimalist**, **modern**, and **native** music player

[Download Here](https://github.com/mfbulut/MusicPlayer/releases/latest)

## Features

- **Auto-scans Music Folder**: By default, scans `C:\Users\{username}\Music\` for MP3 files.
- **Playlist Discovery**: Any folder containing MP3 files is treated as a playlist.
- **Cover Art Support**:
  - Attempts to load `cover.qoi` or `cover.png` if found in the folder.
  - Extracts embedded PNG cover art from MP3 metadata if available.

## Current State

This is **early-stage** code with low code quality it's a personal learning project.
A full rewrite is planned for the future.

## Building

Currently only Windows is supported

Run ``` odin build src -out:music.exe -o:speed -resource:src/assets/resource.rc -subsystem:windows ```

## Screenshots

![screenshots](screenshots/screenshot1.png)
![screenshots](screenshots/screenshot2.png)

## Recommended Software

Lyrics downloaders
* https://github.com/tranxuanthang/lrcget

Music downloaders
* https://github.com/yt-dlp/yt-dlp
* https://cobalt.tools/
