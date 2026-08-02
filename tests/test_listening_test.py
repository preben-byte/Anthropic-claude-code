"""Round-1 listening test: blind page + score persistence."""

import json
from pathlib import Path

import pytest

from jarvis.voice_lab.adapters import MockTTSAdapter
from jarvis.voice_lab.candidates import VARIANT_BRIEFS, generate_candidates
from jarvis.voice_lab.listening_test import CRITERIA, build_page, save_score


@pytest.fixture()
def candidates_dir(tmp_path: Path) -> Path:
    generate_candidates(MockTTSAdapter(), tmp_path)
    return tmp_path


def test_page_shows_blind_codes_and_criteria(candidates_dir: Path):
    page = build_page(candidates_dir)
    html = page.read_text(encoding="utf-8")
    for code in ("A01", "B02", "D03"):
        assert code in html
    for _, label in CRITERIA:
        assert label in html
    assert "diskvalifiserende" in html


def test_page_leaks_no_variant_information(candidates_dir: Path):
    """Bias control: the page must not reveal variant briefs (§6.2/§6.5)."""
    html = build_page(candidates_dir).read_text(encoding="utf-8")
    for brief in VARIANT_BRIEFS.values():
        assert brief not in html
    assert "internal_mapping" not in html
    assert "variant" not in html.lower()


def test_save_score_roundtrip(candidates_dir: Path):
    payload = {
        "blind_code": "B02",
        "scores": {"identity": 4, "norwegian": 5},
        "recognizable": False,
    }
    out = save_score(candidates_dir, payload)
    assert out == candidates_dir / "scores" / "B02.json"
    assert json.loads(out.read_text(encoding="utf-8")) == payload


def test_save_score_rejects_bad_code(candidates_dir: Path):
    with pytest.raises(ValueError):
        save_score(candidates_dir, {"blind_code": "../evil", "scores": {}})
    with pytest.raises(ValueError):
        save_score(candidates_dir, {"scores": {}})
