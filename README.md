# ⚡ PulsePipe — The Spotify-Killer Powered by YouTube (No Cap)

<div align="center">

```
  ____       _          ____  _            
 |  _ \ _  _| |___  ___|  _ \(_)_ __   ___ 
 | |_) | | | | / __|/ _ \ |_) | | '_ \ / _ \
 |  __/| |_| | \__ \  __/  __/| | |_) |  __/
 |_|    \__,_|_|___/\___|_|   |_| .__/ \___|
                                |_|         
```

### *Streaming music hits different when you don't pay \$11/month for ads. Certified banger. 🎧✨*

[![GitHub Release](https://img.shields.io/github/v/release/taezeem14/PulsePipe?color=00d2ff&style=for-the-badge&logo=github)](https://github.com/taezeem14/PulsePipe/releases/latest)
[![Platform](https://img.shields.io/badge/Platform-Android-3DDC84?style=for-the-badge&logo=android&logoColor=white)](https://github.com/taezeem14/PulsePipe/releases/latest)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Engine](https://img.shields.io/badge/Engine-NewPipe%20Extractor-FF0000?style=for-the-badge&logo=youtube&logoColor=white)](https://github.com/TeamNewPipe/NewPipe)
[![License](https://img.shields.io/badge/License-GPLv3-blue.svg?style=for-the-badge)](LICENSE)
[![Zero Ads](https://img.shields.io/badge/Ads-ZERO%20ADS-success?style=for-the-badge&logo=adguard&logoColor=white)](https://github.com/taezeem14/PulsePipe)

<br/>

### [👉 📲 DOWNLOAD LATEST APK (v1.0.0)](https://github.com/taezeem14/PulsePipe/releases/latest/download/PulsePipe-v1.0.0.apk) 👈

*Tap above, download the APK, install, and elevate your earholes immediately.*

</div>

---

## 💅 What Is PulsePipe?

Look, Spotify got greedy and YouTube Music got annoying with 3 unskippable ads before a 2-minute song. **PulsePipe** is the ultimate lovechild of **Spotify's sleek midnight UI** and **NewPipe's raw, unhinged YouTube extraction power**. 

- **No subscriptions.**
- **No accounts required.**
- **No tracking.**
- **No ads. Ever.**
- Just pure, uninterrupted, audiophile-grade music streamed straight from YouTube & YouTube Music's global catalog.

We cooked so you can vibe. Fr fr. 👨‍🍳🔥

---

## 🚀 The Feature Flex

### 🎧 1. Pure YouTube Engine (Powered by NewPipe)
- Streams direct Opus (160 kbps audiophile) and AAC audio streams straight from YouTube servers.
- No Spotify audio leaks, no sketchy third-party backend scraping, no fake 320kbps MP3 transcode nonsense.
- Instant search across billions of tracks, official artist uploads, live covers, lo-fi beats, unreleased tracks, and remixes.

### 🚫 2. Zero Ads + Integrated SponsorBlock
- You will literally never hear an ad. Ever.
- Built-in **SponsorBlock** automatically detects and skips annoying podcast host sponsorships, intro skits, and outro sponsor plugs. It just stays on the music. Ain't nobody got time for that.

### 🎚️ 3. Studio-Grade Hardware Multi-Band DSP Equalizer
- No artificial gain blowouts or ear-splitting 100x volume glitches.
- Pure Android hardware DSP multi-band EQ calibrated for pristine frequency response.
- **Acoustic Presets**:
  - 📻 `Warm Tape` — Analog vintage saturation & tape warmth
  - ☕ `Lo-Fi` — Mid-focused nostalgic frequency roll-off
  - 🔊 `Bass Boost` — Sub-harmonic low-end without distorting your speakers
  - 🎙️ `Vocal Air` — High-shelf presence for crisp vocals
  - 🎸 `Acoustic` — Balanced natural instrument dynamics
  - 🎛️ `Flat` — Studio reference monitor profile

### ♾️ 4. Infinite YouTube Mixes & Endless Queue
- Put on any YouTube Mix or Radio (`list=RD...`, `list=RDMM...`) and PulsePipe paginates deep into the algorithm, retrieving **150+ to 200+ tracks** on the fly.
- Smart auto-advance ensures seamless track transitions with background stream prefetching.

### 🎤 5. Real-Time Synced Karaoke Lyrics
- Live synchronized karaoke lyrics scrolling line-by-line as the artist sings.
- Tap any line to seek directly to that part of the track.

### 🎨 6. Electric Cyan & Obsidian Midnight Aesthetic
- Built with a stunning Spotify-grade dark UI tailored for OLED screens.
- Electric cyan and deep neon blue accents, smooth gesture sliders, dynamic album art glow, and buttery 120Hz animations.

### 📥 7. Offline Download Vault
- Save any track directly to your device storage for offline plane rides, subway commutes, or gym sessions with zero Wi-Fi.

### 📱 8. Native Android Background Playback & Lock Screen
- Fully integrated with Android `MediaSession` and `AudioService`.
- Rich notification with album artwork, seekbar, next/previous buttons, and bluetooth headset integration with auto-pause on headphone unplug.

---

## 📸 Sneak Peek / Aesthetic

| Now Playing & Glowing Art | Hardware DSP Equalizer | Infinite Queue & Lyrics |
|:---:|:---:|:---:|
| 🌌 Deep Electric Blue Vibe | 🎛️ Multi-Band Studio Shaping | 🎤 Real-Time Karaoke Sync |

---

## ⚡ Installation (Super Easy)

1. Head over to the **[Latest Releases](https://github.com/taezeem14/PulsePipe/releases/latest)**.
2. Download **`PulsePipe-v1.0.0.apk`**.
3. On your Android device, tap the downloaded APK.
4. If prompted, toggle *"Allow install from unknown sources"* (it's open-source, safe, and completely transparent).
5. Open PulsePipe and start streaming! 🚀

---

## 🛠️ Tech Stack & Architecture

PulsePipe is engineered with modern Flutter & Dart architecture:

- **Framework**: [Flutter 3](https://flutter.dev) & Dart 3.11
- **Audio Engine**: [`just_audio`](https://pub.dev/packages/just_audio) + [`audio_service`](https://pub.dev/packages/audio_service) + [`audio_session`](https://pub.dev/packages/audio_session)
- **Extraction Protocol**: [Team NewPipe](https://github.com/TeamNewPipe/NewPipe) extraction logic + [`youtube_explode_dart`](https://pub.dev/packages/youtube_explode_dart) + Piped REST API proxy failover
- **DSP Audio FX**: Android native hardware `AndroidEqualizer` multi-band filter chain
- **Smart Metadata Cleaner**: Custom regex engine extracting true track titles & artist bylines from bloated YouTube video titles
- **Sponsor Filtering**: Official [SponsorBlock API](https://sponsor.ajay.app/) integration
- **State Management**: Reactive `Provider` pattern

---

## 🧑‍💻 Building From Source

Wanna tweak the code or build your own APK? It's straightforward:

```bash
# 1. Clone the repo
git clone https://github.com/taezeem14/PulsePipe.git
cd PulsePipe

# 2. Get dependencies
flutter pub get

# 3. Run static analyzer (verify 0 lint errors)
flutter analyze lib test

# 4. Run tests
flutter test

# 5. Build optimized Android Release APK
flutter build apk --release --no-tree-shake-icons
```

Your compiled APK will be located at:
`build/app/outputs/flutter-apk/app-release.apk`

---

## 👑 Credits & Shoutouts

### Created & Developed By
- **Muhammad Taezeem Tariq** ([@taezeem14](https://github.com/taezeem14)) — *Project Architect, Lead Developer & Mastermind* 🔥

### Special Thanks & Open Source Giants
- **[Team NewPipe](https://github.com/TeamNewPipe/NewPipe)** — For pioneering private, tracker-free YouTube extraction.
- **[YoutubeExplode](https://github.com/Hexer10/YoutubeExplode)** — Exceptional Dart YouTube metadata parser.
- **[Ryan Heise](https://github.com/ryanheise)** — Creator of `just_audio` and `audio_service`.
- **[Ember Mobile](https://github.com/taezeem14/Ember)** — UI inspiration and acoustic design concepts.

---

## 📜 License

PulsePipe is released under the **GNU General Public License v3.0 (GPL-3.0)**. Free as in freedom, forever.

<div align="center">

**Made with 💙 by [taezeem14](https://github.com/taezeem14). If you love this project, drop a ⭐ on the repo!**

</div>
