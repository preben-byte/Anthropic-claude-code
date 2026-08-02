"""Amended language policy (§7): Norwegian in, British English out — always,
unless Preben explicitly asks for Norwegian."""

from pathlib import Path

from jarvis.config import load_config

CONFIG_DIR = Path(__file__).resolve().parents[1] / "config"


def _policy():
    return load_config(CONFIG_DIR).language


def test_stt_optimised_for_norwegian():
    policy = _policy()
    assert policy.listen.primary_language == "nb-NO"
    assert policy.listen.auto_language_switch == "conservative"


def test_reply_is_british_english_even_for_norwegian_input():
    policy = _policy()
    assert policy.speak.language == "en-GB"
    # No explicit request → English, no matter what Preben spoke.
    assert policy.reply_language() == "en-GB"
    assert policy.reply_language(explicit_norwegian_request=False) == "en-GB"


def test_norwegian_reply_only_on_explicit_request():
    policy = _policy()
    assert policy.speak.reply_in_norwegian == "on_explicit_request_only"
    assert policy.reply_language(explicit_norwegian_request=True) == "nb-NO"


def test_norwegian_pronunciation_uses_lexicon():
    config = load_config(CONFIG_DIR)
    assert config.language.speak.norwegian_pronunciation == "lexicon"
    for term in ("Marivold", "Paradisbukta", "Beverdalen", "Golanhøyden"):
        entry = config.pronunciation.lookup(term)
        assert entry is not None, f"missing lexicon entry for {term}"
        assert entry.hint
