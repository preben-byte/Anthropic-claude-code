"""Jarvis CLI (brief §18). Every command supports --json for machine output.

Only commands that actually work today are registered; commands for later
phases are added when their phase lands, so `--help` never advertises
functionality that does not exist.
"""

from __future__ import annotations

import json as jsonlib
from pathlib import Path

import typer
import yaml

from jarvis.config import find_config_dir, load_config
from jarvis.secrets import get_secret, load_env_local
from jarvis.voice_lab.adapters import get_adapter, validate_api_key
from jarvis.voice_lab.candidates import generate_candidates
from jarvis.voice_lab.texts import STRESS_ITEMS, TEST_TEXT_EN, TEST_TEXT_MIXED

app = typer.Typer(help="Jarvis — personal AI operating system (working name).")
voice_app = typer.Typer(help="Voice Lab commands.")
models_app = typer.Typer(help="Model registry commands.")
app.add_typer(voice_app, name="voice")
app.add_typer(models_app, name="models")


def _project_root() -> Path:
    return find_config_dir().parent


def _emit(payload: dict, as_json: bool) -> None:
    if as_json:
        typer.echo(jsonlib.dumps(payload, indent=2, ensure_ascii=False))
    else:
        for key, value in payload.items():
            typer.echo(f"{key}: {value}")


@app.command()
def doctor(json: bool = typer.Option(False, "--json")) -> None:
    """Check configuration and service readiness. Read-only, never writes."""
    checks: dict[str, str] = {}
    ok = True

    try:
        config_dir = find_config_dir()
        checks["config_dir"] = str(config_dir)
        load_env_local(config_dir.parent)
        config = load_config(config_dir)
        checks["config"] = "ok"
        checks["assistant_name"] = config.identity.assistant_name
        checks["wake_word"] = config.identity.wake_word
        checks["stt_language"] = config.language.listen.primary_language
        checks["tts_language"] = config.language.speak.language
    except Exception as exc:  # noqa: BLE001 — doctor reports, never crashes
        checks["config"] = f"FAIL: {exc}"
        ok = False

    # Presence and validity only — never the value.
    api_key = get_secret("ELEVENLABS_API_KEY")
    if not api_key:
        checks["elevenlabs_api_key"] = "missing (mock mode)"
    else:
        verdict = validate_api_key(api_key)
        if verdict is True:
            checks["elevenlabs_api_key"] = "valid"
        elif verdict is False:
            checks["elevenlabs_api_key"] = "invalid (using mock)"
        else:
            checks["elevenlabs_api_key"] = "present (api unreachable)"
    checks["voice_lab_mode"] = get_adapter().provider_name

    manifest_path = Path(checks.get("config_dir", ".")) / "voice_manifest.json"
    checks["voice_manifest"] = "present" if manifest_path.is_file() else "not yet created (Phase 1 in progress)"

    checks["status"] = "ok" if ok else "fail"
    _emit(checks, json)
    raise typer.Exit(0 if ok else 1)


@app.command("config")
def show_config(json: bool = typer.Option(False, "--json")) -> None:
    """Show the effective (merged) configuration."""
    load_env_local(_project_root())
    config = load_config()
    payload = config.model_dump(mode="json")
    typer.echo(jsonlib.dumps(payload, indent=2, ensure_ascii=False))


@voice_app.command("test")
def voice_test(
    out: Path = typer.Option(None, help="Output directory (default: var/voice-test)"),
    json: bool = typer.Option(False, "--json"),
) -> None:
    """Synthesize the fixed test texts with the active adapter."""
    root = _project_root()
    load_env_local(root)
    adapter = get_adapter()
    out_dir = out or root / "var" / "voice-test"

    results = []
    for name, text in (
        ("english", TEST_TEXT_EN),
        ("mixed_norwegian_names", TEST_TEXT_MIXED),
        ("stress_items", ". ".join(STRESS_ITEMS)),
    ):
        result = adapter.synthesize(text, "voicelab-smoketest", out_dir / f"{name}.wav")
        results.append(
            {
                "sample": name,
                "audio": str(result.audio_path),
                "provider": result.provider,
                "mock": result.mock,
                "latency_ms": round(result.latency_ms, 1),
            }
        )

    _emit({"samples": results if json else len(results), "out_dir": str(out_dir),
           "mode": adapter.provider_name}, json)


@voice_app.command("candidates")
def voice_candidates(
    out: Path = typer.Option(None, help="Output directory (default: var/voice-candidates)"),
    json: bool = typer.Option(False, "--json"),
) -> None:
    """Generate the blind-coded candidate set A01–D03 for round 1."""
    root = _project_root()
    load_env_local(root)
    adapter = get_adapter()
    out_dir = out or root / "var" / "voice-candidates"
    candidates = generate_candidates(adapter, out_dir)
    _emit(
        {
            "candidates": len(candidates),
            "blind_codes": ", ".join(c.blind_code for c in candidates),
            "out_dir": str(out_dir),
            "mode": adapter.provider_name,
            "note": "Round 1 is blind: use blind_listing.json only.",
        },
        json,
    )


@voice_app.command("listen")
def voice_listen(
    dir: Path = typer.Option(None, help="Candidates directory (default: var/voice-candidates)"),
    port: int = typer.Option(7801, help="Local port for the listening test"),
) -> None:
    """Serve the blind listening test page for round 1 scoring."""
    from jarvis.voice_lab.listening_test import serve

    root = _project_root()
    candidates_dir = dir or root / "var" / "voice-candidates"
    if not (candidates_dir / "blind_listing.json").is_file():
        typer.echo("No candidates found — run `jarvis voice candidates` first.")
        raise typer.Exit(1)
    typer.echo(f"Åpne http://localhost:{port}/listening_test.html i nettleseren.")
    typer.echo("Avslutt med Ctrl+C. Scores lagres i scores/ underveis.")
    serve(candidates_dir, port)


@models_app.command("list")
def models_list(json: bool = typer.Option(False, "--json")) -> None:
    """List model roles from config/models.yaml."""
    models_file = find_config_dir() / "models.yaml"
    data = yaml.safe_load(models_file.read_text(encoding="utf-8")) or {}
    roles = data.get("model_roles", {})
    if json:
        typer.echo(jsonlib.dumps(roles, indent=2, ensure_ascii=False))
    else:
        for role, spec in roles.items():
            preferred = spec.get("preferred") or "(decided by evals)"
            typer.echo(f"{role:15s} {preferred:30s} {spec.get('description', '')}")


if __name__ == "__main__":
    app()
