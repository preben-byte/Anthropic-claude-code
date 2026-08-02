"""Typed configuration schema (Pydantic v2).

Two hard product rules are encoded here rather than scattered through code:

1. Identity is configuration. `assistant_name` and `wake_word` can be changed
   in config/assistant.yaml without touching code, the voice identity, or any
   rebuild step.

2. Language policy (brief §7 as amended): STT listens in Norwegian bokmål,
   spoken replies are always British English, and Norwegian replies happen
   only on Preben's explicit request.
"""

from __future__ import annotations

from enum import Enum
from typing import Literal

from pydantic import BaseModel, Field, field_validator


class AddressStyle(str, Enum):
    PREBEN = "preben"
    SIR = "sir"
    NONE = "none"


class AssistantIdentity(BaseModel):
    assistant_name: str = Field(min_length=1)
    wake_word: str = Field(min_length=1)
    wake_word_aliases: list[str] = Field(default_factory=list)
    address_style: AddressStyle = AddressStyle.NONE

    @field_validator("assistant_name", "wake_word")
    @classmethod
    def _strip(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("must not be blank")
        return v


class ListenPolicy(BaseModel):
    primary_language: str = "nb-NO"
    secondary_languages: list[str] = Field(default_factory=lambda: ["en-GB"])
    auto_language_switch: Literal["conservative", "off"] = "conservative"


class SpeakPolicy(BaseModel):
    language: str = "en-GB"
    reply_in_norwegian: Literal["on_explicit_request_only", "never"] = (
        "on_explicit_request_only"
    )
    norwegian_pronunciation: Literal["lexicon", "off"] = "lexicon"


class LanguagePolicy(BaseModel):
    listen: ListenPolicy = Field(default_factory=ListenPolicy)
    speak: SpeakPolicy = Field(default_factory=SpeakPolicy)

    def reply_language(self, *, explicit_norwegian_request: bool = False) -> str:
        """Language for a spoken reply.

        Replies are always the configured speak language (British English)
        regardless of the language Preben spoke — unless he explicitly asked
        for Norwegian and the policy allows it.
        """
        if (
            explicit_norwegian_request
            and self.speak.reply_in_norwegian == "on_explicit_request_only"
        ):
            return "nb-NO"
        return self.speak.language


class LexiconEntry(BaseModel):
    term: str
    kind: str = "term"
    hint: str


class PronunciationLexicon(BaseModel):
    entries: list[LexiconEntry] = Field(default_factory=list)

    def lookup(self, term: str) -> LexiconEntry | None:
        lowered = term.lower()
        for entry in self.entries:
            if entry.term.lower() == lowered:
                return entry
        return None


class VoiceProfile(BaseModel):
    purpose: str
    model_hint: str | None = None
    target_speed: float = 1.0
    target_stability: float = 0.75


class VoiceConfig(BaseModel):
    active_voice: str | None = None
    fallback_voice: str | None = None
    provider: str = "elevenlabs"
    mock_mode_allowed: bool = True
    profiles: dict[str, VoiceProfile] = Field(default_factory=dict)


class JarvisConfig(BaseModel):
    identity: AssistantIdentity
    language: LanguagePolicy
    voice: VoiceConfig
    pronunciation: PronunciationLexicon
