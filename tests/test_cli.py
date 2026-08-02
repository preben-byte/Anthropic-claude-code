import json

from typer.testing import CliRunner

from jarvis.cli import app

runner = CliRunner()


def test_doctor_runs_clean():
    result = runner.invoke(app, ["doctor"])
    assert result.exit_code == 0
    assert "assistant_name: Jarvis" in result.output
    assert "mock" in result.output


def test_doctor_json_mode():
    result = runner.invoke(app, ["doctor", "--json"])
    assert result.exit_code == 0
    payload = json.loads(result.output)
    assert payload["status"] == "ok"
    assert payload["tts_language"] == "en-GB"
    assert payload["stt_language"] == "nb-NO"
    # Secret values are never printed, only presence.
    assert payload["elevenlabs_api_key"] in ("present", "missing (mock mode)")


def test_voice_test_in_mock_mode(tmp_path):
    result = runner.invoke(app, ["voice", "test", "--out", str(tmp_path)])
    assert result.exit_code == 0
    assert (tmp_path / "english.wav").is_file()
    assert (tmp_path / "mixed_norwegian_names.wav").is_file()


def test_models_list():
    result = runner.invoke(app, ["models", "list"])
    assert result.exit_code == 0
    assert "strategist" in result.output
