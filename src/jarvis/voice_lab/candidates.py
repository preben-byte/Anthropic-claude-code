"""Blind-coded voice candidate generation (brief §6.2).

Four controlled variants (A–D) of one base description, three candidates
each: blind codes A01–D03. During the first listening round only the blind
code is shown — never the variant brief or provider description — to reduce
expectation bias.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path

from .adapters import TTSAdapter
from .texts import TEST_TEXT_EN, TEST_TEXT_MIXED

BASE_VOICE_DESCRIPTION = (
    "Create a wholly original mature British male synthetic assistant voice. "
    "Perceived age approximately 40-48. Standard Southern British English "
    "with excellent international intelligibility. Medium-low baritone, "
    "controlled resonance, clean low mids and crisp consonants without "
    "exaggerated bass or theatrical projection. Calm, observant, precise and "
    "quietly authoritative. Emotion is restrained but never lifeless. Dry "
    "intelligence and subtle warmth should be audible without sounding "
    "playful, smug or sarcastic. Speech is measured, economical and "
    "confident, with clean downward sentence endings, short deliberate "
    "pauses and almost no breath noise. Close-mic, dry studio sound with no "
    "room ambience. The identity must remain stable in short commands, long "
    "technical explanations, warnings, numbers and bilingual "
    "English/Norwegian speech. It must be an original identity and must not "
    "imitate or resemble any actor, celebrity or recognizable fictional "
    "performance."
)

VARIANT_BRIEFS: dict[str, str] = {
    "A": "Slightly warmer and more diplomatic.",
    "B": "Cooler and more analytical.",
    "C": "Slightly deeper and more sonorous, but never a movie-trailer voice.",
    "D": "Slightly brighter and faster, especially clear for long technical answers.",
}

CANDIDATES_PER_VARIANT = 3


@dataclass
class Candidate:
    blind_code: str          # e.g. "B02" — the only identifier shown in round 1
    variant: str             # internal only; hidden during blind evaluation
    voice_ref: str           # provider voice/preview id, or mock ref
    samples: list[Path] = field(default_factory=list)


def generate_candidates(
    adapter: TTSAdapter,
    out_dir: Path,
    *,
    variants: dict[str, str] | None = None,
    per_variant: int = CANDIDATES_PER_VARIANT,
) -> list[Candidate]:
    """Generate blind-coded candidates and synthesize the two core samples
    (English test text + mixed English/Norwegian-names text) for each."""
    variants = variants or VARIANT_BRIEFS
    out_dir.mkdir(parents=True, exist_ok=True)
    candidates: list[Candidate] = []

    for variant_key in variants:
        for index in range(1, per_variant + 1):
            blind_code = f"{variant_key}{index:02d}"
            voice_ref = f"voicelab-{blind_code.lower()}"
            candidate = Candidate(
                blind_code=blind_code, variant=variant_key, voice_ref=voice_ref
            )
            for sample_name, text in (
                ("english", TEST_TEXT_EN),
                ("mixed_norwegian_names", TEST_TEXT_MIXED),
            ):
                result = adapter.synthesize(
                    text,
                    voice_ref,
                    out_dir / blind_code / f"{sample_name}.wav",
                )
                candidate.samples.append(result.audio_path)
            candidates.append(candidate)

    # Blind listing for round 1: codes and audio only — no variant briefs,
    # no provider descriptions.
    blind_listing = [
        {"blind_code": c.blind_code, "samples": [str(p) for p in c.samples]}
        for c in candidates
    ]
    (out_dir / "blind_listing.json").write_text(
        json.dumps(blind_listing, indent=2), encoding="utf-8"
    )

    # Full mapping kept separately for after the blind round.
    internal = [
        {
            "blind_code": c.blind_code,
            "variant": c.variant,
            "variant_brief": variants[c.variant],
            "voice_ref": c.voice_ref,
        }
        for c in candidates
    ]
    (out_dir / "internal_mapping.json").write_text(
        json.dumps(internal, indent=2), encoding="utf-8"
    )

    return candidates
