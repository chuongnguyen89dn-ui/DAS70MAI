# DAS70MAI

iPhone ADAS companion designed around a 70mai A500S dashcam.

## Camera policy

The camera is selected manually in the app:

- **70mai A500S** — production/vehicle camera source via its stream.
- **iPhone Rear** — development/test source when the A500S is not physically available.

There is no automatic fallback or automatic reconnect switching. Losing or regaining the A500S connection does not change the selected source. The front/selfie camera is never used. Both sources feed the same `CVPixelBuffer -> AI -> ADAS` pipeline so ADAS can be developed and tested with the rear iPhone camera before testing against the A500S.

## Low-latency policy

The AI pipeline is latest-frame-wins. Stale frames are replaced instead of queued so inference does not create an ever-growing delay.

## Status

Manual source selector, common video boundary, rear-camera capture and common latest-frame inference pipeline are IMPLEMENTED, NOT VERIFIED. A500S RTSP integration, concrete Core ML/YOLO inference and full iPhone build remain pending verification.
