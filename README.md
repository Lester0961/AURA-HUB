# 🎵 AuraHub

> *Feel the music.*

AuraHub is a mood-based music streaming and offline playback app built with Flutter. It dynamically adapts its visual theme — gradients, particle effects, and accent colors — to match the mood of the currently playing song, creating an immersive listening experience.

---


## ✨ Features

### 🎧 For Users
- **Mood-based theming** — background gradients, particle animations, and accent colors shift in real time based on the song's mood (Joyful, Calm, Melancholic, Energetic, Romantic, Rock)
- **Now Playing screen** — full-screen player with album art, animated waveform, seek bar, and skip controls
- **Mini Player** — persistent bottom bar with play/pause and skip while browsing
- **Search & Filter** — search songs by title and filter by mood category
- **Playlists** — create, rename, and delete playlists; add or remove songs; long-press to manage
- **Offline Downloads** — download any remote song to your device for offline playback; stored in a dedicated `aurahub_downloads/` folder
- **My Downloads folder** — all downloaded songs organized in one place inside the Library tab
- **Smart download sync** — if the admin updates a song's URL, the old cached version is automatically invalidated
- **Google Sign-In & Email/Password auth**

### 🛠 For Admins
- **Admin Panel** — exclusive interface for the designated admin account
- **Add songs** — upload songs via direct MP3 URL (archive.org, Dropbox, GitHub Raw supported); enter title, artist, mood, and cover image URL
- **Edit songs** — modify any added song's title, artist, URL, cover art, or mood after the fact
- **Delete songs** — remove custom songs from the library; automatically removes any user-downloaded copies and stops playback if active
- **Section separation** — clear visual distinction between Built-in Songs (locked) and Custom Songs (editable)
- **YouTube URL detection** — warns admin in real time if a YouTube link is entered and explains why it won't work, with alternative hosting suggestions
- **GitHub URL auto-convert** — automatically converts GitHub blob URLs to raw URLs

---

## 🎨 Mood System

| Mood | Colors | Particle Shape | Feel |
|------|--------|----------------|------|
| Joyful | Orange → Pink | ⭐ Stars | Upbeat, vibrant |
| Melancholic | Deep Blue → Purple | ● Circles | Slow, emotional |
| Calm | Navy → Teal | 💧 Drops | Peaceful, serene |
| Energetic | Blue → Gold | ⚡ Bolts | High energy, pumping |
| Romantic | Dark Red → Pink | ❤️ Hearts | Warm, intimate |
| Rock | Charcoal → Dark Gray | ⚡ Bolts | Raw, intense |

---

## 🗂 Project Structure

```
lib/
└── main.dart              # Entire application (single-file architecture)

assets/
├── audio/                 # Built-in song MP3 files
│   ├── Happy.mp3
│   ├── Sad.mp3
│   ├── Calm.mp3
│   ├── Energetic.mp3
│   ├── Love.mp3
│   └── Rock.mp3
└── images/                # Built-in album artwork
    ├── happy_art.png
    ├── sad_art.png
    ├── calm_art.png
    ├── energetic_art.png
    ├── love_art.png
    └── rock_art.png
```

---

## 🚀 Getting Started

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) 3.0+
- Dart 3.0+
- Android Studio or VS Code with Flutter extension
- A Firebase project (for authentication)

### Installation

```bash
# 1. Clone the repository
git clone https://github.com/Lester0961/AURA-HUB.git
cd AURA-HUB

# 2. Install dependencies
flutter pub get

# 3. Add your Firebase config
# Place google-services.json in android/app/
# Place GoogleService-Info.plist in ios/Runner/
# Ensure firebase_options.dart is present in lib/

# 4. Run the app
flutter run
```

---

## 📦 Dependencies

| Package | Purpose |
|---------|---------|
| `just_audio` | Audio playback engine |
| `firebase_core` | Firebase initialization |
| `firebase_auth` | User authentication |
| `google_sign_in` | Google OAuth login |
| `shared_preferences` | Local data persistence |
| `path_provider` | Device file system access |
| `http` | Remote MP3 downloading |

---

## 🔧 Firebase Setup

1. Create a project at [Firebase Console](https://console.firebase.google.com)
2. Enable **Email/Password** and **Google** sign-in methods under Authentication
3. Download and add the config files:
   - `google-services.json` → `android/app/`
   - `GoogleService-Info.plist` → `ios/Runner/`
4. Run `flutterfire configure` or manually create `lib/firebase_options.dart`

---

## 🎵 Adding Songs (Admin)

AuraHub supports any **direct audio file URL**. YouTube links are not supported.

**Recommended free hosting options:**

| Service | How to get a direct link |
|---------|--------------------------|
| **archive.org** | Upload MP3 → open file → right-click player → *Copy audio address* |
| **Dropbox** | Share link → change `?dl=0` to `?dl=1` |
| **GitHub** | Upload to public repo → open file → click *Raw* → copy URL |
| **ImgBB / Imgur** | For cover images — upload → copy *Direct link* |

---

## 📲 Offline Playback

Downloaded songs are stored on-device at:
```
{App Documents Directory}/aurahub_downloads/
```

- Downloads persist across sessions
- If a song is removed by the admin, its local file is also deleted
- If the admin updates a song's audio URL, the cached version is automatically invalidated and re-download is prompted

---

## 🏗 Architecture Notes

- **Single-file Flutter architecture** — all UI, state, and logic in `lib/main.dart`
- **Global `ValueNotifier` state** — `currentSongNotifier`, `currentMoodNotifier`, `downloadedTitlesNotifier`, and `playlistChangeNotifier` drive reactive UI updates without a state management framework
- **Global `AudioPlayer` instance** — shared across all screens for seamless mini-player and now-playing continuity
- **Mood particle engine** — custom `CustomPainter` renders animated mood-specific shapes (stars, hearts, bolts, drops, circles) using `AnimationController`

---

## 🔐 Admin Access

The admin panel is accessible only from the designated admin email address. Regular users are redirected to the standard home screen upon login. Admin accounts cannot be created through the app's registration flow.

---

## 🐛 Known Limitations

- Playlists and downloaded song metadata are stored in `SharedPreferences` and are local to the device — they are not synced across devices or users
- YouTube URLs are blocked at both the UI and playback level by design
- Song library additions by the admin are also local to the current device (no cloud database)

---

## 🛣 Roadmap

- [ ] Cloud-synced playlists via Firestore
- [ ] Shuffle and repeat modes
- [ ] Sleep timer
- [ ] Equalizer / audio effects
- [ ] Background audio service (persistent notification controls)
- [ ] Song lyrics display

---

## 📄 License

This project is for academic and personal use. All built-in music is original content by **Aura Collective**.

---

<p align="center">Made with ❤️ and Flutter</p>
