<div align="center">
  <img src="assets/icon/icon.png" width="120" alt="PlanMate Logo">
  <h1>PlanMate: The Intelligent AI Scheduler</h1>
  <p><b>Transform chaotic thoughts into a perfectly orchestrated day.</b></p>

  <a href="https://github.com/pranavdawara-py/planMate-lastMinuteSaver/releases/latest">
    <img src="https://img.shields.io/badge/Download-APK-blue?style=for-the-badge&logo=android" alt="Download APK">
  </a>
</div>

<br/>

## 🚀 What is PlanMate?
Traditional calendar apps force you to manually click, drag, and set times for every single task. **PlanMate** is a next-generation AI scheduling assistant that lets you plan your entire day using natural language. 

Just tell PlanMate what you need to do, and it will intelligently extract the tasks, calculate durations, organize them into categories, and set strict Full-Screen Alarms to keep you on track.

## ✨ Core Features (The "Wow" Factor)

### 🧠 1. Intelligent Natural Language Parsing
Type a single paragraph containing multiple tasks, relative times (e.g., *"in 2 hours"*), and exact times. PlanMate's AI instantly breaks it down into a structured schedule.

### 🔄 2. Dynamic Conversational Rescheduling
Meetings run late? Plans change? Just tell the chatbot: *"Push my coding session back by 15 minutes."* The AI understands the context, finds the existing task, and mathematically shifts your schedule without you having to touch a single form field.

### ⏰ 3. Premium Full-Screen Alarms
No more easily-ignored tray notifications. When a strict task is due, PlanMate triggers a stunning, pulsing **Full-Screen Alarm UI** that locks over your screen and forces you to acknowledge your commitment. 

### 🗂️ 4. Multi-Session Task Management
Tell the AI to *"Schedule deep work for 1 hour now, and 2 hours tonight."* It automatically creates a single task tracked across multiple separate time sessions, managing the alarms for both independently.

---

## 🛠️ Testing the Magic (Demo Prompts)

Want to see the power of PlanMate? Install the APK and try typing these exact prompts into the AI Chatbot:

**The Complex Organizer:**
> *"Schedule a 'Quick Sync' meeting starting exactly at 15:20 for 10 minutes, and set a strict alarm reminder for it so I don't miss it. Next, add a 'Product Strategy' task with two different sessions: the first session starting 30 minutes from now for 60 minutes, and the second session exactly at 18:00 for 2 hours. Just set standard notifications for the strategy sessions."*

**The Contextual Rescheduler:**
> *"That sync ran slightly over. Push my entire 'Product Strategy' task back by exactly 10 minutes, and upgrade the reminder for its first session to a strict alarm so I jump right into it!"*

---

## 📥 Installation

1. Navigate to the **[Releases](https://github.com/pranavdawara-py/planMate-lastMinuteSaver/releases)** tab.
2. Download `planMate.apk`.
3. Transfer it to your Android device and tap to install.
4. **Important:** For the Full-Screen Alarms to work perfectly, please ensure PlanMate has `Display over other apps` and `Alarms & Reminders` permissions granted in your Android settings!

---

## 💻 Tech Stack
- **Frontend:** Flutter & Dart (Cross-platform UI)
- **AI Brain:** Google Gemini API (Natural Language Parsing & Intent Extraction)
- **Local Database:** Hive (Fast NoSQL on-device storage)
- **Scheduling Engine:** `alarm` package (Reliable background execution)
