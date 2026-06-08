# Walk v1 — Production-Hardened Engine (Design Spec)

**Date:** 2026-06-07
**Author:** Dennis (Luceo Studio), with Claude
**Status:** Approved design — pending spec review, then implementation plan

---

## 1. Background

Walk Agent (a.k.a. "Walk"; repo dir `promo-agent`) is an autonomous web agent that turns a
**start URL + a goal** into a polished **1920×1080 @ 30fps walkthrough/tutorial MP4** with no human
in the loop. It won the **NVIDIA Agent Hackathon at GTC Taipei 2026** (solo, under the Luceo Studio
brand). Architecture is two-pass: a **discovery pass** inside the NemoClaw sandbox (Nemotron picks
each action over `connectOverCDP`, capturing DOM text + accessibility tree — no screenshots to the
model), and a **render pass** on the host (Remotion `Explainer` composition), with `action-log.json`
as the only artifact crossing the sandbox boundary.

The prototype works but is fragile: a hand-run local stack that does not survive reboot, a sandbox
that can be bricked by `destroy`, version sprawl in the agent code, silent failure paths, and a known
security gap in the per-run allowlist.

## 2. Goal

Turn the hackathon-winning prototype into a **stable and fast** production engine — **without**
changing what it fundamentally is. This is an engineering hardening + performance pass, plus a
data-driven model upgrade, on the existing two-pass design.

Long-term north star (NOT this spec): a **revenue SaaS for documentation / DevRel teams** — *"CI/CD
for documentation"*, where tutorial videos auto-regenerate as the product ships. v1 is the solid
engine that later product surfaces are built on.

## 3. Locked decisions

| Decision | Choice |
| --- | --- |
| Product north star | Revenue SaaS, beachhead = docs/DevRel ("CI/CD for documentation") |
| v1 scope | Harden existing engine: **stable + fast** |
| v1 runtime | Single-instance / operator-run. **Cloud multi-tenant deferred to v2.** |
| Engineering posture | **A + C**: harden in place, driven by an eval harness. Defer containerization (B). |
| Model | **A/B Nemotron 3 Super vs Nemotron 3 Ultra**, adopt by data. |
| Repo strategy | New **private repo `walk`**, seeded from a **full-history mirror** of `promo-agent`. Original frozen + tagged. |

## 4. Non-goals (explicitly v2+)

- Cloud / multi-tenant hosting; the "NemoClaw-in-the-cloud" problem.
- New product surfaces: self-serve web app, CI/CD GitHub Action, hosted tutorial hub, public API/SDK.
- Navigating **login-gated / authenticated** in-product flows (v1 targets public docs/product pages).
- Billing, accounts, usage metering.
- Containerizing the full pipeline into orchestrated images (Approach B) — revisit when the v2 cloud
  push starts.

## 5. Repo & lineage

1. **Freeze the original** `denniswanglabs/promo-agent`:
   - Tag the winning commit `v1.0-gtc-taipei-winner` (immutable; the always-available fallback).
   - Commit the small README "Walk Agent" name-fix already made locally, plus a one-line pointer:
     *"Product development continues at → `walk`."*
   - Leave `main` otherwise untouched.
2. **Create the product repo** `walk` (private) as a **full-history mirror** of `promo-agent`, so the
   "productized from the GTC-winning agent" lineage is visible in the commit history.
3. All v1 work happens in `walk`. The original remains the untouched, prize-validated fallback that can
   be re-cloned or checked out at the tag at any time.

**Why duplicate-with-history (not fork, not branch):** a fork is built for contributing back upstream
and self-forks are awkward; a branch shares the original repo's identity/issues/"this is the
submission" framing. An independent repo with copied history gives lineage with a hard firewall.

## 6. Target architecture

Keep the winning two-pass design (discovery in sandbox → render on host, `action-log.json` bridge).
Refactor into clearly-bounded components, each with one responsibility:

1. **Orchestrator** — single entrypoint replacing the `tutorial-maker.sh` sprawl. Input `(url, goal,
   opts)`; runs the staged pipeline; returns a job result with status + structured logs.
2. **Agent core** — collapse `agent.sandbox-v25 / v26 / "content-is-v36"` into **one canonical,
   model-agnostic module**. The proposer model is a **config flag** (provider/model string), so
   Super↔Ultra is a one-line change. 8-action vocabulary unchanged.
3. **Sandbox image** — a reproducible Dockerfile that bakes chrome libs + node deps
   (`nemoclaw onboard --from`), so `destroy`/reboot can never brick it. One documented recovery command.
4. **Renderer** — the canonical Remotion `Explainer` path. The AutoOverlay fallback is removed or
   clearly demoted to end the dual-path confusion. *(Open question §11.)*
5. **Service** — Flask API (`:8082`) + static dashboard (`:8081`), supervised (restart-on-crash,
   `BROWSER=none`).
6. **Eval harness** — new; the measurement spine (§9).
7. **Policy/allowlist** — the security fix (§10).

Data flow (unchanged in shape): `orchestrator → sandbox(agent core → Chromium via CDP → Nemotron
loop) → action-log.json → host(renderer) → MP4`.

## 7. Reliability work ("stable")

- **Reproducible sandbox image** — ends the destroy-disaster; rebuilds identically every time.
- **Process supervision** — a LaunchAgent keeps the `:8081` / `:8082` / `poll.sh` stack alive across
  crashes and reboots; `BROWSER=none` (per the better-opn "Where is Arc?" gotcha).
- **Error handling** — retries with backoff on NIM calls and flaky actions; **fail-soft renders**
  (remove the `set -e` + grep silent-kill); per-run structured JSON logs + an artifact directory;
  resumable runs via formalized `.handoff` checkpoints.
- **Config over scattered shell env** — one schema'd config file.
- **Canonicalize** the agent versions; intentionally commit the current working-tree drift in `walk`.

## 8. Speed work ("fast")

- **Primary lever: fewer steps via a smarter proposer (Ultra).** Agent wall-clock is dominated by
  step count — each wrong click is a full extra DOM-capture + model round-trip — so a model that
  self-corrects beats a faster-but-dumber one.
- **Measure per-stage wall-clock** (sandbox startup vs discovery vs render) to find the real
  bottleneck before optimizing.
- **Candidate optimizations** (each validated by the harness, none assumed): keep the sandbox **warm**
  between runs (avoid cold recovery), **trim the DOM payload** sent to the model, tune render
  concurrency, cache static deps.

## 9. Eval harness + Ultra A/B (one data-driven spine)

- A fixed **suite of `(url, goal)` targets**: seed with the booth set (NemoClaw docs, Stripe,
  Wikipedia) plus a few real docs-site targets representative of the beachhead. Each target has a
  **checkable success assertion** (did it reach the goal?).
- A **runner** executes each target **K times** and records: success rate, step count, per-stage
  wall-clock, failure category, output path.
- Produces a **comparison report**: **Super vs Ultra**, and **before vs after** hardening.
- **Model decision rule:** adopt **Ultra** if it lifts success rate and/or cuts steps without an
  unacceptable latency/cost regression; otherwise keep **Super** and document why. Either way the
  "runs on NVIDIA's newest Nemotron" narrative remains available.
- The harness is also the regression gate for every later change.

**Ultra facts (for implementers):** model ID `nvidia/nemotron-3-ultra-550b-a55b`, served on the same
`integrate.api.nvidia.com/v1` endpoint Walk already uses (OpenAI-compatible, function calling). 550B
total / 55B active, 1M context, **text-only** (fine — Walk feeds DOM/a11y, no images). Released
2026-06-04. Per-token pricing not yet posted as of 2026-06-07; no independent tool-calling benchmark
yet — hence the A/B rather than a blind switch.

## 10. Security

- **Fix `auto-allowlist.sh`:** replace the loose CDN substring match with **exact host-suffix
  allowlisting**; add a **strict per-run mode** that resets the accumulated (~151-host) list; close or
  make-explicit the "the target URL is implicitly trusted" hole. Unit-tested (assert `static.evil.com`
  / `cdn-evil.com` / `assets.attacker.net` are now rejected).
- **Rotate** the two keys that previously leaked to chat (`NVIDIA_API_KEY`,
  `OPENCLAW_GATEWAY_TOKEN`). Keep all keys in env (`~/.zshrc` / `.env`), never in the repo.

## 11. Testing

- The **eval harness is the integration test** (end-to-end success on the suite + a fast known-good
  smoke target before any release).
- **Unit tests** on the pure pieces: `action-log` schema validation, allowlist policy logic (the
  security fix), DOM-trim, config parsing.

## 12. Sequencing (milestones for the plan phase)

- **M0** — Repo migration: freeze + tag `promo-agent`; create private `walk` from full mirror; commit
  drift; canonicalize agent versions.
- **M1** — Eval harness + **baseline** numbers (Super, current code).
- **M2** — Hardening: reproducible sandbox, supervision, error handling, security fix → re-measure.
- **M3** — **Ultra A/B** on the harness → decide and adopt.
- **M4** — Speed pass on the measured bottleneck → re-measure.

## 13. Success criteria

- A reboot and a `destroy`/recover cycle leave the engine fully working with no manual repair.
- A documented, repeatable bring-up; the dashboard stack self-heals.
- The eval suite runs green end-to-end and is the standing regression gate.
- **Measured** improvement vs the M1 baseline on success rate and/or wall-clock (numbers, not vibes).
- A recorded Super-vs-Ultra decision with the data behind it.
- The `auto-allowlist` security hole is closed with passing tests; leaked keys rotated.
- The original winner is frozen and tagged; all new work lives in `walk`.

## 14. Open questions / risks

- **AutoOverlay path:** remove entirely, or keep as a demoted fallback? (Leaning remove for
  simplicity; confirm before M2.)
- **Eval-suite targets:** confirm the seed targets truly represent the docs/DevRel beachhead.
- **Ultra cost/latency:** pricing unposted; if Ultra is materially slower or pricier per run, the
  decision rule may keep Super — acceptable, and the harness will make it explicit.
- **`RLIMIT_NPROC=512`** sandbox cap remains (BEAM parallelism limited); not blocking for BEAM=0 v1.
- Warm-sandbox reuse must not compromise per-run isolation/security — validate.
