# Backend Deployment Implementation Plan
## planMate — Vibe2Ship Hackathon, Deadline: June 29, 2026 2:00 PM

---

## First: Your Question About Google AI Studio

**You asked:** "Can Google AI Studio build in Flutter? Can we upload our files and deploy from there since those file types are also used in React?"

**Honest answer — NO, this won't work for us:**

- Google AI Studio's "Build" mode generates **React (TypeScript) + Node.js** apps from scratch via natural language prompts. It cannot ingest your existing Flutter/Dart codebase.
- Even if you upload `.dart` files — AI Studio won't treat them as a React project. The file formats are completely different: React uses `.tsx`/`.jsx`, Flutter uses `.dart`. They are not interchangeable.
- AI Studio's deployment button deploys **its own generated React code** to Cloud Run, not your existing code.

**What AI Studio CAN do for us:** Nothing useful for deployment. We already have a working Node.js backend (`backend/index.js`) — we just need to deploy it to Cloud Run directly using `gcloud CLI`. That's simpler and more reliable.

---

## What Actually Needs to be Deployed

We have **two things** to deploy:

| Thing | What it is | Where to deploy |
|---|---|---|
| `backend/index.js` | Node.js Express server — holds Gemini API key, proxies AI calls | **Google Cloud Run** (GCP free tier) |
| Flutter app (web build) | Static files: HTML/JS/CSS from `flutter build web` | **Firebase Hosting** (free tier, same Firebase project) |

The Android APK doesn't need deployment — it's uploaded to GitHub Releases.

---

## Why Cloud Run is Correct for the Backend (Confirmed)

- **Free tier:** 2 million requests/month + 180,000 vCPU-seconds free. We'll use maybe 1,000 requests for the hackathon — completely free.
- **Scales to zero:** When no requests come in, you pay nothing.
- **Billing account required:** Yes — you MUST link a credit card/billing account, BUT you will NOT be charged as long as you stay within the free tier. Set a $0 budget alert and Google will email you before any charge.
- **Our backend is ready:** `backend/index.js` already runs on port `process.env.PORT` (Cloud Run sets this automatically) and reads `GEMINI_API_KEY` from env vars. No changes needed.
- **No Docker needed:** `gcloud run deploy --source .` handles containerization automatically using Google's buildpacks.

---

## Final Architecture

```
Android APK (primary deliverable)
        ↓ (user installs)
planMate Flutter App
        ↓ POST /chat
Cloud Run: Node.js Gemini Proxy      ← DEPLOY THIS (backend/)
        ↓
Gemini API (gemini-2.5-flash, Google AI Studio key)

Flutter Web Build (flutter build web)
        ↓
Firebase Hosting                     ← DEPLOY THIS (build/web/)
        ↓
Judges open the web link in browser

Firebase Auth + Firestore            ← already wired, just needs Console setup
```

---

## Phase 1 — Set Up Google Cloud (ONE-TIME SETUP, ~15 min)

### 1.1 Install gcloud CLI
Download from: https://cloud.google.com/sdk/docs/install
```
(Windows) Run the installer → restart terminal
```

### 1.2 Login and configure
```powershell
gcloud auth login
# Opens browser — sign in with your Google account (same one as Firebase)

gcloud config set project planmate-3113b
# planmate-3113b is your existing Firebase project ID
```

### 1.3 Enable Cloud Run API
```powershell
gcloud services enable run.googleapis.com
```

### 1.4 Link a Billing Account (REQUIRED — won't charge you)
- Go to: https://console.cloud.google.com/billing
- Link any credit/debit card
- Then go to: Budgets & Alerts → Create Budget → set to $1 → you get an email before any charge
- **Expected actual cost: $0.00** (2M free requests/month, we'll use <1,000)

---

## Phase 2 — Deploy Node.js Backend to Cloud Run (~10 min)

### 2.1 Ensure CORS allows your Firebase Hosting domain
In `backend/index.js`, line 19, the `ALLOWED_ORIGIN` env var handles this.
**No code changes needed** — we'll set it as an env var during deploy.

### 2.2 Deploy using gcloud (no Docker, no Dockerfile needed)
```powershell
cd C:\Users\prana\Downloads\planMate\backend

gcloud run deploy planmate-gemini-proxy `
  --source . `
  --platform managed `
  --region asia-south1 `
  --allow-unauthenticated `
  --set-env-vars "GEMINI_API_KEY=YOUR_ACTUAL_KEY_HERE" `
  --memory 256Mi `
  --max-instances 3
```

> **Why `asia-south1` (Mumbai)?** Closest region to India = lower latency for you.

### 2.3 Note your Cloud Run URL
After deploy completes, you get:
```
https://planmate-gemini-proxy-xxxx-el.a.run.app
```
Save this URL.

### 2.4 Test it
```powershell
curl https://planmate-gemini-proxy-xxxx-el.a.run.app/
# Should return: {"status":"Last Minute Life Saver API is running"}
```

---

## Phase 3 — Update Flutter App to Use Deployed Backend (~5 min)

### 3.1 Update `assets/.env`
```
PROXY_URL=https://planmate-gemini-proxy-xxxx-el.a.run.app
WEB_PROXY_URL=https://planmate-gemini-proxy-xxxx-el.a.run.app
```

Both point to Cloud Run. The `kIsWeb` switch in `gemini_service.dart` handles which one to use automatically.

### 3.2 Remove `android:usesCleartextTraffic` restriction (optional)
In `AndroidManifest.xml`, the `usesCleartextTraffic="true"` flag was needed for local HTTP testing. With Cloud Run (HTTPS), it's not needed but also doesn't hurt — leave it.

---

## Phase 4 — Fix Web Compatibility for Flutter Web Build (~30 min)

The Claude plan had this right. Several packages crash on Flutter Web because they use native Android APIs. All are already guarded with `kIsWeb` checks in our codebase, but verify:

### 4.1 Check packages are guarded (already done in our code)
- `notification_service.dart` — all calls wrapped with `if (kIsWeb) return` ✅
- `background_service.dart` — verify same
- `main.dart` — verify notification/background init skipped on web

### 4.2 Test locally
```powershell
cd C:\Users\prana\Downloads\planMate
flutter run -d chrome
```
Fix any crashes. Common issues:
- `Hive.initFlutter()` — works on web via IndexedDB, no changes needed
- `flutter_tts` — guarded by `kIsWeb` already
- `alarm` package — guarded already

---

## Phase 5 — Deploy Flutter Web to Firebase Hosting (~15 min)

### 5.1 Build web release
```powershell
cd C:\Users\prana\Downloads\planMate
flutter build web --release
```
Output in: `build\web\`

### 5.2 Install Firebase CLI (if not installed)
```powershell
npm install -g firebase-tools
firebase login
```

### 5.3 Initialize Firebase Hosting (one-time)
```powershell
firebase init hosting
```
When prompted:
- Project: select `planmate-3113b`
- Public directory: `build/web`
- Single-page app: **Yes**
- Overwrite index.html: **No**

### 5.4 Update CORS in backend for your Firebase domain
Once you know your Firebase Hosting URL (e.g. `https://planmate-3113b.web.app`), redeploy backend with:
```powershell
gcloud run deploy planmate-gemini-proxy `
  --source . `
  --region asia-south1 `
  --update-env-vars "ALLOWED_ORIGIN=https://planmate-3113b.web.app"
```

### 5.5 Deploy to Firebase Hosting
```powershell
firebase deploy --only hosting
```
Your app is now live at: `https://planmate-3113b.web.app`

---

## Phase 6 — Enable Firebase Auth + Firestore in Console (~10 min)

1. Go to: https://console.firebase.google.com/project/planmate-3113b
2. **Authentication** → Get Started → Email/Password → Enable → Save
3. **Firestore Database** → Create database → Start in production mode → Region: `asia-south1`
4. **Firestore Rules** (for basic security):
```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId}/{document=**} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

---

## Phase 7 — Android APK + GitHub Release (~15 min)

### 7.1 Build APK
```powershell
flutter build apk --release
```
Output: `build\app\outputs\flutter-apk\app-release.apk`

### 7.2 Push code to GitHub
```powershell
git add .
git commit -m "feat: production deployment ready"
git remote add origin https://github.com/YOUR_USERNAME/planmate.git
git push -u origin master
```

### 7.3 Create GitHub Release
- GitHub → your repo → Releases → Draft a new release
- Tag: `v1.0.0`
- Title: `planMate v1.0.0 — Vibe2Ship Hackathon`
- Upload: `app-release.apk` (rename to `planMate.apk`)
- Publish release

---

## Summary: What Changes vs Claude's Old Plan

| Topic | Claude's Plan | Actual Correct Plan |
|---|---|---|
| Backend deploy | Cloud Run (correct) | Cloud Run — same, but use `asia-south1` (India) for lower latency |
| Flutter code changes | Replace GeminiService entirely | NO — just update `assets/.env` with Cloud Run URL. GeminiService already reads from .env |
| `.env` handling | Remove dotenv, hardcode URL | Keep dotenv — just update the URL values in `assets/.env` |
| Google AI Studio deploy | Not mentioned | Cannot deploy our Flutter app — ignore this idea |
| CORS | Not addressed | Must add Firebase Hosting URL as `ALLOWED_ORIGIN` env var on Cloud Run |
| Region | `us-central1` | `asia-south1` (Mumbai) — better latency for India |

---

## Deployment Order (Time estimate: ~1.5 hours total)

```
1. Install gcloud CLI + login + link billing        ~15 min
2. Deploy backend to Cloud Run                       ~10 min
3. Update assets/.env with Cloud Run URL             ~2 min
4. Test AI chat works on physical device             ~5 min
5. Fix web compatibility issues                      ~30 min (variable)
6. flutter build web → firebase deploy hosting       ~15 min
7. Enable Firebase Auth + Firestore in console       ~10 min
8. flutter build apk → GitHub Release                ~10 min
9. Submit on BlockseBlock                            ~5 min
```

---

> [!IMPORTANT]
> The billing account is mandatory for Cloud Run but you will NOT be charged.
> Set a $1 budget alert in Google Cloud Billing → you get emailed before any charge happens.
> Expected cost: **$0.00**

> [!NOTE]
> **Do NOT use Google AI Studio's "Build" mode for deployment.**
> It builds React apps from scratch via prompts — it cannot ingest our existing Flutter/Dart code.
> Our `backend/index.js` deploys directly to Cloud Run in one command.
