import SwiftUI

@main
struct RHEOApp: App {
    init() {
        // 停用視窗狀態還原：編輯器沒有可還原的文件狀態（位移場本來就不可續）。
        // 不停的話，App 被強殺後留下的髒 saved state 會讓下次啟動「靜默還原失敗」
        // ——事件迴圈正常跑、選單都在，就是永遠不建內容視窗（2026-08-14 踩到，用
        // -ApplePersistenceIgnoreState YES 驗出病根）。
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }
    var body: some Scene {
        WindowGroup("RHEO") {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
                .preferredColorScheme(.dark)
        }
    }
}
