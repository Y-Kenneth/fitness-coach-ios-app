#!/usr/bin/env python3
"""
Train a Core ML squat form classifier from synthetic pose data.

Setup (one-time):
    pip install scikit-learn coremltools numpy

Run:
    python CrewAI/train_squat_classifier.py

Output:
    SquatFormClassifier.mlmodel  ← drag this into Xcode under
    FitnessCoachApp/Services/Vision/ and add to the FitnessCoachApp target.

Why synthetic data?
    Vision gives us joint angles every frame. We know from biomechanics what
    "good" and "bad" angle combinations look like, so we can generate realistic
    training distributions without collecting real video first. Once you have
    labelled real data, replace the synthetic arrays with your real CSV and
    retrain — the rest of the pipeline stays the same.

Why Random Forest over the rule-based if/else?
    Rules fire sequentially on single thresholds. A Random Forest considers all
    three features (knee angle, hip angle, knee-ankle drift) simultaneously and
    can learn that, e.g., hip angle changes the acceptable drift range — which
    is the key squat-stance interaction the rules miss.
"""

import sys
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import cross_val_score, StratifiedKFold
import coremltools as ct

np.random.seed(42)
N = 3000  # samples per primary class


# ---------------------------------------------------------------------------
# Synthetic data generators
# Each returns (X, y) where X has 3 columns: kneeAngle, hipAngle, drift
# ---------------------------------------------------------------------------

def good_form_deep(n: int):
    """Deep squat: both knees and hips well flexed, drift minimal."""
    base_knee = np.random.uniform(58, 108, n)
    # Hip tracks the knee with some independent variation
    hip = base_knee + np.random.normal(0, 8, n)
    hip = np.clip(hip, 55, 115)
    drift = np.random.uniform(0.00, 0.052, n)
    return np.column_stack([base_knee, hip, drift]), np.full(n, "goodForm")


def good_form_standing(n: int):
    """Between reps / fully upright — still correct form."""
    knee = np.random.uniform(157, 179, n)
    hip  = np.random.uniform(157, 179, n)
    drift = np.random.uniform(0.00, 0.060, n)
    return np.column_stack([knee, hip, drift]), np.full(n, "goodForm")


def not_deep_enough(n: int):
    """Partial squat — not at parallel yet, alignment is fine."""
    knee = np.random.uniform(111, 156, n)
    hip  = np.random.uniform(100, 152, n)
    drift = np.random.uniform(0.00, 0.063, n)
    return np.column_stack([knee, hip, drift]), np.full(n, "notDeepEnough")


def knee_alignment_issue(n: int):
    """Actively squatting but knees tracking outside ankles."""
    knee = np.random.uniform(68, 156, n)
    hip  = np.random.uniform(68, 148, n)
    drift = np.random.uniform(0.088, 0.26, n)
    return np.column_stack([knee, hip, drift]), np.full(n, "kneeAlignmentIssue")


def borderline_alignment_in_partial(n: int):
    """Partial squat + alignment fault: alignment label takes priority."""
    knee = np.random.uniform(111, 154, n)
    hip  = np.random.uniform(100, 148, n)
    drift = np.random.uniform(0.088, 0.20, n)
    return np.column_stack([knee, hip, drift]), np.full(n, "kneeAlignmentIssue")


def wide_stance_good(n: int):
    """Wide-stance squat: hip angle more open than narrow stance, still good."""
    knee = np.random.uniform(72, 108, n)
    hip  = knee + np.random.uniform(5, 20, n)   # hip opens more in wide stance
    hip  = np.clip(hip, 78, 125)
    drift = np.random.uniform(0.00, 0.068, n)   # more drift acceptable for wide
    return np.column_stack([knee, hip, drift]), np.full(n, "goodForm")


# ---------------------------------------------------------------------------
# Build dataset
# ---------------------------------------------------------------------------

sets = [
    good_form_deep(N),
    good_form_standing(N // 2),
    not_deep_enough(N),
    knee_alignment_issue(N),
    borderline_alignment_in_partial(N // 3),
    wide_stance_good(N // 3),
]

X = np.vstack([s[0] for s in sets])
y = np.concatenate([s[1] for s in sets])

print(f"Dataset: {len(X)} samples")
for label in np.unique(y):
    print(f"  {label}: {(y == label).sum()}")


# ---------------------------------------------------------------------------
# Train
# ---------------------------------------------------------------------------

clf = RandomForestClassifier(
    n_estimators=200,
    max_depth=10,
    min_samples_leaf=3,
    class_weight="balanced",
    random_state=42,
    n_jobs=-1,
)

cv = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)
scores = cross_val_score(clf, X, y, cv=cv, scoring="accuracy")
print(f"\nCross-validation accuracy: {scores.mean():.3f} ± {scores.std():.3f}")

clf.fit(X, y)
train_acc = clf.score(X, y)
print(f"Training accuracy:         {train_acc:.3f}")

feature_names = ["kneeAngleDegrees", "hipAngleDegrees", "kneeAnkleDrift"]
importances = clf.feature_importances_
print("\nFeature importances:")
for name, imp in zip(feature_names, importances):
    bar = "█" * int(imp * 40)
    print(f"  {name:<22}  {imp:.3f}  {bar}")


# ---------------------------------------------------------------------------
# Convert to Core ML
# ---------------------------------------------------------------------------

coreml_model = ct.converters.sklearn.convert(
    clf,
    input_features=feature_names,
    output_feature_names="formLabel",
)

coreml_model.short_description = (
    "Squat form classifier. "
    "Input: Vision-derived joint angles and knee-ankle drift. "
    "Output: goodForm | notDeepEnough | kneeAlignmentIssue"
)
coreml_model.input_description["kneeAngleDegrees"] = (
    "Knee flexion angle in degrees averaged across both legs (Vision-derived). "
    "180° = standing, ~100° = thighs parallel, 70° = deep squat."
)
coreml_model.input_description["hipAngleDegrees"] = (
    "Hip flexion angle in degrees (shoulder-hip-knee). "
    "180° = upright, smaller = more bent forward."
)
coreml_model.input_description["kneeAnkleDrift"] = (
    "Normalized horizontal offset between knee and ankle (0–1 image units). "
    "Values above ~0.08 indicate knees tracking outside ankles."
)
coreml_model.output_description["formLabel"] = (
    "Predicted form class: goodForm, notDeepEnough, or kneeAlignmentIssue."
)

output_path = "SquatFormClassifier.mlmodel"
coreml_model.save(output_path)
print(f"\n✓  Saved {output_path}")
print(
    "\nNext steps:\n"
    "  1. In Xcode, drag SquatFormClassifier.mlmodel into\n"
    "     FitnessCoachApp/Services/Vision/\n"
    "  2. In the 'Add to targets' dialog, check FitnessCoachApp\n"
    "  3. Build the project — Xcode compiles the model automatically\n"
    "  4. The app uses it live; falls back to rule-based if model is missing"
)
