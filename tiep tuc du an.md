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
