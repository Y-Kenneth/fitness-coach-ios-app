"""
CrewAI agents and crew-builder for FitnessCoach.

Two public entry points:
  - `fitness_crew`: the legacy static crew (kept for backward compat / CLI runs)
  - `build_fitness_crew(snapshot: dict | None)`: builds a crew whose task
    descriptions are interpolated with the user's real HealthKit data.
    Called per-request from server.py.

A `snapshot` is the JSON dict the iOS app POSTs to /run. See HealthSnapshot.swift.
"""

from datetime import datetime

from crewai import Agent, Task, Crew, Process
from crewai import LLM

# ── Connect to Ollama on Windows Laptop ────────────────────────────────────────
WINDOWS_IP = "10.24.135.89"
ollama_llm = LLM(
    model="ollama/llama3.2:3b",
    base_url=f"http://{WINDOWS_IP}:11434"
)

# ── Agents ─────────────────────────────────────────────────────────────────────

ui_agent = Agent(
    role="iOS UI Designer",
    goal="Suggest SwiftUI improvements and UI enhancements for the FitnessCoach app",
    backstory=(
        "You are an expert iOS UI/UX designer who specialises in SwiftUI. "
        "You know Apple's Human Interface Guidelines inside out and always "
        "recommend accessible, modern, and visually polished interfaces."
    ),
    llm=ollama_llm,
    verbose=True,
    allow_delegation=False,
)

healthkit_agent = Agent(
    role="HealthKit Data Analyst",
    goal="Analyse fitness and health data to provide personalised coaching advice",
    backstory=(
        "You are a certified fitness coach and data analyst with deep knowledge "
        "of Apple HealthKit metrics — steps, heart rate, calories, workouts, and sleep. "
        "You translate raw health data into actionable, safe coaching recommendations."
    ),
    llm=ollama_llm,
    verbose=True,
    allow_delegation=False,
)

qa_agent = Agent(
    role="iOS QA Engineer",
    goal="Review SwiftUI code and agent outputs for bugs, edge cases, and quality issues",
    backstory=(
        "You are a senior iOS QA engineer who specialises in SwiftUI apps. "
        "You catch accessibility problems, data edge cases, UI regressions, "
        "and ensure every feature works correctly before it ships."
    ),
    llm=ollama_llm,
    verbose=True,
    allow_delegation=False,
)


# ── Vision-lesson agents ──────────────────────────────────────────────────────
#
# Mirrors the "Agents Used Today" table from the camera-vision lecture.
# These agents design the AI form-check pipeline that the iOS app (Vision +
# AVFoundation + SquatFormAnalyzer) implements. Each agent owns one band of
# the lecture's data flow: camera frame → AVFoundation → Vision pose →
# feature extraction → rule-based analyzer → SwiftUI feedback.
#
# Kept separate from ui_agent / qa_agent above so the original HealthKit
# crew stays unchanged.

healthy_agent = Agent(
    role="iOS Camera Pipeline Engineer (HealthyAgent)",
    goal=(
        "Design a safe, performant AVFoundation capture pipeline that "
        "delivers CVPixelBuffer frames to the ML layer through a small "
        "service protocol."
    ),
    backstory=(
        "You build iOS camera pipelines for fitness apps. You know "
        "AVCaptureSession, AVCaptureDeviceInput, AVCaptureVideoDataOutput, "
        "CMSampleBuffer, and CVPixelBuffer inside-out. You care about "
        "device permissions, front/back camera flipping, thermal load, "
        "and never blocking the main thread. You expose frames through a "
        "small protocol so the ML pipeline can be swapped or mocked."
    ),
    llm=ollama_llm,
    verbose=True,
    allow_delegation=False,
)

ml_agent = Agent(
    role="On-device Vision & Core ML Engineer (MLAgent)",
    goal=(
        "Design the Vision body-pose flow, explain when to use built-in "
        "Vision models versus custom Core ML models, and specify a "
        "rule-based form analyzer that can later graduate into a Core ML "
        "classifier without changing its input or output shape."
    ),
    backstory=(
        "You are an on-device ML engineer. You use VNDetectHumanBodyPoseRequest "
        "for joints, you compute joint angles and visibility features, and "
        "you turn those features into form feedback with simple, "
        "hand-tunable rules. You always describe the migration path from "
        "rules → Core ML so the rule layer's outputs can be swapped for a "
        "trained classifier with the same FormFeedback enum."
    ),
    llm=ollama_llm,
    verbose=True,
    allow_delegation=False,
)

vision_ui_agent = Agent(
    role="SwiftUI Workout-Session Feedback Designer (UIAgent)",
    goal=(
        "Design the in-session SwiftUI overlay that surfaces the form "
        "analyzer's verdict to the user without breaking their rep."
    ),
    backstory=(
        "You design heads-up overlays for live workout sessions. You know "
        "the user is mid-rep and can only glance at the phone — colour, "
        "iconography and one short sentence must do all the work. You map "
        "each FormFeedback state to a green/amber/red treatment, add a "
        "VoiceOver label, and animate state changes so they read but don't "
        "distract."
    ),
    llm=ollama_llm,
    verbose=True,
    allow_delegation=False,
)

vision_qa_agent = Agent(
    role="On-device ML QA Engineer (QAAgent)",
    goal=(
        "Review the camera + pose + rules pipeline for real-time "
        "performance, user privacy, and device-testing coverage."
    ),
    backstory=(
        "You QA on-device ML features on iOS. You check frame-rate under "
        "thermal pressure, verify nothing leaves the device (privacy), "
        "stress-test confidence thresholds in poor lighting, and define a "
        "matrix of devices, framing distances and lighting conditions the "
        "team must validate before shipping."
    ),
    llm=ollama_llm,
    verbose=True,
    allow_delegation=False,
)


# ── Snapshot → human-readable summary ──────────────────────────────────────────

def _summarize_snapshot(snapshot: dict | None) -> str:
    """Build a short, prompt-friendly summary of the user's week."""
    if not snapshot:
        return (
            "No live HealthKit data was provided for this run. "
            "Make general recommendations and remind the user to grant Health "
            "permissions for personalised advice."
        )

    totals = snapshot.get("weekly_totals", {}) or {}
    entries = snapshot.get("daily_entries", []) or []
    source = snapshot.get("data_source", "unknown")

    today_str = datetime.now().strftime("%Y-%m-%d")

    # Find today's entry — prefer exact date match, fall back to last entry.
    today_entry = next((e for e in entries if e.get("date") == today_str), None)
    if today_entry is None and entries:
        today_entry = entries[-1]

    # Build daily breakdown, tagging today's row so the model can't miss it.
    daily_lines = []
    for e in entries:
        date_label = e.get("date", "?")
        tag = " ← TODAY" if date_label == today_str else ""
        daily_lines.append(
            f"  - {date_label}{tag}: "
            f"{e.get('steps', 0):,} steps, "
            f"{e.get('active_kcal', 0)} active kcal, "
            f"{e.get('exercise_minutes', 0)} ex min, "
            f"{e.get('workout_count', 0)} workouts, "
            f"sleep {e.get('sleep_hours', 0):.1f}h, "
            f"avg HR {e.get('avg_heart_rate', 0)} bpm"
        )

    daily_block = "\n".join(daily_lines) if daily_lines else "  (no daily entries)"

    # Prominent today block so small models read the right number directly.
    if today_entry:
        today_block = (
            f"\nTODAY ({today_str}) — use these exact values for any 'today' question:\n"
            f"  Active kcal today:      {today_entry.get('active_kcal', 0)} kcal\n"
            f"  Steps today:            {today_entry.get('steps', 0):,}\n"
            f"  Exercise minutes today: {today_entry.get('exercise_minutes', 0)} min\n"
            f"  Workouts today:         {today_entry.get('workout_count', 0)}\n"
        )
    else:
        today_block = ""

    return (
        f"TODAY'S DATE: {today_str}\n"
        f"{today_block}"
        f"\nUser's 7-day Health summary (source: {source}):\n"
        f"Period: {snapshot.get('period_start', '?')} → {snapshot.get('period_end', '?')}\n"
        f"\n"
        f"Weekly totals:\n"
        f"  - Steps: {totals.get('total_steps', 0):,} "
        f"(avg {totals.get('daily_average_steps', 0):,}/day)\n"
        f"  - Active calories: {totals.get('total_active_kcal', 0)} kcal "
        f"(avg {totals.get('daily_average_active_kcal', 0):.0f}/day, "
        f"goal {totals.get('goal_active_kcal_per_day', 0)}/day)\n"
        f"  - Resting calories: {totals.get('total_resting_kcal', 0)} kcal\n"
        f"  - Exercise minutes: {totals.get('total_exercise_minutes', 0)} min\n"
        f"  - Workouts logged: {totals.get('total_workouts', 0)}\n"
        f"  - Avg resting HR: {totals.get('avg_resting_heart_rate', 0)} bpm\n"
        f"  - Avg sleep: {totals.get('avg_sleep_hours', 0):.1f} hours\n"
        f"\n"
        f"Daily breakdown (most recent = today):\n{daily_block}"
    )


# ── Crew builders ──────────────────────────────────────────────────────────────

def build_fitness_crew(snapshot: dict | None) -> Crew:
    """Build a fresh Crew with tasks tailored to this user's actual data."""
    summary = _summarize_snapshot(snapshot)

    ui_task = Task(
        description=(
            "Review the FitnessCoach iOS app screens: Home, Workouts, Progress, and Profile. "
            "Suggest 3 specific SwiftUI UI improvements that would make the app more "
            "engaging and easier to use. Consider that the user's recent activity looks "
            "like this so your suggestions can fit their habits:\n\n"
            f"{summary}"
        ),
        expected_output="A numbered list of 3 concrete SwiftUI UI improvement suggestions.",
        agent=ui_agent,
    )

    healthkit_task = Task(
        description=(
            "Analyse the user's real HealthKit data below and provide a personalised "
            "coaching message and ONE specific actionable recommendation. Reference "
            "concrete numbers from the data (e.g. specific days, totals, averages). "
            "Avoid generic advice — be precise about what this person actually did "
            "this week.\n\n"
            f"{summary}"
        ),
        expected_output=(
            "A personalised coaching message (3-5 sentences) referencing specific "
            "numbers from the user's week, followed by one concrete actionable "
            "recommendation for the next 7 days."
        ),
        agent=healthkit_agent,
    )

    qa_task = Task(
        description=(
            "Review the outputs from the UI agent and HealthKit agent. "
            "Check for any issues: incorrect advice, unsafe recommendations, claims "
            "that contradict the data, inaccessible UI suggestions, or anything that "
            "could cause problems in the FitnessCoach app. Provide a final "
            "quality-approved summary.\n\n"
            "For reference, the data the HealthKit agent was working with:\n"
            f"{summary}"
        ),
        expected_output="A QA report confirming what passes, what needs revision, and a final approved summary.",
        agent=qa_agent,
    )

    return Crew(
        agents=[ui_agent, healthkit_agent, qa_agent],
        tasks=[ui_task, healthkit_task, qa_task],
        process=Process.sequential,
        verbose=True,
    )


# ── Vision crew builder ───────────────────────────────────────────────────────
#
# Sequential crew that produces a complete design package for the AI camera
# vision feature. Output is documentation — the iOS implementation lives in
# FitnessCoachApp/Services/Vision/SquatFormAnalyzer.swift and the camera VM.
# MVP scope per the lecture: Squat exercise first.

def build_vision_crew(exercise: str = "Squat") -> Crew:
    """Build a crew that designs the on-device camera + pose form-check
    pipeline for `exercise`. Defaults to Squat per the MVP scope."""

    healthy_task = Task(
        description=(
            f"Design the AVFoundation camera capture pipeline for an iOS "
            f"{exercise} form-check session. Cover: AVCaptureSession setup, "
            "front/back camera selection, AVCaptureVideoDataOutput "
            "configuration (pixel format, late-frame discarding), the "
            "capture queue threading model, and the small Swift protocol "
            "the ML pipeline uses to receive CVPixelBuffer frames. "
            "Call out device permissions and graceful denial handling."
        ),
        expected_output=(
            "A short Swift-flavoured design doc: the protocol signature, "
            "the AVCaptureSession configuration steps, the threading "
            "model, and a permissions checklist."
        ),
        agent=healthy_agent,
    )

    ml_task = Task(
        description=(
            f"Design the Vision + rule-based form-analysis layer for the "
            f"{exercise} session. Cover: which VNRequest to use, the "
            "joints required, how to convert Vision's normalised "
            "bottom-left coordinates for SwiftUI, the features to extract "
            "(joint angles, body visibility, confidence), and the rule "
            "thresholds that classify each frame into one of: good form, "
            "not deep enough, knee alignment issue, body not fully "
            "visible, pose confidence too low. Finish with a one-paragraph "
            "migration plan from these rules to a Core ML classifier that "
            "keeps the same input features and output enum."
        ),
        expected_output=(
            "A Swift-flavoured design doc: feature list, threshold table, "
            "the five FormFeedback cases with the rule that fires each, "
            "and a Core ML migration paragraph."
        ),
        agent=ml_agent,
    )

    ui_task = Task(
        description=(
            "Design the SwiftUI in-session feedback overlay that surfaces "
            "the form analyzer's verdict to the user during a live "
            f"{exercise} set. Specify: layout (top bar, skeleton overlay, "
            "bottom feedback card), colour mapping per FormFeedback state "
            "(green = good, amber = correctable fault, red = setup "
            "problem), iconography, motion (animate state changes "
            "subtly), and VoiceOver labels. Assume the user is mid-rep "
            "and can only glance at the screen."
        ),
        expected_output=(
            "A SwiftUI layout spec with the colour/icon/copy mapping for "
            "all five FormFeedback states and accessibility notes."
        ),
        agent=vision_ui_agent,
    )

    qa_task = Task(
        description=(
            "Review the camera pipeline, Vision flow, rule analyzer, and "
            "feedback overlay above for real-time performance, user "
            "privacy, and device-testing coverage. List the "
            "performance budget (target FPS, frame-drop tolerance), the "
            "privacy guarantees (frames never leave device, no recording), "
            "and a device × lighting × framing test matrix the team must "
            "validate on real hardware before ship."
        ),
        expected_output=(
            "A QA report with sections: Performance Budget, Privacy "
            "Guarantees, Test Matrix, and Open Risks."
        ),
        agent=vision_qa_agent,
    )

    return Crew(
        agents=[healthy_agent, ml_agent, vision_ui_agent, vision_qa_agent],
        tasks=[healthy_task, ml_task, ui_task, qa_task],
        process=Process.sequential,
        verbose=True,
    )


# ── Static legacy crew (kept so `python agents.py` still works) ────────────────
fitness_crew = build_fitness_crew(snapshot=None)
vision_crew = build_vision_crew()


# ── CLI Run ────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == "vision":
        exercise = sys.argv[2] if len(sys.argv) > 2 else "Squat"
        print(f"\n📷  FitnessCoach Vision Crew ({exercise}) Starting...\n")
        result = build_vision_crew(exercise).kickoff()
    else:
        print("\n🏋️  FitnessCoach CrewAI Agents Starting...\n")
        result = fitness_crew.kickoff()
    print("\n✅ Final Output:\n")
    print(result)
