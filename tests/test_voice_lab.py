"""Voice Lab runs end-to-end in mock mode: no key, no network."""

import json
import wave
from pathlib import Path

from jarvis.voice_lab.adapters import MockTTSAdapter, get_adapter
from jarvis.voice_lab.candidates import generate_candidates
from jarvis.voice_lab.manifest import VoiceManifest
from jarvis.voice_lab.texts import TEST_TEXT_EN


def test_adapter_falls_back_to_mock_without_key(monkeypatch):
    monkeypatch.delenv("ELEVENLABS_API_KEY", raising=False)
    assert get_adapter().provider_name == "mock"


def test_mock_synthesis_writes_valid_wav(tmp_path: Path):
    result = MockTTSAdapter().synthesize(TEST_TEXT_EN, "voicelab-a01", tmp_path / "a.wav")
    assert result.mock
    with wave.open(str(result.audio_path)) as wav:
        assert wav.getnchannels() == 1
        assert wav.getframerate() == 24_000
        assert wav.getnframes() > 0


def test_generates_twelve_blind_coded_candidates(tmp_path: Path):
    candidates = generate_candidates(MockTTSAdapter(), tmp_path)
    codes = [c.blind_code for c in candidates]
    assert len(codes) == 12
    assert codes[0] == "A01" and codes[-1] == "D03"
    assert all(len(c.samples) == 2 for c in candidates)
    assert all(p.is_file() for c in candidates for p in c.samples)


def test_blind_listing_hides_variant_information(tmp_path: Path):
    generate_candidates(MockTTSAdapter(), tmp_path)
    blind = json.loads((tmp_path / "blind_listing.json").read_text())
    assert len(blind) == 12
    for row in blind:
        assert set(row) == {"blind_code", "samples"}, (
            "blind listing must expose only blind codes and audio paths"
        )


def test_voice_manifest_roundtrip_contains_no_secrets(tmp_path: Path):
    manifest = VoiceManifest(
        internal_name="candidate-b02",
        provider="elevenlabs",
        voice_id="mock-voice-id",
        voice_design_model="eleven_ttv_v3",
        tts_models=["eleven_flash_v2_5", "eleven_v3"],
        created_date="2026-08-02",
        generation_description="original synthetic British male assistant voice",
    )
    path = tmp_path / "voice_manifest.json"
    manifest.save(path)
    loaded = VoiceManifest.load(path)
    assert loaded == manifest
    raw = path.read_text().lower()
    assert "api_key" not in raw and "xi-api-key" not in raw
