# FitnessCoach CrewAI Flask Server
#
# Requirements:
#     pip install flask crewai
#     (plus dependencies from agents.py — requires an Ollama-reachable LLM)
#
# Run:
#     python server.py
#
# The iOS app POSTs to http://<this-mac-ip>:5001/run
# and GETs /health to check reachability.

import time
from datetime import datetime, timezone
from flask import Flask, jsonify, request
from agents import build_fitness_crew, ollama_llm, _summarize_snapshot

app = Flask(__name__)


# ── Conversational fitness coach ──────────────────────────────────────────────
# The iOS app's AI Coach screen calls /chat for every turn. The full
# HealthSnapshot is included so the coach knows the user's steps/calories/HR/
# sleep/workouts from message #1 — no /run needed first.
#
# /run still exists for the CrewAI assignment: it kicks the full 3-agent crew
# (verbose=True logs in the terminal). Output is NOT shown in the app.

CHAT_SYSTEM_PROMPT = (
    "You are FitCoach, a friendly and knowledgeable AI fitness coach inside the "
    "FitnessCoach iOS app. You speak to one specific user whose recent Apple "
    "Health data is given to you below. You can talk about workouts, steps, "
    "calories, heart rate, sleep, recovery, nutrition basics, exercise form, "
    "motivation — anything fitness or general wellness related.\n\n"
    "Guidelines:\n"
    "- Reference the user's actual numbers when relevant (e.g. \"you averaged "
    "9,268 steps this week\"). Don't invent numbers that aren't in the data.\n"
    "- Be conversational and warm, not clinical. Short paragraphs over long lists.\n"
    "- Keep most replies to 2-5 sentences. Go longer only when the user asks for "
    "a plan, breakdown, or detailed explanation.\n"
    "- If the user asks something off-topic (coding, news, etc.), gently redirect "
    "back to fitness and wellness.\n"
    "- Never give medical diagnoses or prescribe treatment. Suggest seeing a "
    "doctor or certified professional when the user describes pain, injury, or "
    "symptoms that warrant it.\n"
    "- If no health data is available, say so and answer with general advice."
)


def _build_chat_messages(snapshot: dict | None,
                         original_report: str,
                         history: list,
                         new_question: str) -> list:
    """Assemble the message list for the conversational coach LLM call."""
    today_str = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    system_with_date = CHAT_SYSTEM_PROMPT + f"\n\nToday's date is {today_str}."
    messages = [{"role": "system", "content": system_with_date}]

    # Always inject the user's data summary if we have a snapshot, so the
    # coach has full context even when /run has never been called.
    if snapshot:
        messages.append({
            "role": "system",
            "content": (
                "=== USER'S RECENT HEALTH DATA ===\n"
                f"{_summarize_snapshot(snapshot)}"
            ),
        })

    # Optional: include the CrewAI weekly report if the app passed it.
    report = (original_report or "").strip()
    if report:
        messages.append({
            "role": "system",
            "content": (
                "=== EARLIER COACHING REPORT (for reference) ===\n"
                f"{report}"
            ),
        })

    for turn in history or []:
        role = turn.get("role")
        content = (turn.get("content") or "").strip()
        if role in ("user", "assistant") and content:
            messages.append({"role": role, "content": content})
    messages.append({"role": "user", "content": new_question.strip()})
    return messages


def _agent_emoji(role: str) -> str:
    """Pick an emoji for the agent role so iOS can render an avatar fallback."""
    role_lower = (role or "").lower()
    if "ui" in role_lower or "designer" in role_lower:
        return "🎨"
    if "health" in role_lower or "fitness" in role_lower or "data" in role_lower:
        return "💪"
    if "qa" in role_lower or "quality" in role_lower:
        return "🧪"
    return "🤖"


def _extract_agent_outputs(crew_output) -> list:
    """Pull per-task outputs from CrewOutput into a simple JSON-friendly shape."""
    outputs = []
    tasks_output = getattr(crew_output, "tasks_output", None) or []
    for idx, task_out in enumerate(tasks_output):
        raw = getattr(task_out, "raw", None) or str(task_out)
        agent_role = getattr(task_out, "agent", None) or f"Agent {idx + 1}"
        description = getattr(task_out, "description", "") or ""
        outputs.append({
            "agent_role": agent_role,
            "agent_emoji": _agent_emoji(agent_role),
            "task_description": description.strip(),
            "output": str(raw).strip(),
            "order": idx + 1,
        })
    return outputs


def _artifact_data_from_snapshot(snapshot: dict | None, coaching_note: str) -> dict:
    """Build the calorie-summary 'data' block from the user's actual snapshot,
    falling back to zeroes if none was provided."""
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    if not snapshot:
        return {
            "period": {"start_date": today, "end_date": today},
            "summary": {
                "total_active_kcal": 0,
                "total_resting_kcal": 0,
                "total_kcal": 0,
                "daily_average_active_kcal": 0.0,
                "daily_average_resting_kcal": 0.0,
                "goal_active_kcal_per_day": 500,
            },
            "daily_entries": [],
            "coaching_note": coaching_note,
        }

    totals = snapshot.get("weekly_totals", {}) or {}
    total_active = totals.get("total_active_kcal", 0)
    total_resting = totals.get("total_resting_kcal", 0)

    daily_entries = []
    for e in snapshot.get("daily_entries", []) or []:
        daily_entries.append({
            "date": e.get("date", ""),
            "active_kcal": e.get("active_kcal", 0),
            "resting_kcal": e.get("resting_kcal", 0),
            "steps": e.get("steps", 0),
            "exercise_minutes": e.get("exercise_minutes", 0),
        })

    return {
        "period": {
            "start_date": snapshot.get("period_start", today),
            "end_date": snapshot.get("period_end", today),
        },
        "summary": {
            "total_active_kcal": total_active,
            "total_resting_kcal": total_resting,
            "total_kcal": total_active + total_resting,
            "daily_average_active_kcal": totals.get("daily_average_active_kcal", 0.0),
            "daily_average_resting_kcal": (total_resting / 7) if total_resting else 0.0,
            "goal_active_kcal_per_day": totals.get("goal_active_kcal_per_day", 500),
        },
        "daily_entries": daily_entries,
        "coaching_note": coaching_note,
    }


def _wrap_crew_output_as_a2a(crew_output, duration_seconds: float, snapshot: dict | None) -> dict:
    """Map CrewAI's CrewOutput object into JSON the iOS app can decode."""
    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    agent_outputs = _extract_agent_outputs(crew_output)

    final_text = str(crew_output).strip()
    coaching_note = final_text if final_text else "AI Coach finished but returned no message."

    return {
        "jsonrpc": "2.0",
        "id": "req-live-001",
        "result": {
            "id": "task-live-crewai-001",
            "sessionId": f"session-live-{today}",
            "status": {
                "state": "completed",
                "timestamp": now_iso,
            },
            "run_metadata": {
                "duration_seconds": round(duration_seconds, 2),
                "agent_count": len(agent_outputs),
                "model": "ollama/llama3.2:3b",
                "completed_at": now_iso,
                "data_source": (snapshot or {}).get("data_source", "none"),
            },
            "agent_outputs": agent_outputs,
            "artifacts": [
                {
                    "artifactId": f"live-coaching-{today}",
                    "name": "Live AI Coaching",
                    "description": "Live CrewAI output with the user's real HealthKit data",
                    "mimeType": "application/json",
                    "parts": [
                        {
                            "kind": "data",
                            "data": _artifact_data_from_snapshot(snapshot, coaching_note),
                        }
                    ],
                }
            ],
        },
    }


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok"}), 200


@app.route("/run", methods=["POST"])
def run():
    snapshot = request.get_json(silent=True)
    if snapshot:
        source = snapshot.get("data_source", "unknown")
        steps = (snapshot.get("weekly_totals") or {}).get("total_steps", 0)
        print(f"\n🟢 [server] /run received — snapshot source={source}, weekly_steps={steps:,}")
    else:
        print("\n🟢 [server] /run received with no snapshot — using generic advice.")

    start = time.monotonic()
    try:
        crew = build_fitness_crew(snapshot)
        result = crew.kickoff()
        duration = time.monotonic() - start
        print(f"\n✅ [server] CrewAI finished in {duration:.1f}s. Returning JSON to iOS.")
        return jsonify(_wrap_crew_output_as_a2a(result, duration, snapshot)), 200
    except Exception as exc:
        print(f"\n❌ [server] CrewAI failed: {exc}")
        return jsonify({"error": str(exc)}), 500


@app.route("/chat", methods=["POST"])
def chat():
    """Conversational coach turn.

    Expected JSON body:
      {
        "snapshot": { ... HealthSnapshot JSON ... },   # optional but recommended
        "original_report": "<text of an earlier crew report>",  # optional
        "history": [{"role": "user"|"assistant", "content": "..."}, ...],
        "question": "<the user's new question>"
      }
    """
    body = request.get_json(silent=True) or {}
    question = (body.get("question") or "").strip()
    if not question:
        return jsonify({"error": "Missing 'question' in request body."}), 400

    snapshot = body.get("snapshot")
    original_report = body.get("original_report") or ""
    history = body.get("history") or []

    snap_src = (snapshot or {}).get("data_source", "none")
    print(f"\n💬 [server] /chat — turns={len(history)}, snap={snap_src}, q={question[:80]!r}")

    messages = _build_chat_messages(snapshot, original_report, history, question)

    start = time.monotonic()
    try:
        reply = ollama_llm.call(messages=messages)
    except Exception as exc:
        print(f"\n❌ [server] /chat failed: {exc}")
        return jsonify({"error": str(exc)}), 500

    duration = time.monotonic() - start
    reply_text = (reply or "").strip() if isinstance(reply, str) else str(reply).strip()
    print(f"\n✅ [server] /chat replied in {duration:.1f}s ({len(reply_text)} chars).")

    return jsonify({
        "reply": reply_text,
        "duration_seconds": round(duration, 2),
        "model": "ollama/llama3.2:3b",
    }), 200


if __name__ == "__main__":
    print("🚀 FitnessCoach CrewAI server starting on http://0.0.0.0:5001")
    print("   Endpoints:  GET /health   POST /run   POST /chat")
    app.run(host="0.0.0.0", port=5001, debug=False)
