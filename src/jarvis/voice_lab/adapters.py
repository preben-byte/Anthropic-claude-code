"""TTS adapters for the Voice Lab.

MockTTSAdapter runs fully offline: it writes valid WAV files (a short shaped
tone unique per voice) plus a sidecar transcript, so the whole candidate /
blind-test pipeline can be exercised and timed without an ElevenLabs key.

ElevenLabsAdapter talks to the real API and is only selected when
ELEVENLABS_API_KEY is present. It is written against the current public API
but stays quarantined behind the same interface, so replacing the provider
never touches the rest of the system.
"""

from __future__ import annotations

import json
import math
import struct
import time
import wave
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

import httpx

from jarvis.secrets import get_secret

ELEVENLABS_BASE_URL = "https://api.elevenlabs.io/v1"


@dataclass
class SynthesisResult:
    audio_path: Path
    provider: str
    voice_ref: str
    latency_ms: float
    mock: bool


class TTSAdapter(Protocol):
    provider_name: str

    def synthesize(
        self, text: str, voice_ref: str, out_path: Path, *, language: str = "en-GB"
    ) -> SynthesisResult: ...


class MockTTSAdapter:
    provider_name = "mock"

    SAMPLE_RATE = 24_000  # mono PCM, 24 kHz — matches the brief's internal format

    def synthesize(
        self, text: str, voice_ref: str, out_path: Path, *, language: str = "en-GB"
    ) -> SynthesisResult:
        start = time.perf_counter()
        out_path.parent.mkdir(parents=True, exist_ok=True)

        # A per-voice base frequency makes candidates audibly distinct in
        # blind playback even in mock mode.
        base_freq = 110 + (sum(ord(c) for c in voice_ref) % 80)
        duration_s = min(2.5, 0.4 + len(text) / 400)
        n_samples = int(self.SAMPLE_RATE * duration_s)

        frames = bytearray()
        for i in range(n_samples):
            t = i / self.SAMPLE_RATE
            envelope = min(1.0, t / 0.05, (duration_s - t) / 0.1)
            sample = 0.3 * envelope * math.sin(2 * math.pi * base_freq * t)
            frames += struct.pack("<h", int(sample * 32767))

        with wave.open(str(out_path), "wb") as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(self.SAMPLE_RATE)
            wav.writeframes(bytes(frames))

        out_path.with_suffix(".txt").write_text(
            f"[mock synthesis]\nvoice_ref: {voice_ref}\nlanguage: {language}\n\n{text}\n",
            encoding="utf-8",
        )

        return SynthesisResult(
            audio_path=out_path,
            provider=self.provider_name,
            voice_ref=voice_ref,
            latency_ms=(time.perf_counter() - start) * 1000,
            mock=True,
        )


class ElevenLabsAdapter:
    provider_name = "elevenlabs"

    def __init__(self, api_key: str, model_id: str = "eleven_flash_v2_5"):
        self._api_key = api_key
        self.model_id = model_id

    def synthesize(
        self, text: str, voice_ref: str, out_path: Path, *, language: str = "en-GB"
    ) -> SynthesisResult:
        start = time.perf_counter()
        out_path.parent.mkdir(parents=True, exist_ok=True)
        response = httpx.post(
            f"{ELEVENLABS_BASE_URL}/text-to-speech/{voice_ref}",
            headers={"xi-api-key": self._api_key},
            json={
                "text": text,
                "model_id": self.model_id,
                "output_format": "pcm_24000",
            },
            timeout=60,
        )
        response.raise_for_status()
        pcm = response.content
        with wave.open(str(out_path), "wb") as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(24_000)
            wav.writeframes(pcm)
        return SynthesisResult(
            audio_path=out_path,
            provider=self.provider_name,
            voice_ref=voice_ref,
            latency_ms=(time.perf_counter() - start) * 1000,
            mock=False,
        )

    def design_previews(self, voice_description: str, text: str) -> list[dict]:
        """Request Voice Design previews. Returns raw preview descriptors."""
        response = httpx.post(
            f"{ELEVENLABS_BASE_URL}/text-to-voice/create-previews",
            headers={"xi-api-key": self._api_key},
            json={"voice_description": voice_description, "text": text},
            timeout=120,
        )
        response.raise_for_status()
        return json.loads(response.text).get("previews", [])


def get_adapter() -> TTSAdapter:
    """Real adapter when a key is configured, mock otherwise. Never raises
    for a missing key — the Voice Lab must always be runnable."""
    api_key = get_secret("ELEVENLABS_API_KEY")
    if api_key:
        return ElevenLabsAdapter(api_key)
    return MockTTSAdapter()
