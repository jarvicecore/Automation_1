"""Hello, World -- on steroids.

It still says hello. It just also tells you, with proof, exactly which build of
itself is doing the talking.

    GET /          the greeting, plus a provenance card
    GET /healthz   liveness
    GET /version   what am I, and can I prove it
    GET /extract   the data extract, with its schema contract
"""

from __future__ import annotations

from fastapi import FastAPI, Response
from fastapi.responses import HTMLResponse, JSONResponse

from . import extract, provenance

app = FastAPI(
    title="Secure Release Pipeline extract service",
    description="Hello, World, with a verifiable chain of custody.",
)


@app.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/version")
def version(response: Response) -> dict:
    """What is running here, and does it match what the pipeline says?

    Returns HTTP 200 when the service can prove its identity, and 409 when it
    cannot. The smoke test keys off the status code, so a service running bytes
    that nobody approved fails its own deployment.
    """
    p = provenance.load()
    if not p.self_verified:
        response.status_code = 409
    return p.as_dict()


@app.get("/extract")
def run_extract() -> JSONResponse:
    """The extract, plus the result of validating it against its own contract."""
    result = extract.run()
    problems = extract.validate(result)

    payload = {
        **result,
        "environment": provenance.load().environment,
        "contract_valid": not problems,
        "problems": problems,
    }
    return JSONResponse(payload, status_code=200 if not problems else 422)


@app.get("/", response_class=HTMLResponse)
def index() -> str:
    p = provenance.load()
    rows = extract.run()["rows"]

    if p.self_verified:
        badge, colour, note = (
            "PROVENANCE VERIFIED",
            "#1a7f37",
            "The bytes running here match the digest the promotion PR was approved with.",
        )
    else:
        badge, colour, note = (
            "UNVERIFIED",
            "#cf222e",
            "This service cannot prove its identity. Running outside a deployment, "
            "or the artifact does not match what the pipeline recorded.",
        )

    greetings = "\n".join(
        f"<tr><td>{r['id']}</td><td>{r['language']}</td>"
        f"<td><code>{r['code']}</code></td><td>{r['greeting']}</td></tr>"
        for r in rows
    )

    return f"""
<!doctype html>
<meta charset="utf-8">
<title>Hello, World — {p.environment}</title>
<style>
  :root {{ color-scheme: light dark; }}
  body {{ font: 16px/1.6 system-ui, sans-serif; max-width: 54rem;
         margin: 3rem auto; padding: 0 1.5rem; }}
  h1 {{ font-size: 2.4rem; margin: 0 0 .25rem; }}
  .env {{ display: inline-block; padding: .15rem .6rem; border-radius: 999px;
          background: #6366f1; color: #fff; font-size: .8rem;
          letter-spacing: .08em; text-transform: uppercase; }}
  .badge {{ display: inline-block; padding: .15rem .6rem; border-radius: 999px;
            background: {colour}; color: #fff; font-size: .8rem;
            letter-spacing: .08em; }}
  table {{ border-collapse: collapse; width: 100%; margin: 1rem 0 2rem; }}
  th, td {{ text-align: left; padding: .45rem .6rem;
            border-bottom: 1px solid color-mix(in srgb, currentColor 15%, transparent); }}
  th {{ font-size: .75rem; text-transform: uppercase; letter-spacing: .08em; opacity: .6; }}
  code {{ font: .85em ui-monospace, monospace; word-break: break-all; }}
  .note {{ opacity: .7; font-size: .9rem; }}
</style>

<h1>Hello, World.</h1>
<p><span class="env">{p.environment}</span> &nbsp; <span class="badge">{badge}</span></p>
<p class="note">{note}</p>

<h2>Chain of custody</h2>
<table>
  <tr><th>Release</th><td><code>{p.release_tag}</code></td></tr>
  <tr><th>Version</th><td><code>{p.version}</code></td></tr>
  <tr><th>Commit</th><td><code>{p.commit}</code></td></tr>
  <tr><th>Built at</th><td><code>{p.built_at}</code></td></tr>
  <tr><th>Digest the pipeline promoted</th><td><code>{p.expected_sha256}</code></td></tr>
  <tr><th>Digest actually running</th><td><code>{p.observed_sha256 or "unknown"}</code></td></tr>
</table>

<h2>Extract</h2>
<table>
  <tr><th>id</th><th>language</th><th>code</th><th>greeting</th></tr>
  {greetings}
</table>

<p class="note">
  Promote this release to another environment and load that one too. The
  <em>digest actually running</em> will be identical — that is binary promotion,
  and this page is the receipt.
</p>
"""
