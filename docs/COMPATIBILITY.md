# DAS70MAI Compatibility Baseline

Updated: 2026-09-17

## Deployment target

**iOS 16.0+** is the current project baseline.

Reason: the selected RTSP candidate IPCamKit requires iOS 16.0+ and Swift 6. The Ultralytics YOLO iOS inference package itself supports an older floor, but its current example app targets iOS 16. Using iOS 16 therefore avoids raising the OS requirement solely for AI while keeping the modern RTSP path available.

Do not raise the deployment target without a measured technical reason.

## Device policy

There are two different meanings of support:

1. **Install/API compatibility** — an iPhone can run iOS 16 and the required frameworks.
2. **ADAS performance support** — the device can sustain the required camera + decode + Core ML + overlay workload without unacceptable latency or thermal throttling.

The second category must be established by on-device benchmarks; it must not be guessed from API compatibility.

## Current validation matrix

| Device class | Status | Notes |
|---|---|---|
| iPhone 14 Pro (A16) | PRIMARY TEST TARGET | Must be tested with rear camera first, then A500S stream |
| Other iOS 16-capable iPhones | COMPATIBILITY CANDIDATE | Build/API support may exist; real-time ADAS performance not yet verified |

No older iPhone is currently labelled VERIFIED until FPS, end-to-end frame age, thermal behavior and memory are measured on that hardware.

## Performance gates

For each physical iPhone test record:

- iOS version and device/chip
- selected camera source
- capture/stream resolution and FPS
- model name, input size and quantization
- inference time (median / p95)
- end-to-end frame age at rendered overlay
- dropped/replaced frames
- thermal state over a sustained drive/test
- memory use

The app should use a nano-class Core ML detector initially and latest-frame-wins ingestion. Model size/input resolution may later be selected by measured device tier rather than hard-coding one workload for every iPhone.

## AI baseline

Use Core ML/Vision for broad Apple-device coverage. The current Ultralytics iOS package has an iOS 13 library floor while its main example app targets iOS 16. Current Ultralytics guidance recommends Core ML for broad Apple compatibility and real-time iOS inference.

## RTSP baseline

IPCamKit is the current preferred RTSP candidate because it is pure Swift, supports H.264/H.265, TCP/UDP RTP/RTCP and outputs video suitable for VideoToolbox. Its current requirement is iOS 16+ / Swift 6.

A500S protocol/endpoints and actual latency still require physical-camera verification.
