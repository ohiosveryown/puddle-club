# Puddle Club — Prompt Architecture

## Overview

Two-prompt system that separates individual screenshot classification from cross-corpus pattern recognition. The intake prompt handles each screenshot. The pattern prompt runs periodically across the full library and injects context back into individual reflections — this is what makes the reflection feel personal rather than generic.

---

## Prompt 1 — Intake

Runs on every new screenshot. Classifies content and generates a reflection. If pattern context is available it is injected at runtime to make the reflection specific and personal.

```swift
private let intakePrompt = """
Return ONLY valid JSON with these keys:
title, contentType, contentTypeConfidence, entities, tags,
reflection, aestheticNotes, moodTags, sourceURL.

TITLE
A concise name for the subject. Be specific.
Good: "Carlsbad Flower Fields", "Kendrick Lamar - GNX", "Nike Air Max 90"
Bad: "Beautiful landscape", "Music album", "Sneaker"

CONTENT TYPE
Must be exactly one of: food, music, travel, design, fashion,
product, architecture, art, text, social, event, person,
nature, craft, unknown.
contentTypeConfidence: 0.0–1.0

ENTITIES
Array of {name, type, confidence} for any identifiable
people, places, brands, songs, dishes, etc.

TAGS
3–6 short descriptive keywords. Factual, not aesthetic.

REFLECTION
1–2 sentences. Second person ("you").
Focus on mood and the user's relationship to this content.
Not a description of what's on screen.
If pattern context is provided below, reference it directly
and specifically — recurrence, timing, evolution of interest.
If no pattern context, keep it observational and open.

AESTHETIC NOTES
Array of 1–2 short phrases (max 3 words per phrase) describing the overall visual,
typographic, and tonal vibe.
Good: "1980s film", "Organic forms", "Art book layout energy"
Bad: "Beautiful", "Colorful", "Modern"
Only include if genuinely distinctive — omit for generic imagery.

MOOD TAGS
Array of 2–4 single words describing the emotional register.
Good: "Melancholy", "Aspirational", "Playful", "Quiet"
Different from aestheticNotes — about feeling, not visual style.

SOURCE URL
Most relevant URL visible anywhere in the image.
Social posts: prefer direct post URL.
If only a handle is visible: return profile URL.
Any other site: return domain as-is.
Omit if no URL present.

---
PATTERN CONTEXT (injected at runtime if available):
\(patternContext ?? "None available — treat this as a first impression.")
"""
```

---

## Prompt 2 — Pattern

Runs periodically across the full screenshot corpus. Generates taste signatures, behavioral patterns, and per-content-type summaries that get injected into future intake reflections.

```swift
private let patternPrompt = """
You are analyzing a personal screenshot library to identify
taste patterns, recurring interests, and behavioral signals.
This data will be used to generate personalized reflections
that feel like they come from something that has been paying
close attention over time.

Return ONLY valid JSON with these keys:
recurringThemes, aestheticSignature, behavioralPatterns,
contentProfile, patternSummaries.

INPUT
You will receive an array of processed screenshots, each with:
title, contentType, tags, aestheticNotes, moodTags,
savedAt (timestamp).

RECURRING THEMES
Array of {theme, count, firstSeen, lastSeen, examples[]}.
Identify topics, places, people, or content types that
appear 3 or more times.
Be specific — not "beaches" but "empty coastlines, usually
overcast, no people visible."

AESTHETIC SIGNATURE
3–5 phrases that describe the user's overall visual taste
across the entire library.
Should feel like a considered critical observation, not a
list of tags.
Good: "Drawn to spaces that feel inhabited rather than
designed. Prefers grain over polish."
Bad: "Likes minimalism, black and white, vintage"

BEHAVIORAL PATTERNS
Array of {pattern, insight}.
Observations about how and when they save, not just what.
Examples:
- "Saves heavily on Sunday evenings"
- "Travel content spikes before and after major life events"
- "Saves products repeatedly without purchasing"
- "Music saves cluster around specific moods"

CONTENT PROFILE
Breakdown by contentType as percentages.
Include dominant and notable-minority categories.

PATTERN SUMMARIES
Array of {contentType, summary}.
For each major content type, a 1–2 sentence summary written
in second person that can be injected into individual
reflections as context.
These should be specific enough to feel personal.

Good example for travel:
"You save coastal destinations almost exclusively —
specifically places that feel uncrowded and slightly
melancholy. You've been saving Carlsbad content since 2022
without going."

Bad example for travel:
"You enjoy saving travel content including beaches
and destinations."
"""
```

---

## Runtime Connection

How pattern context gets built and injected into each intake prompt at runtime.

```swift
func buildReflectionContext(for screenshot: Screenshot) -> String? {
    guard let pattern = patternStore.summary(
        for: screenshot.contentType
    ) else { return nil }

    let recurring = patternStore.recurringThemes
        .filter { $0.examples.contains(screenshot.title) }
        .map { "Part of a recurring theme: \($0.theme) — \($0.count) saves since \($0.firstSeen)" }
        .first

    return [pattern, recurring]
        .compactMap { $0 }
        .joined(separator: "\n")
}
```

Then at intake:

```swift
let context = buildReflectionContext(for: screenshot)
let prompt = intakePrompt.replacingOccurrences(
    of: "\\(patternContext ?? \"None available — treat this as a first impression.\")",
    with: context ?? "None available — treat this as a first impression."
)
```

---

## When to Run the Pattern Prompt

Not on every screenshot — expensive and slow. Suggested triggers:

- **First run:** after 25+ screenshots processed
- **Recurring:** every 50 new screenshots added
- **On demand:** when user opens the chat / ask interface
- **Background:** weekly via `BGProcessingTask` on overnight charge

---

## Key Design Principles

- The **pattern store** is the memory — it accumulates knowledge about the user over time
- The **intake prompt** is the voice — it speaks to the user about individual screenshots
- Without pattern context, reflections describe the image
- With pattern context, reflections describe the user
- `aestheticNotes` is about visual style — how something looks
- `moodTags` is about emotional register — how something feels
- `contentTypeConfidence` gives you the threshold data to decide when to suppress fields conditionally in the UI
- `aestheticNotes` should be suppressed when confidence is low or content is generic — not every screenshot warrants an aesthetic label
