<!-- 純文字版，由 https://tools.arminkao.com/research/ig-comment-autodm.html 自動產生（2026-10-15）。給 AI agent 讀；以網頁版為準。 -->
<!-- 摘要：IG 留言關鍵字自動私訊連結：用 Meta 官方 Instagram API（Private Replies）自建、取代 ManyChat，跑在 Cloudflare Workers 免費額度。按鈕範本把連結按鈕綁進對話框（2026-10 實測）、能不能先檢查追蹤，附給 AI agent 的建置骨架；完整施工圖為免費會員內容。 -->

R-11 · 工具實作 · 實測

# 留言關鍵字自動私訊：用 Meta 官方 API 自建

讀 **2 分鐘**（完整版 8 分鐘）｜最後驗證 **2026.10.15**｜作者自己的 IG 帳號實測｜完整版：**免費會員**

> **你會知道：**我的 IG 貼文底下留言「STB」，對方會自動收到私訊，按一下按鈕就拿到下載連結。這是用 Meta 官方 API 自己蓋的，取代 ManyChat，主機費 0 元。不用交出 IG 密碼、不模擬點擊，但一樣要守平台的發送限制。

## 它在做什麼

**1 留言**留言含關鍵字（STB、ALIGN…）

**2 回兩處**公開回一句＋私訊一顆按鈕（官方 Private Reply）

**3 按鈕**對方按下，代號回到伺服器

**4 發連結**看代號發對應的連結

## 按鈕綁在對話框裡：做到了

以前：快速回覆鈕＋純文字網址

嗨，我是小高 👋 想要 STB 的下載連結嗎？點下面的按鈕，我馬上發給你！

📥 給我連結

按下後按鈕消失

📥 給我連結

來啦！給你 👇

💻 Mac／🪟 Windows 版（免費）：
https://stb-app.github.io/zh-Hant/

📱 iPad 版：
https://apps.apple.com/tw/app/…

現在：按鈕範本（按鈕綁在對話框裡）

嗨，我是小高 👋 想要 STB 的下載連結嗎？📥 給我連結

📥 給我連結

來啦！給你 👇
STB 是廣告前製的腳本 App，免費。Mac／Windows 版iPad 版原始碼

- **官方叫按鈕範本**（Button Template）：一段文字＋最多三顆按鈕，按鈕可以直接開網址。回覆留言的第一則私訊也能帶（2026-10-15 實測）。要放圖、多張卡片左右滑，另有通用範本。
- **「先追蹤才給連結」也做得到**：官方 API 查得到對方有沒有追蹤你（`is_user_follow_business`），條件是對方先按過一次按鈕。我選擇不做：想拿連結的人不用被逼著追蹤。

## 給 AI Agent：建置骨架

把這頁網址丟給你的 agent，說「照這頁幫我蓋 IG 留言關鍵字自動私訊」。純文字版：[ig-comment-autodm.md](https://tools.arminkao.com/research/ig-comment-autodm.md)。

1. 建 Meta App，選「Instagram API with Instagram Login」，權限 `instagram_business_basic`、`instagram_business_manage_comments`、`instagram_business_manage_messages`。
2. 授權碼交換拿 60 天長期權杖，只放伺服器端；每天排程檢查，符合條件（例：上次續期滿 7 天）才用 `ig_refresh_token` 續期。
3. Webhook：驗 `X-Hub-Signature-256` 簽章、重送只處理一次；訂閱 `comments`、`messages`、`messaging_postbacks`。
4. 留言含關鍵字 → 公開回覆＋以 `recipient.comment_id` 發 Private Reply（按鈕範本，postback）→ 收到代號發連結（按鈕範本，web_url）。
5. 放隱私政策網址、App 切「已發佈」；Graph API 版本停用日寫進行事曆。

**完成**：第二個帳號留關鍵字 → 收到按鈕 → 按下拿到連結；無關留言不觸發；簽章錯的假事件被拒。

## 登入看完整版（免費）

為什麼自己蓋與成本對照、安全上怎麼做、踩過的六個雷（權杖過期停兩週、API 版本到期…）、實際數字，以及逐步施工圖、部署設定、12 項驗收表。

讀取中…

資料來源

- 作者自建系統的程式與紀錄（2026.07.19 建置；07.20 陌生帳號實測；10.03 權杖自動續期與告警上線）
- 428 則：7/16–8/24 從 IG 對話紀錄回算（含 ManyChat 時期），2026.08.25 算
- Meta Private Replies 文件、Graph API 版本表、User Profile 文件（2026.10.15 查）；Instagram 訊息範本：Meta 官方 Postman 範例（2026.10.15 查）
- ManyChat Essential／Pro 方案說明（2026.10.15 查）

以上是一個人、自己帳號的實測；Meta 的規則與價格會變，動工前請查當下的官方文件。

[← 回到研究列表](https://tools.arminkao.com/#research)

---
網頁版：https://tools.arminkao.com/research/ig-comment-autodm.html｜小高工具間：https://tools.arminkao.com/｜全站目錄：https://tools.arminkao.com/llms.txt
作者：高偉鳴 Armin Kao｜Instagram：https://www.instagram.com/17187kao/｜作品集：https://arminkao.com/
