"""
CrewAI agents and crew-builder for FitnessCoach.

Two public entry points:
  - `fitness_crew`: the legacy static crew (kept for backward compat / CLI runs)
  - `build_fitness_crew(snapshot: dict | None)`: builds a crew whose task
    descriptions are interpolated with the user's real HealthKit data.
    Called per-request from server.py.

A `snapshot` is the JSON dict the iOS app POSTs to /run. See HealthSnapshot.swift.
"""

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

    daily_lines = []
    for e in entries:
        daily_lines.append(
            f"  - {e.get('date', '?')}: "
            f"{e.get('steps', 0):,} steps, "
            f"{e.get('active_kcal', 0)} active kcal, "
            f"{e.get('exercise_minutes', 0)} ex min, "
            f"{e.get('workout_count', 0)} workouts, "
            f"sleep {e.get('sleep_hours', 0):.1f}h, "
            f"avg HR {e.get('avg_heart_rate', 0)} bpm"
        )

    daily_block = "\n".join(daily_lines) if daily_lines else "  (no daily entries)"

    return (
        f"User's 7-day Health summary (source: {source}):\n"
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
        f"Daily breakdown:\n{daily_block}"
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


# ── Static legacy crew (kept so `python agents.py` still works) ────────────────
fitness_crew = build_fitness_crew(snapshot=None)


# ── CLI Run ────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    print("\n🏋️  FitnessCoach CrewAI Agents Starting...\n")
    result = fitness_crew.kickoff()
    print("\n✅ Final Output:\n")
    print(result)
