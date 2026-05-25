# FitnessCoach CrewAI Flask Server

A small Flask wrapper around `agents.py` so the iOS app can trigger the CrewAI
pipeline over the local network. Receives a 7-day HealthKit snapshot from the
iPhone, runs the 3 AI agents, and returns a structured JSON report.

## Install

From the project root (activate your venv first):

```bash
source venv/bin/activate
pip install flask crewai apscheduler   # apscheduler silences a litellm warning
```

`server.py` imports `build_fitness_crew` from `agents.py`, which interpolates
the user's real HealthKit data into each agent's task description on every
request. `python agents.py` still works standalone for CLI testing (uses
`fitness_crew` with no snapshot).

## Run

```bash
cd CrewAI
python server.py
```

Expected startup output:

```
🚀 FitnessCoach CrewAI server starting on http://0.0.0.0:5001
   Endpoints:  GET /health   POST /run
 * Serving Flask app 'server'
 * Running on all addresses (0.0.0.0)
 * Running on http://127.0.0.1:5001
 * Running on http://<Mac LAN IP>:5001
```

When a request arrives you'll see:

```
🟢 [server] /run received — snapshot source=healthkit, weekly_steps=42,103
... (CrewAI verbose logs, 2–5 minutes) ...
✅ [server] CrewAI finished in 187.4s. Returning JSON to iOS.
```

The `source=...` line is your built-in proof of which dataset the AI is working with:

| Value | Meaning |
|---|---|
| `healthkit` | Real Apple Health data from a physical iPhone |
| `mock` | Seeded weekly data from `MockHealthDataProvider` (simulator) |
| `none` | iOS sent no body (older client or fallback path) |

## Pre-flight test (before starting the server)

The CrewAI server is useless if Ollama on the Windows laptop isn't reachable.
Test that first:

```bash
curl -s --max-time 5 http://10.24.135.89:11434/api/tags && echo "✅ Ollama OK" || echo "❌ Ollama unreachable"
```

The Windows IP is hardcoded as `WINDOWS_IP` near the top of `agents.py`.
Update it there if the Windows machine moves to a different network.

## Test the server from the Mac (after starting it)

Health check (instant):

```bash
curl http://127.0.0.1:5001/health
# → {"status": "ok"}
```

Trigger a full run with a minimal mock body (takes 2–5 minutes):

```bash
curl -X POST http://127.0.0.1:5001/run \
  -H "Content-Type: application/json" \
  -d '{"data_source":"manual_test","weekly_totals":{"total_steps":10000}}'
```

Or trigger from iOS — the request body is built and POSTed automatically
when the user taps **Run** in the AI Coach screen.

## How iOS finds this server

`A2ACoachingView.swift` picks a host at compile time:

- **iOS Simulator** → `http://127.0.0.1:5001` (loopback — never changes, works
  through VPNs, ignores WiFi)
- **Physical iPhone** → `http://30s-iMac.local:5001` (Bonjour follows the Mac
  across IP changes; iPhone must be on the same WiFi as the Mac)

No IP edits needed when the Mac's address changes. If the Mac is *renamed*
(`scutil --set LocalHostName ...`), update the hostname in the Swift file.

## Response shape

`POST /run` returns JSON with these top-level fields under `result`:

- `agent_outputs[]` — per-agent role, emoji, task description, raw output text
- `run_metadata` — `duration_seconds`, `agent_count`, `model`, `data_source`
- `artifacts[]` — the weekly summary + per-day entries echoed from the request,
  decoded by the existing iOS UI
- `status` — `state` and `timestamp`

See [`../docs/APP_OVERVIEW.md`](../docs/APP_OVERVIEW.md) for the end-to-end
architecture.
