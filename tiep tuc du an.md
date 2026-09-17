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
