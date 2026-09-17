# CodeLocal workspace — DAS70MAI

Status: ACTIVE
Initialized: 2026-09-17

## Operating mode
This repository is the persistent workspace for DAS70MAI. Continue from repository state instead of rebuilding project context each session.

1. Inspect existing source/state before editing.
2. Reuse verified upstream/open-source implementations where possible; do not guess protocols/APIs.
3. Keep changes small and reversible; do not replace architecture without evidence.
4. For clear tasks continue autonomously: inspect -> diagnose -> edit -> test/build -> verify -> record.
5. A commit is not proof a feature works. Runtime/build/device evidence is required for VERIFIED.
6. Do not delete working data/history merely to simplify a fix.
7. Record progress immediately in `tiep tuc du an.md`.

## DAS70MAI direction
- Target: iPhone workflow/application using a 70mai A500S as the camera source.
- Do not substitute the iPhone camera for the A500S camera stream.
- Establish and measure the existing 70mai stream path first, especially latency.
- Prefer proven 70mai protocol/stream implementations from existing projects over reverse-engineering from guesses.
- Add AI/ADAS components only on top of a verified camera-stream path.

## State labels
- VERIFIED: actual build/runtime/device evidence exists.
- IMPLEMENTED, NOT VERIFIED: implementation exists but runtime/device verification is pending.
- CAN SUA: known issue remains.
- CHUA XAC MINH: evidence is insufficient.
