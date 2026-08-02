"""Voice manifest schema (brief §6.9).

The manifest records everything about the approved voice identity except
secrets: no API keys, ever. The voice is decoupled from the assistant's name —
renaming the assistant (config/assistant.yaml) never touches this file.
"""

from __future__ import annotations

from pathlib import Path

from pydantic import BaseModel, Field


class VoiceManifest(BaseModel):
    internal_name: str
    provider: str
    voice_id: str
    voice_design_model: str
    tts_models: list[str]
    created_date: str
    generation_description: str
    settings: dict = Field(default_factory=dict)
    languages: list[str] = Field(default_factory=lambda: ["en-GB", "nb-NO"])
    test_results: dict = Field(default_factory=dict)
    approval_status: str = "pending"          # pending | approved | rejected
    license_consent_status: str = "original_synthetic_voice"
    checksums: dict[str, str] = Field(default_factory=dict)
    known_weaknesses: list[str] = Field(default_factory=list)
    fallback_profile: str | None = None
    next_regression_test_date: str | None = None

    def save(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(self.model_dump_json(indent=2), encoding="utf-8")

    @classmethod
    def load(cls, path: Path) -> "VoiceManifest":
        return cls.model_validate_json(path.read_text(encoding="utf-8"))
