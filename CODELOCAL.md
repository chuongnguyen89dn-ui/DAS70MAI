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
- iOS 16.0+; iPhone-only. iPhone 14 Pro/A16 is the primary physical performance test target.
- Camera source is selected manually by the user: `70mai A500S` or `iPhone Rear`.
- `iPhone Rear` is a development/test source for times when the A500S is not physically available.
- Never use the front/selfie camera.
- Never automatically switch camera source when the A500S disconnects or reconnects.
- Both camera sources must feed the same `CVPixelBuffer -> latest-frame-wins -> AI/Core ML -> ADAS -> UI/alerts` pipeline.
- Rear iPhone camera is used first to develop and validate AI/ADAS; A500S RTSP/RTP is integrated into the same pipeline afterward.
- Prefer proven upstream 70mai/RTSP/YOLO implementations over guessed protocols or custom reinvention.
- Do not raise the iOS minimum without a verified dependency or measured technical reason.

## State labels
- VERIFIED: actual build/runtime/device evidence exists.
- IMPLEMENTED, NOT VERIFIED: implementation exists but runtime/device verification is pending.
- CAN SUA: known issue remains.
- CHUA XAC MINH: evidence is insufficient.
