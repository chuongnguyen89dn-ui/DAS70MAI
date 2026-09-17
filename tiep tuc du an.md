# TIEP TUC DU AN — DAS70MAI

> Append-only project handoff. Khong xoa/sua lich su cu; moi moc cong viec moi ghi tiep xuong duoi.

## 2026-09-17 — Khoi tao CodeLocal

Trang thai: VERIFIED (repository workspace)

- Da kich hoat co che lam viec lien tuc CodeLocal cho repo DAS70MAI.
- File quy tac: `CODELOCAL.md`.
- Repo la noi luu source, quyet dinh ky thuat, ket qua test/build va tien do de phien sau tiep tuc dung trang thai hien tai.
- Quy trinh: inspect -> diagnose -> edit -> test/build -> verify -> record.
- Khong danh dau tinh nang la VERIFIED neu chi moi commit code.

### Huong du an hien tai
- Thiet bi camera: 70mai A500S.
- Dau ra muc tieu: iPhone.
- Khong dung camera iPhone thay cho camera A500S.
- Da biet A500S co the ket noi stream; van de can nghien cuu va do thuc te la do tre.
- Uu tien be/tai su dung implementation 70mai da co va co bang chung thay vi tu doan giao thuc.
- AI/ADAS se duoc xem xet tren stream A500S sau khi duong stream duoc xac minh.

### Viec chua lam
- CHUA XAC MINH: source nen 70mai/iOS chua duoc dua vao repo.
- CHUA XAC MINH: chua co build iPhone.
- CHUA XAC MINH: chua do latency A500S trong implementation cua repo.
- CHUA XAC MINH: chua chot module AI/ADAS.

## 2026-09-17 — Camera test source + compatibility baseline

Trang thai: IMPLEMENTED, NOT VERIFIED

- Yeu cau moi thay the huong camera cu: nguoi dung tu chon `70mai A500S` hoac `iPhone Rear`; khong tu dong fallback.
- `iPhone Rear` la nguon test/development khi khong co A500S tai cho; tuyet doi khong dung selfie/front camera.
- Hai nguon dung chung CVPixelBuffer -> AI/ADAS pipeline va latest-frame-wins.
- Da them manual source coordinator, rear AVCapture source, segmented source picker va common ADAS inference boundary tren branch `feature-dual-source`.
- Chot baseline hien tai: iOS 16.0+ de phu hop IPCamKit (iOS 16+/Swift 6) va app Ultralytics hien tai.
- iPhone 14 Pro (A16) la primary physical test target hien tai.
- Cac iPhone iOS 16 khac chi la compatibility candidate cho den khi co benchmark thuc te; khong tu suy dien may cu chay ADAS real-time tot.
- Them `docs/COMPATIBILITY.md` de theo doi device/chip, FPS, inference p50/p95, end-to-end frame age, thermal va memory.
- AI huong Core ML/Vision; model nano-class ban dau. Khong nang minimum iOS neu khong co ly do do duoc.

### Viec tiep theo
- Tao project iOS buildable voi deployment target 16.0.
- Tich hop upstream YOLO iOS thay vi tu viet inference.
- Build/test camera sau tren iPhone va ghi benchmark.
- Tich hop IPCamKit/A500S sau khi pipeline iPhone test chay.

## 2026-09-17 — Build + live rear preview + YOLO pipeline

Trang thai: IMPLEMENTED, PARTLY BUILD-VERIFIED

- VERIFIED bang GitHub Actions: XcodeGen project va iOS Simulator build da thanh cong truoc khi noi inference runtime; live rear-camera preview source van can iPhone vat ly de runtime-verify.
- Da them camera permission handling, `AVCaptureVideoPreviewLayer`, rear-camera start/stop va manual source UI.
- Da tich hop Swift Package `UltralyticsYOLO`; CI da resolve va compile upstream package 8.9.14.
- Da them `UltralyticsDetectionEngine`: CVPixelBuffer -> CIImage -> YOLO detect -> normalized boxes -> road-object filter.
- Da them bounding-box overlay, road object filter va forward-risk visual heuristic. Risk heuristic CHUA PHAI TTC/FCW da hieu chuan.
- Da noi `ADASViewModel`: rear-camera frames -> latest-frame pipeline -> YOLO -> detections -> overlay/risk UI.
- CI run #15 phat hien Swift 6 Sendable error khi actor nhan `CVPixelBuffer`; da sua engine thanh nonisolated thread-safe class de khong gui CVPixelBuffer qua actor boundary rieng cua engine. Dang cho CI xac nhan fix.
- Da sua `CODELOCAL.md` theo policy camera moi: user chon thu cong A500S/iPhone Rear, khong auto fallback, khong front camera.

### Blocker vat ly
- CHUA XAC MINH tren iPhone 14 Pro: camera preview, YOLO model download/cache, FPS/inference latency, bounding-box alignment va thermal.
- CHUA XAC MINH A500S: RTSP endpoint/protocol va latency tren camera that.

### Tiep theo
- Fix den khi CI xanh voi full YOLO/UI chain.
- Sau CI xanh, them metrics inference/frame-age va canh bao audio/haptic co debounce.
- Sau do tich hop A500S RTSP vao cung VideoSource/CVPixelBuffer pipeline; khong thay doi source tu dong.

## 2026-09-17 — Full YOLO/UI chain build xanh + model URL duoc upstream xac nhan

Trang thai: BUILD-VERIFIED, RUNTIME NOT VERIFIED

- VERIFIED: GitHub Actions iOS Build run #20 thanh cong tren commit `f68b996`, sau khi bo actor isolation khoi `CVPixelBuffer` inference boundary.
- VERIFIED upstream: UltralyticsYOLO README hien tai chinh thuc dung URL `https://github.com/ultralytics/yolo-ios-app/releases/download/v8.3.0/yolo26n.mlpackage.zip` cho official hosted Core ML model; URL trong DAS70MAI khong con la gia dinh tu doan.
- VERIFIED upstream: package co san `YOLOCamera`/`YOLOView` cho realtime camera, ho tro cameraPosition `.back`; DAS70MAI van giu common custom CVPixelBuffer pipeline de cung mot inference path co the nhan ca iPhone Rear va A500S.
- Upstream package/release license: AGPL-3.0; neu phat hanh thuong mai can xu ly licensing phu hop, khong coi la permissive dependency.
- CHUA VERIFIED runtime: model tai/cache thanh cong tren iPhone, detections thuc, overlay alignment, FPS/frame-age/thermal.
- Uu tien tiep: runtime observability + warning debounce; sau do A500S RTSP adapter vao cung pipeline, khong auto switch source.

## 2026-09-17 — Build #36 xanh + warning feedback

Trang thai: BUILD-VERIFIED TO #36; NEW FEEDBACK IMPLEMENTED, NOT YET VERIFIED

- VERIFIED: GitHub Actions iOS Build run #36 success tren commit `a3fc891` (`fix: avoid sending A500S pixel buffer to MainActor`).
- A500S decoded frame van vao chung `VideoFrame/CVPixelBuffer -> ADASPipeline`; preview UI chi nhan CGImage immutable de tranh Swift 6 Sendable/MainActor violation.
- Da them `WarningFeedbackController`: caution rung medium; warning dung warning haptic + system sound, chi kich hoat sau `WarningDebouncer`, co cooldown 1.5s de tranh spam.
- Reset feedback khi dung/chuyen source; khong thay doi manual source policy va khong auto fallback.
- CI moi da duoc trigger sau thay doi feedback; chua danh dau BUILD-VERIFIED cho thay doi nay cho den khi run xanh.
- Blocker vat ly van con: iPhone 14 Pro runtime (rear preview/model/detection/overlay/thermal) va A500S that (RTSP compatibility + end-to-end latency).

## 2026-09-17 — Physical rear test + bundled YOLO recovery

Trang thai: REAR CAMERA RUNTIME VERIFIED; YOLO/LANE RUNTIME NOT VERIFIED

- VERIFIED tren iPhone vat ly tu anh test nguoi dung: app launch, UI va `iPhone Rear` live preview hoat dong; static yellow `LANE GUIDE` hien dung.
- Anh test Build #46 cho thay `YOLO loading`, `lanes 0`, inference/age = 0 ms: day la bang chung YOLO runtime chua chay va lane detector chua cho ket qua; khong danh dau hai muc nay VERIFIED.
- Da them Sound va Vibration toggle rieng, mac dinh bat, de nguoi dung chu dong tat/mo feedback.
- Build #50 VERIFIED CI success: workflow tai official yolo26n mlpackage, dua model vao app va fail build neu khong tim thay model trong device .app.
- Da doi `UltralyticsDetectionEngine` khoi remote URL sang dung upstream Ultralytics 8.9.4 bundled-model API `YOLO("yolo26n", task: .detect, ...)`; upstream resolver tim `yolo26n.mlmodelc` roi `.mlpackage` trong Bundle.main.
- Build #51 VERIFIED CI success tren commit `5dba96e` voi local bundled model loading path.
- Da them inference error propagation tu ADASPipeline -> ViewModel -> UI. Lan test tiep UI se hien `YOLO READY` khi co inference result hoac `YOLO ERROR · <detail>` neu model/runtime that bai, thay vi treo `YOLO loading` vo han.
- CHUA VERIFIED tren device: local yolo26n load thanh cong, real detection boxes, latency, lane candidates, warning trigger.
- Blocker A500S van la camera vat ly: RTSP compatibility va end-to-end latency chua co runtime evidence.

## 2026-09-17 — Restore xADAS A500S VLC path after physical VLC comparison

Trang thai: IMPLEMENTED, CI/RUNTIME NOT YET VERIFIED

- User da xac nhan A500S phat video that trong VLC bang `rtsp://192.168.0.1/00000000`; giu co dinh endpoint nay, khong tiep tuc doan endpoint khac.
- Doi chieu truc tiep upstream `hmtnvac-cpu/xADAS-iOS` `SeventyMaiPlayerView.swift` voi `A500SRTSPSource.swift` phat hien DAS70MAI da bo mat buoc quan trong cua xADAS: `VLCMediaPlayer.drawable` duoc gan vao mot `UIView` truoc khi `play()`. VLC co the vao state `.playing` nhung khong tao video output dung cho snapshot neu khong co drawable.
- Da khoi phuc dung huong xADAS: tao/giu private VLC drawable 960x540, gan drawable truoc play, delay play 0.25s, giu network/live caching 180ms, clock jitter/synchro 0, drop/skip late frames.
- Da khoi phuc `frameProcessing` gate cua xADAS de khong snapshot/ghi file chong len frame dang chuyen thanh CVPixelBuffer.
- Sua false-positive: `.playing` khong con duoc coi la A500S streaming. Chi khi `snapshotTaken` nhan anh decode that moi phat state `.streaming`, sau do frame van vao chung CVPixelBuffer -> AI/ADAS pipeline.
- KHONG danh dau VERIFIED: can GitHub Actions build xanh va test tren iPhone/A500S that. Neu build xanh, ban nay la ban can cai de test lai A500S truoc khi thay doi transport tiep.
