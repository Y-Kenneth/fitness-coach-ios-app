# FitnessCoach — Design Brief for Claude Design

> **Purpose of this document**
> This brief is being handed to **Claude Design** so it can propose a complete, fresh visual language for the FitnessCoach iOS app. The current UI was built quickly while wiring up backend functionality; it works, but it looks "AI-generated default." The goal is a redesign that feels intentional, premium, and emotionally resonant — without changing what the app *does*.
>
> **You have permission to break from current patterns.** Treat existing colors, layouts, and components as functional sketches, not constraints. The information architecture (which screens exist, what data each contains) is fixed; everything visual is open.

---

## 1. Who this is for

A solo developer building their first major iOS app as a university project. The end users are **fitness-conscious people aged 18–35** who already wear an Apple Watch or track activity on their iPhone — they're not beginners to the genre, and they have higher visual standards than typical productivity-app users because they live inside apps like Apple Fitness+, Strava, and Nike Training Club.

The app needs to **demo well in front of a university lecturer** who will compare it to industry-standard fitness apps. Looking premium is part of the grade.

---

## 2. What the app does (information architecture — fixed)

Five tabs:

| Tab | Purpose | Primary content |
|---|---|---|
| **Home** | Daily entry point + motivation | Greeting + weekly progress hero, stat grid (4 weekly stats), horizontal carousel of suggested workouts, Form Check (camera) CTA |
| **Workouts** | Browse + start workouts | Filter chips (muscle group), list of workouts, detail view per workout, active session player |
| **Progress** | History + trends | Weekly bar chart, chronological session history |
| **Health** | Apple Health integration | Permission gate, today's active calories vs. goal, all-time calories, AI Coach entry point |
| **Profile** | User identity + settings | Avatar, personal info (name/age/height/weight), fitness goals, all-time stats |

**Modal / push experiences:**
- **AI Coach** (sheet from Health tab) — multi-state, the signature feature
- **Active workout session** (sheet) — guided exercise flow with timer
- **Form Check** (full-screen) — camera + 2D skeleton overlay

---

## 3. The AI Coach — the signature screen

This is the screen that **must look the most impressive** because it's what makes the app different from "just another workout tracker." The user taps Run, waits 2–5 minutes (a real local LLM is thinking), and receives a structured report from 3 AI agents.

The screen has **five distinct states**, each a design challenge:

| State | Current behavior | What it should feel like |
|---|---|---|
| **Ready to Run** | Static gradient hero + agent list + Start button | Inviting, calm, "your crew is here" — like opening a session with a personal trainer |
| **Loading** | Pulsing rings + rotating sparkle, cycles through stages | Anticipation, not boredom — the user is waiting minutes, the screen needs to reward patience |
| **Live Result** | Hero banner + per-agent expandable cards + stat grid + daily breakdown | Celebratory, premium, "this report was made just for you" — feels like a postcard, not a dashboard |
| **Cached Sample** | Same as Live but with CACHED pill | Honest but not apologetic — clearly differentiated from a real run |
| **Coach Unavailable** | Orange wifi-exclamation icon + Try Again button | Warm and reassuring, not alarming — this is a local-network hiccup, not a disaster |

Each agent has identity:
- 🎨 **iOS UI Designer** — playful, creative
- 💪 **HealthKit Data Analyst** — confident, analytical
- 🧪 **iOS QA Engineer** — precise, calm

These personalities could translate to color, typography, motion, or avatar treatment — your call.

---

## 4. Mood & vibe direction

Pick a direction that feels coherent across all 5 tabs + AI Coach. The brief is open, but here are anchors:

**Words that should describe the final design:**
- Premium
- Motivational (not aggressive)
- Calm-but-alive (gentle motion, not static)
- Trustworthy (this app reads private health data)
- Personal (the user feels seen)
- Confidently modern (not trend-chasing)

**Words that should NOT describe it:**
- Sterile / corporate
- Bootcamp-aggressive ("PUSH HARDER!!!")
- Gamified with badges and confetti
- Overly playful / cartoonish
- Generic SaaS dashboard

---

## 5. Reference territory

Take inspiration from — but don't copy — these aesthetic territories:

- **Apple Fitness+ rings** — the celebratory data viz, the way numbers feel like achievements
- **Strava activity cards** — clean hierarchy, premium photography energy without using photos
- **Nike Training Club** — bold typography for workout names
- **Headspace / Calm** — the soft gradient palette and how loading states feel like a moment, not a wait
- **Linear / Things 3** — restrained, design-system-driven, no decoration without purpose

**Anti-references:**
- MyFitnessPal (too cluttered, too utilitarian)
- Default iOS Settings (too system-grey)
- Anything that screams "fitness bro" (loud reds, screaming serifs, dumbbell silhouettes everywhere)

---

## 6. Visual constraints (the few hard rules)

These exist because of the platform, not personal preference:

1. **iOS-native feel.** Tab bar at bottom, large titles, system gestures. Don't redesign navigation chrome.
2. **Light + dark mode parity.** Both modes must be first-class. Lean dark-mode-first if you have to pick, since fitness apps are often used in low light.
3. **44pt minimum tap targets** for accessibility.
4. **Dynamic Type support** — no hard-coded font sizes that break at accessibility sizes.
5. **No reliance on photography.** This is a solo project; we can't license stock fitness photos. Lean into typography, gradients, icons, illustrations, or generated patterns.
6. **SF Symbols welcome.** Apple's icon set is free and looks native; custom icons are optional.
7. **Markdown rendering matters.** The AI Coach output is Markdown (bold, lists, headers). The typography needs to handle it gracefully.

Everything else — color palette, type system, corner radii, motion language, card treatments — is open.

---

## 7. Components that need a design language

Whatever direction you pick, these recurring components need to feel like a family:

- **Stat card** (icon + big number + unit + label) — used on Home and AI Coach result
- **Progress ring / bar** (today's calories vs. goal, weekly bar chart)
- **List row** (workout list, session history)
- **Filter chip** (muscle group filters)
- **Hero card** (gradient banner with personalized message + progress)
- **Agent card** (avatar + role + expandable body) — AI Coach exclusive
- **Pill / badge** (LIVE, CACHED, difficulty tier, status)
- **CTA button** (primary action — Start workout, Run AI Coach, Save)
- **Empty state** (icon + title + description, sometimes with action)
- **Permission gate** (HealthKit "Connect" / "Denied" / "Unavailable")
- **Loading state** (the AI Coach 2–5 minute wait — needs to be a *moment*, not a spinner)

---

## 8. Motion direction

The current build has some motion (gradient rotation, staggered card entrance, pulsing rings on loading). Keep motion as a design pillar — but with intent:

- **Motion should reward attention, not demand it.** No bouncing icons, no constant animation.
- **Loading is the highest-stakes motion moment.** A user waiting 3 minutes for AI output should feel like they're watching something happen, not like the app froze.
- **Transitions between states should feel like one continuous canvas**, not jump-cuts between screens.

---

## 9. Specific design opportunities

A non-exhaustive list of moments where strong design choices could elevate the app meaningfully:

1. **The greeting on Home** — "Hello, Kenneth 💪" could be the visual anchor of the whole app. Typography hierarchy here sets the tone for everything.
2. **The weekly progress ring/bar.** Apple Fitness+ rings are iconic for a reason. Find your version.
3. **Workout card photography problem** — without stock photos, what makes a workout card feel exciting? Gradients keyed to category? Generated patterns? Icon arrangements? Solve this.
4. **AI Coach loading state** — currently 4-stage spinner with emoji. Could it be a visualization of the agents passing data to each other? A timeline? An ambient gradient that shifts as each agent completes?
5. **Per-agent identity** — three agents, three personalities. Express this in color, typography weight, motion, or avatar style.
6. **Empty states** — these moments are usually wasted. Make at least one of them delightful enough that users remember.
7. **Markdown rendering** in AI output — currently default attributed string. Could it have its own type scale, blockquote treatment, or list bullet styling that makes it feel like a magazine article?

---

## 10. Out of scope for this redesign

- Backend / API changes (already finalized this week)
- Information architecture (tabs, screen flows are fixed)
- New features (don't propose a meal logger, social feed, etc.)
- Onboarding flow (will be tackled separately)
- App icon / marketing assets (can be addressed separately if time allows)

---

## 11. Success criteria

This redesign will be considered successful if:

- ✅ A stranger looking over the user's shoulder thinks "what app is that, it looks nice"
- ✅ The lecturer can't immediately distinguish it from a real shipped product
- ✅ The AI Coach result feels like a moment, not a data dump
- ✅ All 5 tabs feel like they're part of the same app
- ✅ Light mode and dark mode are both intentional, not afterthoughts
- ✅ The design system is documented enough that future screens can be added consistently

---

## 12. Deliverables hoped for

If Claude Design can produce any of these, in priority order:

1. **Design system foundation** — color palette, type scale, spacing rhythm, motion principles, component library
2. **AI Coach screen — all 5 states** (Ready / Loading / Live Result / Cached / Error)
3. **Home tab** — the daily entry point
4. **Workouts list + detail**
5. **Progress tab**
6. **Health Dashboard**
7. **Profile**
8. **Empty states, error states, permission gates** as a sweep
9. **Handoff bundle for Claude Code** so the design can be translated to SwiftUI without losing fidelity

---

## 13. One last thing

The current build is in a working state — the user (the developer) does not want a redesign that breaks the working backend integration. The redesign output should be visual + a Claude Code handoff bundle, so it can be merged screen-by-screen into the existing SwiftUI codebase rather than as a big-bang rewrite.

**Have fun. Go bold. Surprise us.**
