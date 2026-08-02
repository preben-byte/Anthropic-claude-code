"""Blind listening test, round 1 (brief §6.5).

Generates a local, self-contained scoring page from blind_listing.json and
serves it with a stdlib HTTP server. The page shows ONLY blind codes and
audio — never variant briefs or provider descriptions. Scores are saved as
JSON files under scores/ in the candidates directory.
"""

from __future__ import annotations

import json
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

# Scoring criteria from the master brief §6.5, 1-5 each.
CRITERIA: list[tuple[str, str]] = [
    ("identity", "Stemmeidentitet"),
    ("authority", "Autoritet"),
    ("warmth", "Varme"),
    ("intelligence", "Intelligensinntrykk"),
    ("clarity", "Tydelighet"),
    ("british", "Britisk uttale"),
    ("norwegian", "Norsk uttale av navn"),
    ("technical", "Teknisk uttale"),
    ("comfort", "Langtidskomfort"),
    ("short_commands", "Korte kommandoer"),
    ("long_explanations", "Lengre forklaringer"),
]

# Disqualifying flag (checkbox, not a 1-5 score).
RECOGNIZABLE_KEY = "recognizable"
RECOGNIZABLE_LABEL = "Minner om en kjent person (diskvalifiserende)"

PAGE_NAME = "listening_test.html"
SCORES_DIR = "scores"


def build_page(candidates_dir: Path) -> Path:
    """Render the scoring page from blind_listing.json. Returns the path."""
    listing = json.loads(
        (candidates_dir / "blind_listing.json").read_text(encoding="utf-8")
    )

    cards = []
    for row in listing:
        code = row["blind_code"]
        players = "".join(
            f'<figure><figcaption>{Path(p).stem.replace("_", " ")}</figcaption>'
            f'<audio controls preload="none" src="{code}/{Path(p).name}"></audio></figure>'
            for p in row["samples"]
        )
        selects = "".join(
            f'<label>{label}<select name="{key}">'
            + '<option value="">-</option>'
            + "".join(f'<option value="{n}">{n}</option>' for n in range(1, 6))
            + "</select></label>"
            for key, label in CRITERIA
        )
        cards.append(
            f'<section class="card" data-code="{code}"><h2>{code}</h2>'
            f"{players}<div class=\"grid\">{selects}</div>"
            f'<label class="flag"><input type="checkbox" name="{RECOGNIZABLE_KEY}">'
            f" {RECOGNIZABLE_LABEL}</label>"
            f'<button onclick="saveScore(this)">Lagre score for {code}</button>'
            f'<span class="status"></span></section>'
        )

    html = f"""<!DOCTYPE html>
<html lang="nb">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Blind lyttetest — runde 1</title>
<style>
  body {{ font-family: system-ui, sans-serif; background: #14171a; color: #dfe6ea;
         max-width: 900px; margin: 0 auto; padding: 1.5rem; }}
  h1 {{ font-size: 1.4rem; }} h2 {{ color: #3fd2e0; margin: 0 0 .5rem; }}
  .card {{ background: #1d2126; border-radius: 10px; padding: 1rem 1.25rem; margin: 1rem 0; }}
  figure {{ margin: .4rem 0; }} figcaption {{ font-size: .8rem; color: #8fa0aa; }}
  audio {{ width: 100%; }}
  .grid {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(210px, 1fr));
           gap: .5rem .9rem; margin: .8rem 0; }}
  label {{ font-size: .85rem; display: flex; justify-content: space-between;
           align-items: center; gap: .5rem; }}
  select {{ background: #14171a; color: #dfe6ea; border: 1px solid #3a434b;
            border-radius: 5px; padding: .15rem .3rem; }}
  .flag {{ color: #e0a63f; justify-content: flex-start; margin-bottom: .6rem; }}
  button {{ background: #3fd2e0; color: #10262a; border: 0; border-radius: 6px;
            padding: .45rem .9rem; font-weight: 600; cursor: pointer; }}
  .status {{ margin-left: .75rem; font-size: .85rem; color: #7ee08f; }}
  p.help {{ color: #8fa0aa; font-size: .9rem; }}
</style>
</head>
<body>
<h1>Blind lyttetest — runde 1</h1>
<p class="help">Lytt til begge prøvene per kandidat og gi 1–5 på hvert kriterium
(5 er best). Kryss av hvis stemmen minner om en kjent person — slike kandidater
forkastes. Du kan ta pauser; lagrede scores huskes på disk.</p>
{''.join(cards)}
<script>
async function saveScore(btn) {{
  const card = btn.closest('.card');
  const payload = {{ blind_code: card.dataset.code, scores: {{}} }};
  card.querySelectorAll('select').forEach(s => {{
    if (s.value) payload.scores[s.name] = Number(s.value);
  }});
  payload.{RECOGNIZABLE_KEY} =
    card.querySelector('input[name="{RECOGNIZABLE_KEY}"]').checked;
  const res = await fetch('/score', {{
    method: 'POST',
    headers: {{'Content-Type': 'application/json'}},
    body: JSON.stringify(payload)
  }});
  card.querySelector('.status').textContent =
    res.ok ? 'Lagret ✓' : 'Feil ved lagring';
}}
</script>
</body>
</html>
"""
    page_path = candidates_dir / PAGE_NAME
    page_path.write_text(html, encoding="utf-8")
    return page_path


def save_score(candidates_dir: Path, payload: dict) -> Path:
    """Persist one candidate's scores as scores/<blind_code>.json."""
    code = str(payload.get("blind_code", "")).strip()
    if not code or not code.replace("-", "").isalnum():
        raise ValueError("invalid blind_code")
    scores_dir = candidates_dir / SCORES_DIR
    scores_dir.mkdir(parents=True, exist_ok=True)
    out = scores_dir / f"{code}.json"
    out.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")
    return out


class _Handler(SimpleHTTPRequestHandler):
    """Static file serving plus POST /score."""

    def __init__(self, *args, candidates_dir: Path, **kwargs):
        self._candidates_dir = candidates_dir
        super().__init__(*args, directory=str(candidates_dir), **kwargs)

    def do_POST(self):  # noqa: N802 — stdlib naming
        if self.path != "/score":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length", 0))
        try:
            payload = json.loads(self.rfile.read(length))
            save_score(self._candidates_dir, payload)
        except (ValueError, json.JSONDecodeError):
            self.send_error(400, "invalid score payload")
            return
        self.send_response(204)
        self.end_headers()

    def log_message(self, *args):  # keep the console quiet
        pass


def serve(candidates_dir: Path, port: int = 7801) -> None:
    """Blocking: serve the listening test until interrupted."""
    build_page(candidates_dir)
    handler = partial(_Handler, candidates_dir=candidates_dir)
    with ThreadingHTTPServer(("127.0.0.1", port), handler) as httpd:
        httpd.serve_forever()
