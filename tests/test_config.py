"""The assistant's name and wake word are configuration, not code."""

from pathlib import Path

import pytest
import yaml

from jarvis.config import load_config, find_config_dir

PROJECT_ROOT = Path(__file__).resolve().parents[1]
CONFIG_DIR = PROJECT_ROOT / "config"


def test_default_identity_is_working_name():
    config = load_config(CONFIG_DIR)
    assert config.identity.assistant_name == "Jarvis"
    assert config.identity.wake_word == "Jarvis"


def test_rename_via_config_file_only(tmp_path: Path):
    """Renaming the assistant = editing one YAML file. Nothing else changes."""
    custom = tmp_path / "config"
    custom.mkdir()
    for name in ("assistant.yaml", "language.yaml", "voices.yaml", "pronunciation.yaml"):
        custom.joinpath(name).write_text(
            (CONFIG_DIR / name).read_text(encoding="utf-8"), encoding="utf-8"
        )

    identity = yaml.safe_load((custom / "assistant.yaml").read_text())
    identity["assistant_name"] = "Aurora"
    identity["wake_word"] = "Aurora"
    (custom / "assistant.yaml").write_text(yaml.safe_dump(identity), encoding="utf-8")

    original = load_config(CONFIG_DIR)
    renamed = load_config(custom)

    assert renamed.identity.assistant_name == "Aurora"
    assert renamed.identity.wake_word == "Aurora"
    # Voice identity and language policy are untouched by a rename.
    assert renamed.voice == original.voice
    assert renamed.language == original.language


def test_env_override(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("JARVIS_ASSISTANT_NAME", "Vega")
    monkeypatch.setenv("JARVIS_WAKE_WORD", "Hey Vega")
    config = load_config(CONFIG_DIR)
    assert config.identity.assistant_name == "Vega"
    assert config.identity.wake_word == "Hey Vega"


def test_blank_name_rejected(tmp_path: Path):
    custom = tmp_path / "config"
    custom.mkdir()
    for name in ("assistant.yaml", "language.yaml", "voices.yaml", "pronunciation.yaml"):
        custom.joinpath(name).write_text(
            (CONFIG_DIR / name).read_text(encoding="utf-8"), encoding="utf-8"
        )
    identity = yaml.safe_load((custom / "assistant.yaml").read_text())
    identity["wake_word"] = "   "
    (custom / "assistant.yaml").write_text(yaml.safe_dump(identity), encoding="utf-8")

    with pytest.raises(Exception):
        load_config(custom)


def test_find_config_dir_from_subdirectory():
    found = find_config_dir(PROJECT_ROOT / "src" / "jarvis")
    assert found == CONFIG_DIR
