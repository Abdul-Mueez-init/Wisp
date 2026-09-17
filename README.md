# Wisp

> A realtime Flutter messaging platform combining chat, media, AI features, location sharing, stories, and audio/video calling.

Wisp is a portfolio-grade Flutter messaging application inspired by modern messaging platforms.

Users can create accounts, discover other users by username, send messages and media, create groups, share locations, post stories, use AI-assisted communication features, and make 1-to-1 audio and video calls.

The project is built with **Flutter + Supabase**, with Riverpod-based state management, PostgreSQL-backed data, realtime updates, media storage, location services, AI integrations, and WebRTC calling.

---

## ✨ Overview

Wisp brings several communication features together in one application:

### 💬 Messaging

* 1-to-1 conversations
* Group chats
* Text messages
* Image sharing
* Video sharing
* Voice notes
* Document sharing
* Contact sharing
* Message delivery/read states
* Typing indicators
* Online/offline presence

### 🤖 AI Features

* Realtime message translation
* Embedded AI assistant
* `@wisp` mentions inside conversations
* Voice note transcription
* Voice action extraction

### 📍 Communication Tools

* Current location sharing
* Live location sharing
* 24-hour stories/status
* Audio calling
* Video calling

---

## 💬 Messaging Flow

```text
Find User
    ↓
Open Conversation
    ↓
Send Message
    ↓
Realtime Delivery
    ↓
Delivered / Read
```

Wisp uses realtime backend updates so conversations can react to new messages, message changes, typing state, presence, and other communication events.

---

## 🚀 Core Features

### Authentication & User Discovery

* Email/password authentication
* Username-based user discovery
* User profiles
* Avatar support
* Preferred language selection
* Persistent authentication state

### Chat

* 1-to-1 conversations
* Group conversations
* Admin/member roles
* Text messaging
* Image messages
* Video messages
* Voice notes
* Documents
* Contact sharing
* Delivery/read receipts
* Typing indicators
* Online presence

### Stories

* 24-hour photo/video stories
* Story captions
* Story viewing
* Story view tracking
* Automatic story expiry

### Location

* Current device location
* Live location sharing
* Location updates
* Reverse geocoding
* Map-based location previews

### Calling

* 1-to-1 audio calls
* 1-to-1 video calls
* WebRTC peer connections
* Camera/microphone controls
* Speaker routing
* Call signaling through Supabase Realtime

---

## 🤖 AI

Wisp includes AI directly inside the communication experience.

### Translation

Messages can be translated based on the recipient's preferred language while keeping the original message available.

### AI Assistant

The built-in Wisp AI can be used through a direct conversation or by mentioning `@wisp` inside a chat.

The assistant can use recent conversation context when generating responses.

### Voice Intelligence

Voice notes can be processed into:

```text
Voice Note
    ↓
Transcription
    ↓
Action Extraction
```

The AI layer uses Gemini as the primary provider with Groq available as a fallback for supported operations.

---

## 🏗️ Architecture

Wisp follows a feature-oriented Flutter architecture.

```text
lib/
├── core/
├── config/
├── features/
│   ├── auth/
│   ├── chat/
│   ├── groups/
│   ├── contacts/
│   ├── stories/
│   ├── calls/
│   ├── ai_agent/
│   ├── translation/
│   ├── voice_notes/
│   ├── location/
│   └── profile/
├── models/
├── widgets/
└── main.dart
```

The application separates shared infrastructure from domain-specific features so areas such as messaging, calling, AI, stories, and location can evolve independently.

---

## 🧰 Tech Stack

| Layer            | Technology                            |
| ---------------- | ------------------------------------- |
| Mobile framework | Flutter                               |
| Language         | Dart                                  |
| State management | Riverpod                              |
| Navigation       | go_router                             |
| Backend          | Supabase                              |
| Database         | PostgreSQL                            |
| Authentication   | Supabase Auth                         |
| Realtime         | Supabase Realtime                     |
| Storage          | Supabase Storage                      |
| AI               | Gemini API                            |
| AI fallback      | Groq API                              |
| Calling          | WebRTC                                |
| Location         | Geolocator                            |
| Maps             | flutter_map                           |
| Geocoding        | Nominatim / OpenStreetMap             |
| Image handling   | Image Picker + flutter_image_compress |
| Documents        | File Picker                           |
| Video playback   | video_player                          |
| Voice recording  | record                                |
| Audio playback   | just_audio                            |
| Audio session    | audio_session                         |

---

## 🔐 Backend

Wisp uses Supabase as its backend platform.

The backend is responsible for:

* Authentication
* User profiles
* Conversations
* Group membership
* Messages
* Message status
* Stories
* Story views
* Calls
* Realtime events
* Media storage

This allows the application to operate with real backend data instead of relying on hardcoded demo content.

---

## ⚡ Realtime

Supabase Realtime is used across communication-heavy parts of the application.

Realtime behavior includes:

* New message events
* Message updates
* Message deletion
* Typing state
* User presence
* Call state
* Live location updates

The chat layer uses conversation-scoped realtime events so active conversations can react to relevant changes without treating the entire message history as one constantly refreshed dataset.

---

## 📍 Location & Media

Wisp uses device location services for current and live location sharing.

The application also supports media uploads for:

* Images
* Videos
* Voice notes
* Documents
* Stories
* Profile avatars

Chat media is stored through Supabase Storage and handled through the application's media layer.

---

## 🔒 Security

Environment-specific configuration should be provided through a local `.env` file.

Example:

```env
SUPABASE_URL=your_supabase_url
SUPABASE_ANON_KEY=your_supabase_anon_key

GEMINI_API_KEY=your_gemini_api_key
GROQ_API_KEY=your_groq_api_key

TURN_URL=your_turn_server_url
TURN_USERNAME=your_turn_username
TURN_CREDENTIAL=your_turn_credential
```

Never commit real API keys, private credentials, service-role keys, or unrestricted third-party credentials.

---

## 🛠️ Local Development

### Prerequisites

* Flutter SDK
* Dart SDK
* Android Studio / Android SDK
* A Supabase project
* Gemini API configuration
* Groq API configuration
* TURN/STUN configuration for calling

### 1. Clone the repository

```bash
git clone https://github.com/Abdul-Mueez-init/Wisp.git
cd Wisp
```

### 2. Install dependencies

```bash
flutter pub get
```

### 3. Configure environment variables

Create a local `.env` file with the required Supabase, AI, and calling configuration.

Do not commit this file.

### 4. Run the application

```bash
flutter run
```

---

## 📁 Project Structure

```text
Wisp/
├── android/
├── ios/
├── lib/
│   ├── core/
│   ├── config/
│   ├── features/
│   ├── models/
│   ├── widgets/
│   └── main.dart
├── assets/
├── test/
├── pubspec.yaml
├── .gitignore
└── README.md
```

---

## 🎯 Project Goals

Wisp was built as a portfolio project to demonstrate a full-stack, realtime Flutter application with integrated AI and communication features.

The project focuses on demonstrating:

* Cross-platform Flutter development
* Feature-based architecture
* Riverpod state management
* Supabase integration
* Realtime application behavior
* Authentication and user discovery
* Rich messaging workflows
* Media handling
* Location-aware features
* AI integration
* WebRTC calling

---

## 📌 Project Status

Wisp is a portfolio project with the core application experience built around realtime messaging, AI features, media sharing, stories, location sharing, and 1-to-1 calling.

Some integrations may require environment-specific configuration before deployment.

---

## 🔮 Future Improvements

Potential future development includes:

* Push notifications
* Message reactions
* Advanced chat search
* Expanded privacy controls
* Improved notification handling
* Additional AI workflows
* Production-grade calling infrastructure
* Release automation

---

## 👨‍💻 Author

**Abdul Mueez**

Computer Science student and Flutter developer building full-stack mobile applications.

GitHub:

https://github.com/Abdul-Mueez-init

---

## 📄 License

This project is currently maintained as a personal portfolio project.
