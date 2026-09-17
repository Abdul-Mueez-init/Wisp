# Wisp

### Real-Time Messaging & Calling App
**Flutter + Supabase + AI + WebRTC**

Wisp is an independent personal portfolio project built with Flutter to demonstrate a modern real-time communication application. It combines authentication, real-time messaging, media and document sharing, voice notes, location sharing, AI-assisted features, and WebRTC-based audio/video calling.

**Repository:** https://github.com/Abdul-Mueez-init/Wisp

---

## 1. Project Overview

Wisp is a cross-platform Flutter application focused on real-time communication and rich messaging experiences.

The project demonstrates practical application development beyond UI work, including:

- Authentication and session handling
- Real-time messaging and presence
- Media and document sharing
- Voice-note recording and playback
- Location sharing
- AI-assisted text and audio features
- Peer-to-peer audio/video calling with WebRTC
- Cloud-backed data and real-time services through Supabase

The application is structured as a multi-feature Flutter project with centralized configuration, routing, state management, and feature-specific application logic.

---

## 2. Core Features

### Authentication
- User registration and sign in
- Session-aware application flow
- Sign out and authentication state handling

### Real-Time Messaging
- One-to-one real-time chat
- Message delivery without manual refresh
- Presence / online-state behavior
- Conversation state management

### Media & Documents
- Image and media sharing
- File/document selection
- Video support
- Media playback

### Voice Notes
- Record voice messages
- Send and receive voice notes
- Audio playback

### AI Features
- AI-assisted text generation
- Audio-related AI processing
- Gemini integration with Groq fallback paths

### Audio & Video Calling
- WebRTC-based peer-to-peer calling
- Audio calls
- Video calls
- Microphone and camera support
- STUN/TURN configuration for network traversal

### Location
- Location sharing
- Location-aware application flows
- Map display

---

## 3. Technology Stack

| Layer | Technology |
|---|---|
| Mobile framework | Flutter |
| Language | Dart |
| State management | Riverpod |
| Navigation | go_router |
| Backend | Supabase |
| Database | PostgreSQL via Supabase |
| Authentication | Supabase Auth |
| Realtime | Supabase Realtime |
| AI | Gemini / Groq |
| Calling | flutter_webrtc |
| Voice recording | record |
| Audio playback | just_audio |
| Media | image_picker / file_picker / video_player |
| Location | geolocator / flutter_map / latlong2 |
| Configuration | flutter_dotenv |

Dependency definitions are maintained in `pubspec.yaml`, while the repository lock information keeps the resolved package versions reproducible.

---

## 4. High-Level Architecture

```text
Flutter UI
   |
   v
Riverpod Providers / Controllers
   |
   +-----------------------+
   |                       |
   v                       v
Feature Repositories    Shared Configuration
   |                       |
   +-----------+-----------+
               |
        +------+------+ 
        |             |
        v             v
    Supabase       AI / WebRTC
 Auth + Realtime   Gemini/Groq + ICE
        |
        v
Cloud-backed application data
```

Flutter provides the cross-platform client application. Supabase provides authentication, database, and realtime services, while the AI and WebRTC layers handle AI-assisted functionality and real-time audio/video communication.

---

## 5. Project Structure

```text
Wisp/
├── android/
├── ios/
├── lib/
│   ├── config/
│   ├── core/
│   └── features/
├── assets/
├── test/
├── pubspec.yaml
├── pubspec.lock
└── README.md
```

The `lib/` directory is organized around reusable core functionality and feature-owned application code.

---

## 6. Configuration & Environment

Wisp loads runtime configuration from a local `.env` file in the project root.

Required variables:

```dotenv
SUPABASE_URL=...
SUPABASE_ANON_KEY=...
GEMINI_API_KEY=...
GROQ_API_KEY=...
TURN_URL=...
TURN_USERNAME=...
TURN_CREDENTIAL=...
```

Example project layout:

```text
Wisp/
├── .env
├── pubspec.yaml
├── lib/
├── ios/
└── android/
```

### Important

The real `.env` file should remain private and should **not** be committed to the public repository.

For evaluation or demonstration, the required `.env` can be supplied privately so the reviewer does not need to create and configure a separate Supabase project.

---

## 7. Running the Application

### Prerequisites

- Flutter SDK
- Android Studio or another Flutter-compatible IDE
- Android SDK for Android testing
- macOS + Xcode for physical iPhone testing

For the first reproduction, use the Flutter version recorded by the repository metadata: **Flutter 3.44.8 stable**.

### Install dependencies

```bash
flutter clean
flutter pub get
```

### Run on Android

```bash
flutter run
```

### Run on iPhone

For a physical iPhone, use a Mac with Xcode.

1. Place the supplied `.env` in the project root.
2. Run:

```bash
flutter pub get
flutter doctor -v
```

3. Connect and unlock the iPhone.
4. Open the `ios/` project in Xcode.
5. Select the `Runner` target.
6. Under **Signing & Capabilities**, enable **Automatically manage signing**.
7. Select the available Apple Account / Personal Team.
8. Select the connected iPhone as the run destination.
9. Build and run.

An Apple Personal Team can be used for local device testing without a paid Apple Developer Program membership. Provisioning is temporary, so a later reinstall may be required.

---

## 8. First-Launch Permissions

Depending on the feature being tested, Wisp may request:

- **Microphone** — voice notes and calls
- **Camera** — video calls
- **Photos** — media selection
- **Location** — location sharing

Allow the requested permissions during the first test. If a permission is denied, the related feature may need to be re-enabled in the device settings.

---

## 9. Recommended Test Flow

### Basic application flow

```text
Launch
  ↓
Sign in / Register
  ↓
Open conversation
  ↓
Send text message
  ↓
Share media / document
  ↓
Send voice note
  ↓
Test AI feature
  ↓
Start audio / video call
  ↓
End call
  ↓
Test location sharing
```

### Realtime check

Use two authenticated users/devices where possible:

```text
User A sends message
        ↓
Supabase Realtime
        ↓
User B receives message
```

For WebRTC calling, testing with two authenticated users/devices and a stable internet connection is recommended.

---

## 10. Dependency & Plugin Notes

The project dependencies are declared in `pubspec.yaml` and resolved through the repository lock information.

For the first evaluation build:

```bash
flutter pub get
```

Avoid running:

```bash
flutter pub upgrade
```

before the initial test. The goal is to reproduce the known working project state instead of introducing unrelated package changes.

The project currently uses the **`flutter_webrtc` 0.12.x API line**. Keep the existing WebRTC dependency version for the first evaluation build unless an actual platform/build error identifies a specific incompatibility.

If generated dependency state becomes stale, try:

```bash
flutter clean
flutter pub get
```

before changing package versions.

---

## 11. Security & Environment Handling

- Keep the real `.env` outside the public repository.
- Share test configuration privately when required.
- Never place a Supabase `service_role` / secret key in the Flutter client.
- Treat AI API keys used directly by the client as demonstration credentials rather than production secrets.
- Do not commit personal credentials, signing files, or private keys.

---

## 12. Scope & Limitations

Wisp is an independent portfolio project and demonstration application. It is intended to showcase Flutter application development, backend integration, real-time communication, AI integration, media handling, and WebRTC.

A production deployment would require additional work such as:

- Secure server-side handling of sensitive API credentials
- Expanded automated testing
- Production monitoring and analytics
- Formal error tracking
- Production-grade deployment and release management
- Further security review and hardening

---

## 13. What Wisp Demonstrates

- Cross-platform Flutter development
- Feature-based application structure
- State management with Riverpod
- Navigation with go_router
- Supabase authentication and realtime integration
- Rich messaging workflows
- AI API integration
- Audio/video calling with WebRTC
- Native device capabilities such as camera, microphone, files, and location
- Environment-based configuration and external service integration

---

## 14. Key Files

| File / Directory | Purpose |
|---|---|
| `lib/main.dart` | Application bootstrap |
| `lib/config/` | Shared Supabase, AI, and WebRTC configuration |
| `lib/core/` | Shared application infrastructure |
| `lib/features/` | Feature-specific application code |
| `pubspec.yaml` | Dependency definitions |
| `pubspec.lock` | Resolved dependency versions |
| `ios/` | Native iOS project |
| `android/` | Native Android project |

---

## 15. Notes for Reviewers

The repository contains both Android and iOS project targets.

For iPhone testing, the source code can be opened in Android Studio for Flutter development, while **Xcode is required on the Mac for the native iOS build and device signing step**.

The supplied `.env` is intended to remove the need for the reviewer to create a separate Supabase environment just to test the current demo.

---

## License

This project is a personal portfolio project by Abdul Mueez.
