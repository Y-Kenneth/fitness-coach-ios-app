# FitnessCoach (FitCoach) — App Overview

**Last updated:** 2026-05-18
**Platform:** iOS 16+ (SwiftUI)
**Architecture:** Native iOS app + Flask backend on Mac + Ollama LLM on Windows laptop

---

## 1. What the app does

FitnessCoach is a personal fitness companion that combines four ideas into one iOS app:

1. **Workout library** — browse a catalogue of strength/cardio/flexibility workouts, filter by muscle group, start a guided session, and complete it on-device.
2. **Apple HealthKit integration** — reads the user's real fitness data (steps, calories, workouts, heart rate, exercise minutes, sleep) and writes completed workout calories back to Apple Health.
3. **AI Coach** — sends the user's real 7-day HealthKit snapshot to a local AI server (CrewAI orchestrating 3 LLM agents on Ollama) for personalized analysis and recommendations.
4. **Form Check (camera + pose detection)** — uses Apple's Vision framework to overlay a real-time skeleton on the camera feed, intended as a base for future rep-counting / form-correction features.

---

## 2. Three-machine architecture

The AI Coach feature relies on a small distributed setup:

```
┌──────────────────┐      ┌──────────────────┐      ┌────────────────────┐
│    iPhone /      │POST  │   Mac (Flask)    │HTTP  │  Windows laptop    │
│    Simulator     ├─────▶│   server.py      ├─────▶│  Ollama            │
│   (SwiftUI)      │JSON  │   :5001          │      │  gemma4:latest     │
│                  │◀─────│                  │◀─────│  :11434            │
└──────────────────┘      └──────────────────┘      └────────────────────┘
       HealthKit                CrewAI agents              Local LLM
       snapshot                 (3 sequential)             inference
```

- **iPhone** gathers a 7-day HealthKit snapshot, sends it as JSON to Flask.
- **Mac (Flask)** receives the snapshot, builds a fresh CrewAI crew with task descriptions tailored to the user's actual numbers, calls Ollama via litellm.
- **Windows (Ollama)** runs `gemma4:latest` locally — no cloud, no API keys.
- **Response** flows back: structured JSON with per-agent outputs, run metadata, and the original snapshot echoed for the iOS UI.

### URL strategy (set once, never edit again)

`A2ACoachingView.swift` picks the right host at compile time:

- **Simulator** → `http://127.0.0.1:5001` (loopback, ignores VPN/WiFi state)
- **Physical iPhone** → `http://30s-iMac.local:5001` (Bonjour follows the Mac across IP changes; iPhone must be on the same WiFi)

---

## 3. Feature-by-feature

### 3.1 Home tab (`HomeView`)
- Personalized greeting banner with weekly goal progress
- 2×2 grid of weekly stat cards: Workouts, Calories, Time, Goal completion
- Horizontal "Quick Start" scroller of suggested workouts
- Form Check call-to-action (camera + pose detection)

### 3.2 Workouts tab (`WorkoutListView` → `WorkoutDetailView` → `ActiveSessionView`)
- Filterable workout list (chips for muscle groups)
- Detail view with exercise breakdown, sets, reps, difficulty
- Active session view runs a guided workout flow and writes results back to HealthKit

### 3.3 Progress tab (`FitnessProgressView`)
- Weekly bar chart of activity (`WeeklyBarChartView`)
- Chronological session history with date column, name, duration, calories

### 3.4 Health tab (`HealthDashboardView`)
- HealthKit permission gate (`ConnectHealthView` → `PermissionDeniedView` → authorized content)
- Today's active-calorie card with goal ring
- FitCoach all-time calories summary
- Entry point that opens the AI Coach as a sheet

### 3.5 AI Coach (`A2ACoachingView`, sheet from Health tab)
The signature feature. Five distinct UI states:

1. **Ready to Run** — animated gradient hero, "Meet your crew" preview of the 3 AI agents, big gradient Start button.
2. **Loading** — concentric pulsing rings + rotating sparkle + stage indicator cycling through "Designer drafting → Health analyst crunching → QA reviewing → Polishing."
3. **Live Result** — angular-gradient hero banner with LIVE pill + metadata pills (duration, agent count, model), per-agent expandable cards (avatars, role, task, markdown-rendered output), real-data "This Week" stat cards, "Daily Breakdown" rows.
4. **Cached Sample** — same layout as Live but with a "CACHED" pill and orange-themed banner.
5. **Coach Unavailable (error)** — orange wifi-exclamation icon with Try Again button, shown only when a live run fails AND no cached data is available.

### 3.6 Profile tab (`ProfileView`)
- Avatar (gradient circle with initial), name, fitness level, BMI
- Editable personal info (name, age, height, weight)
- Fitness goals (level picker, weekly goal stepper, daily calorie goal stepper)
- All-time stats summary

### 3.7 Form Check (`PoseDetectionView`)
- Full-screen camera with Apple Vision pose detection
- Real-time 2D skeleton overlay
- Front/back camera toggle
- Currently a foundation — no rep counting or form scoring yet

---

## 4. Project structure

```
FitnessCoachApp/
├── FitnessCoachAppApp.swift         # @main entry point
├── ContentView.swift                # TabView shell (5 tabs)
├── Models/
│   ├── Workout.swift                # Workout + Difficulty + MuscleGroup
│   ├── Exercise.swift               # Single exercise (sets, reps)
│   ├── WorkoutSession.swift         # A completed session
│   └── UserProfile.swift            # Persisted user profile
├── ViewModels/
│   ├── WorkoutViewModel.swift       # Workout list, session lifecycle
│   ├── ProfileViewModel.swift       # Profile persistence
│   ├── HealthDashboardViewModel.swift
│   └── PoseDetectionViewModel.swift # AVFoundation + Vision pipeline
├── Services/
│   ├── HealthDataProvider.swift     # Protocol
│   ├── LiveHealthDataProvider.swift # Real HealthKit reader/writer
│   ├── MockHealthDataProvider.swift # Seeded weekly data for simulator
│   └── HealthSnapshot.swift         # Codable 7-day rollup model
├── Shared/
│   ├── AppConstants.swift           # Design tokens (spacing, corners, colors, animation)
│   └── EmptyStateView.swift         # Reusable empty state
└── Views/
    ├── Home/
    ├── Workouts/
    ├── Progress/
    ├── Health/
    ├── Coaching/                    # A2ACoachingView (AI Coach)
    ├── Profile/
    └── PoseDetection/

CrewAI/                              # Python backend on Mac
├── agents.py                        # 3 CrewAI agents + build_fitness_crew(snapshot)
├── server.py                        # Flask /health + /run endpoints
└── README_SERVER.md

AppleHealthAgent/
└── mock_response.json               # Cached A2A response for offline demo
```

---

## 5. Backend details

### CrewAI agent crew (`CrewAI/agents.py`)
Three sequential agents, each running on `ollama/gemma4:latest`:

| Agent | Role | Emoji | Task |
|---|---|---|---|
| `ui_agent` | iOS UI Designer | 🎨 | Suggests 3 concrete SwiftUI UI improvements, informed by user's activity |
| `healthkit_agent` | HealthKit Data Analyst | 💪 | Analyzes the real 7-day data, gives personalized coaching message + recommendation |
| `qa_agent` | iOS QA Engineer | 🧪 | Reviews UI + HealthKit outputs, produces final approved summary |

The function `build_fitness_crew(snapshot)` is called per-request from `server.py`, interpolating the user's real numbers into the task descriptions so the AI references concrete data rather than fabricating it.

### Flask server (`CrewAI/server.py`)
- `GET /health` → `{"status": "ok"}` for connectivity checks
- `POST /run` → reads JSON body (a HealthSnapshot), kicks off the crew, returns:
  - `result.agent_outputs[]` — per-agent role, emoji, task description, raw output
  - `result.run_metadata` — duration, agent count, model name, data source
  - `result.artifacts[]` — real weekly totals + per-day entries from the snapshot
  - `result.status` — state + timestamp

iOS-side request session uses a custom `URLSession` with 600s timeouts because CrewAI runs typically take 2–5 minutes on local hardware.

---

## 6. HealthKit data flow

`HealthSnapshot` (`FitnessCoachApp/Services/HealthSnapshot.swift`) is a Codable 7-day rollup with:

- `period_start` / `period_end` (yyyy-MM-dd)
- `daily_entries[]` — 7 entries with: date, steps, active kcal, resting kcal, exercise minutes, avg heart rate, workout count, sleep hours
- `weekly_totals` — totals, daily averages, avg resting HR, avg sleep, goal kcal/day
- `data_source` — `"healthkit"`, `"mock"`, or `"empty"`

The view model's `gatherHealthSnapshot()` tries live HealthKit first; falls back to `MockHealthDataProvider`'s seeded weekly data if HealthKit is empty (simulator). This is what makes the demo work on both environments without code changes.

Permissions requested (Info.plist `NSHealthShareUsageDescription`):
- Active energy burned, basal energy burned
- Steps, exercise time
- Heart rate
- Workouts
- Sleep analysis

Write permission: active energy (workout calorie burns).

---

## 7. Current state & known limitations

**Working today:**
- ✅ End-to-end HealthKit → Flask → CrewAI → iOS roundtrip
- ✅ Simulator + physical iPhone parity
- ✅ Per-agent output rendering with markdown
- ✅ Animated, multi-state AI Coach UI
- ✅ HealthKit read/write for active calories
- ✅ Vision-based pose skeleton overlay

**Known gaps / future work:**
- Form Check is a skeleton overlay only — no rep counting, no form scoring
- Pose detection currently shown only as a "Beta" entry point on Home
- No onboarding flow — fields default to a sample profile
- No iCloud / cross-device sync
- Mock data is seeded once per session — varies on each launch but not within a session
- No tests yet
- LiteLLM logging emits a harmless `email_validator` traceback after each /run (cosmetic only — fix is `pip install "pydantic[email]"`)

---

## 8. Design tokens (`AppConstants.swift`)

| Token type | Values |
|---|---|
| **Spacing** | xs=4, sm=8, md=16, lg=24, xl=32 |
| **CornerRadius** | sm=8, md=12, lg=16, xl=24 |
| **Colors** | `primary` (AccentColor asset), `cardBackground` (secondarySystemGroupedBackground), `pageBackground` (systemGroupedBackground) |
| **Animation** | `standard` (easeInOut 0.3s), `spring` (response 0.4 / damping 0.75) |
| **Tap targets** | `MinTapSize.standard` = 44pt |

The visual palette across the app leans on **blue → purple → pink gradients**, with secondary accents in orange (calories/energy), green (goal-met/success), yellow (totals), and red (advanced difficulty). Cards use the system grouped-background tone for automatic light/dark adaptation.
