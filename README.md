# PlanMate — AI Chatbot Assisted Productivity App

> **The Last-Minute Life Saver** · Built for the Google AI Studio Hackathon

PlanMate is an AI-powered mobile productivity companion that helps students, professionals, and entrepreneurs plan, prioritize, and complete tasks before deadlines are missed. Instead of manual data entry, users simply chat in natural language and PlanMate automatically extracts tasks, schedules them into a visual timeline, and sets hardware-level alarms.

---

## ?? Download

**[? Download Latest APK](https://github.com/pranavdawara-py/planMate-lastMinuteSaver/releases/latest)**

---

## ? Key Features

- **Conversational Task Extraction** — Chat naturally with the AI to instantly generate structured tasks and schedule blocks
- **Visual Daily Timeline** — Dynamic scrollable timeline that organizes tasks alongside fixed schedule events
- **Intelligent Recurrence** — Daily, weekly, and monthly recurring tasks that auto-generate next occurrences on completion
- **Context-Aware Alarms** — Hardware-level background alarms and notifications that fire reliably even when the app is closed
- **Offline-First** — Fully functional without internet using local Hive database
- **Cloud Sync** — Firebase-powered cross-device sync for logged-in users

---

## ?? Tech Stack

| Layer | Technology |
|---|---|
| Mobile App | Flutter & Dart |
| Local Storage | Hive (NoSQL) |
| State Management | Provider |
| Backend Proxy | Node.js & Express on **Google Cloud Run** |
| AI Engine | **Google Gemini API** |
| Authentication | **Firebase Auth** |
| Cloud Database | **Cloud Firestore** |

---

## ?? Google Technologies

1. **Google Gemini API** — Core AI for natural language task extraction
2. **Google Cloud Run** — Secure backend proxy hosting
3. **Firebase Authentication** — User sign-up and login
4. **Cloud Firestore** — Real-time cloud sync

---

## ?? Running Locally

```bash
git clone https://github.com/pranavdawara-py/planMate-lastMinuteSaver.git
cd planMate-lastMinuteSaver
# Create assets/.env from the example and fill in your backend URL
cp backend/.env.example assets/.env
flutter pub get
flutter run
```

---

## ?? Security Note

API keys are stored in `.env` files excluded from this repository. The backend proxy on Google Cloud Run secures the Gemini API key — the Flutter app never holds it directly. See `backend/.env.example` for the required environment variable template.

---

*Built with Flutter + Google AI Studio*
