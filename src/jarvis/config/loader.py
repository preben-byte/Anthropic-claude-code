"""Load YAML configuration into the typed schema.

Environment overrides (JARVIS_ASSISTANT_NAME, JARVIS_WAKE_WORD) exist so the
name can be changed per-deployment without editing files, e.g. on a satellite
device. Secrets are never read here — see jarvis.secrets.
"""

from __future__ import annotations

import os
from pathlib import Path

import yaml

from .schema import (
    AssistantIdentity,
    JarvisConfig,
    LanguagePolicy,
    PronunciationLexicon,
    VoiceConfig,
)

CONFIG_FILES = {
    "identity": "assistant.yaml",
    "language": "language.yaml",
    "voice": "voices.yaml",
    "pronunciation": "pronunciation.yaml",
}


def find_config_dir(start: Path | None = None) -> Path:
    """Walk upwards from `start` (or CWD) until a `config/` directory is found."""
    current = (start or Path.cwd()).resolve()
    for candidate in [current, *current.parents]:
        config_dir = candidate / "config"
        if (config_dir / CONFIG_FILES["identity"]).is_file():
            return config_dir
    raise FileNotFoundError(
        "No config/assistant.yaml found. Run from inside the project, "
        "or pass the config directory explicitly."
    )


def _read_yaml(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as fh:
        data = yaml.safe_load(fh)
    return data or {}


def load_config(config_dir: Path | None = None) -> JarvisConfig:
    config_dir = config_dir or find_config_dir()

    identity_data = _read_yaml(config_dir / CONFIG_FILES["identity"])
    if name_override := os.environ.get("JARVIS_ASSISTANT_NAME"):
        identity_data["assistant_name"] = name_override
    if wake_override := os.environ.get("JARVIS_WAKE_WORD"):
        identity_data["wake_word"] = wake_override

    return JarvisConfig(
        identity=AssistantIdentity.model_validate(identity_data),
        language=LanguagePolicy.model_validate(
            _read_yaml(config_dir / CONFIG_FILES["language"])
        ),
        voice=VoiceConfig.model_validate(
            _read_yaml(config_dir / CONFIG_FILES["voice"])
        ),
        pronunciation=PronunciationLexicon.model_validate(
            _read_yaml(config_dir / CONFIG_FILES["pronunciation"])
        ),
    )
