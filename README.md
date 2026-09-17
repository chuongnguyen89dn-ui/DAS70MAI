# DAS70MAI

iPhone ADAS companion designed around a 70mai A500S dashcam.

## Camera policy

1. Prefer the 70mai A500S RTSP/RTP stream whenever it is available.
2. If A500S is unavailable, automatically fall back to the **rear iPhone camera only**.
3. Never use the front/selfie camera.
4. Both sources feed the same `CVPixelBuffer -> AI -> ADAS` pipeline.
5. When A500S becomes available again, switch back to it.

## Low-latency policy

The AI pipeline is latest-frame-wins. Stale frames are replaced instead of queued so inference does not create an ever-growing delay.

## Status

Dual-source source/coordinator and native rear-camera source are IMPLEMENTED, NOT VERIFIED. A500S RTSP integration, Core ML AI integration and full iPhone build are still pending verification.
