# RHEO（Mac 版）

流動扭曲編輯器。照片或影片放進來，用滑鼠／觸控板在畫面上抹，
效果沿著位移場長出來；放開手，它自己慢慢流回去。
⌘S 截當下那格、⌘R 把整段流動錄成影片——輸出的永遠是畫布本身，檔案裡沒有介面。

原本是 iOS 相機 App（採集動態材質用），這份是桌面編輯器版。

## 技術

- Mac 原生 SwiftUI＋Metal，無第三方相依
- 21 種效果（鏡片／液化／場域／玻璃感／慢快門／拖曳流動）共用一張位移場：
  筆刷把向量寫進場裡，每幀「先擴散、再衰減」＝流動地回來
- 畫布＝來源解析度（上限 4096），位移場獨立解析度（長邊 1024）——
  互動成本不隨照片大小長
- 影片：`AVPlayerItemVideoOutput` 逐幀進 Metal，播放中即時抹；
  錄製走 AVFoundation 零拷貝，位元率跟像素數走

## 建置

需要 [xcodegen](https://github.com/yonaskolb/XcodeGen)：

```bash
xcodegen generate
xcodebuild -project RHEOMac.xcodeproj -scheme RHEOMac -configuration Release \
  -destination 'platform=macOS' build
```

`project.yml` 裡的 `DEVELOPMENT_TEAM` 換成你自己的（或刪掉用本機簽名）。

## 測試掛鉤（驗證不靠螢幕）

```bash
RHEO_OPEN=照片.jpg RHEO_TEST=1 RHEO_SAVE=out.png \
  ./RHEO.app/Contents/MacOS/RHEO -ApplePersistenceIgnoreState YES
```

自動開檔→抹一筆→存 PNG，一條指令驗完整條管線。
另有 `RHEO_SAVE_MOV=out.mp4`（自動錄 2.5 秒）與 `RHEO_FX=<mode>`（指定效果）。
`-ApplePersistenceIgnoreState YES` 必帶——同 bundle id 已有實例在跑時，
第二個實例會因視窗還原交握靜默不建視窗。

## 授權

GPL-3.0。
