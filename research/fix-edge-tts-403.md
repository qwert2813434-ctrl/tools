<!-- 純文字版，由 https://tools.arminkao.com/research/fix-edge-tts-403.html 自動產生（2026-10-12）。給 AI agent 讀；以網頁版為準。 -->
<!-- 摘要：2026-10-12 起微軟舊的 Edge 配音主機開始回 403，用 edge-tts 的工具會突然不出聲。Aloud（讓 Agent 講話）與唸書機怎麼更新，自己蓋的版本貼哪一段（換主機＋429 自動重試）；Edge 配音整條掛掉時的其他台灣腔解法。給人看也給 AI agent 照做。 -->

修正公告 · Aloud／唸書機

# 朗讀突然沒聲音：微軟換了配音主機

發生 **2026.10.12**｜影響 **用 edge-tts 的工具**｜最後驗證 **2026.10.12**

> **一句話：**微軟舊的 Edge 配音主機開始拒絕連線（403），所以 Aloud 和唸書機會突然不唸、不出音檔。程式本身沒壞。換到微軟的新主機就好；新主機偶爾會拒絕一次（429），所以再加上自動重試。自己蓋的版本貼 C 段那一段程式，現成版照 A、B 段更新。

**更新 2026.10.12 晚上：**換到新主機後，偶爾還是會有一句不唸（錯誤 429）。C 段已改成「換主機＋自動重試」；Aloud 現成版的重試還在測。不想折騰、要長期穩定：看最下面「其他解法」第 1 個，微軟官方免費等級。

## 症狀

- Aloud：文字推得進去、畫面也有，就是不唸；或一直停在「合成中」。
- 唸書機：配音或建置跟讀器時中斷，沒有產生音檔。
- 錯誤訊息是 `403, message='Invalid response status'`（網址含 `speech.platform.bing.com`），或只看到 `RuntimeError: Session is closed`。

不是時鐘問題，也不是 edge-tts 版本太舊：7.2.8 是目前最新版，一樣 403。

## 你是哪一種，照哪一段做

### A. 裝了 Aloud 現成版（貼一行指令裝的）

打開「終端機」，貼上當初安裝的同一行指令。會更新到 2.3 版，你的破音字表會保留。更新完重開導讀窗。

2.3 版已換主機，但還沒有自動重試：偶爾某一句不唸時，重推那一句就好。含重試的新版測好後會更新這裡。

```bash
curl -fsSL https://raw.githubusercontent.com/qwert2813434-ctrl/aloud/main/install.sh | bash
```

### B. 用唸書機（從 GitHub 下載的）

repo：[github.com/qwert2813434-ctrl/shuji](https://github.com/qwert2813434-ctrl/shuji)。到唸書機資料夾，拉最新版就好（已換主機，重試還沒加）。已修好的兩個檔是 `跟讀器建置.py` 和 `對照建置.py`。

```bash
git pull
```

沒有用 git、是下載 zip 的：照下面 C 段，在這兩個檔的 `import edge_tts` 後面貼上那一段。

### C. 照 Aloud 規格書自己蓋的，或任何用 edge-tts 的程式

在檔案最上面 `import edge_tts` 的下一行，貼上這一段（不用改套件本體）。第 1 部分換主機，第 2 部分在新主機偶爾拒絕時自動重送。

```python
import asyncio, edge_tts, edge_tts.communicate

# 1. 改走微軟新主機（舊主機 2026-10-12 起開始回 403）
edge_tts.communicate.WSS_URL = ("wss://api.msedgeservices.com/tts/cognitiveservices/websocket/v1"
                                "?Ocp-Apim-Subscription-Key=" + edge_tts.constants.TRUSTED_CLIENT_TOKEN)

# 2. 新主機偶爾回 429／503：第一次失敗後再試最多 3 次（等 1、2、4 秒）；只在還沒收到任何資料時重送，不會重複
if not getattr(edge_tts.Communicate, "_retry_patched", False):
    _edge_stream = edge_tts.Communicate._Communicate__stream

    async def _edge_stream_retry(self):
        for wait in (1, 2, 4, None):
            sent = False
            try:
                async for message in _edge_stream(self):
                    sent = True
                    yield message
                return
            except Exception as error:
                if sent or wait is None or getattr(error, "status", None) not in (429, 503):
                    raise
                self.state["chunk_audio_bytes"] = 0
                await asyncio.sleep(wait)

    edge_tts.Communicate._Communicate__stream = _edge_stream_retry
    edge_tts.Communicate._retry_patched = True
```

這段要放在檔案最上層（不要縮排進函式裡），每個程序跑一次就生效；不小心貼兩次也不會疊加。用 `from edge_tts import Communicate` 的寫法一樣有效。改完要重開伺服器，舊的程序還在跑，就不會用到新程式。

第 2 部分用到 edge-tts 的內部函式，在 7.2.x（目前最新 7.2.8）實測可用。官方新版若拿掉這個內部函式，會在載入時報 AttributeError；若函式還在但行為改了，不一定會報錯，所以升級後要重新驗證。

## 給 AI Agent：照這個步驟修

把這頁網址丟給你的 Claude、Codex 或其他 agent，跟它說「照這頁修」。

1. 先判斷是哪一種安裝（上面 A／B／C），三種的驗證方法不同：**A** 執行那行安裝指令、整個 App 結束再開，從 App 推三到五句文字，句句都有聲音就完成（不用做第 2–5 步）。**B** 在唸書機資料夾 `git pull`，再用它實際配一小段（例如示範書的一章），有產出音檔就完成。**C** 照第 2–6 步做。
2. 在專案裡搜尋 `import edge_tts` 和 `from edge_tts`，列出所有命中的 `.py` 檔（不含 site-packages）。先分出哪些是真正會跑到的程式（伺服器、主程式、建置腳本），測試、範例、備份檔不用改。
3. 每個檔案在最上層 import 區的後面，貼上 C 段整段（不縮排）。已經有 `msedgeservices` 但沒有 `_retry_patched` 的檔案（舊版三行修正），把原本三行換成 C 段整段。兩個都有的跳過。
4. 每個改過的檔跑 `python3 -m py_compile 檔名`，確認沒有語法錯誤。
5. （只適用 C）驗證補丁本身：用同一個 Python 連續合成 10 句中文，10 句都要拿到大於 0 位元組的音檔（只測 1 句，碰不到偶發的 429）。要用 App 實際用的那個 Python（例如虛擬環境裡的），不然測的是別的環境。
   把 C 段存成 `edge_fix.py`，在同一個資料夾跑：
   ```bash
   python3 -c "
   import asyncio, edge_fix, edge_tts
   async def t():
       ok = 0
       for i in range(10):
           n = 0
           async for c in edge_tts.Communicate(f'第 {i} 句測試', 'zh-TW-HsiaoChenNeural').stream():
               if c['type'] == 'audio': n += len(c['data'])
           ok += n > 0
       print('OK', ok, '/ 10')
   asyncio.run(t())"
   ```
6. （只適用 C）重開有在跑的伺服器，從 App 本身推幾句文字，確認真的有聲音。上一步只證明補丁本身能用，這一步才證明 App 有載入它。
7. 不要刪除或降級 edge-tts 套件；不要改 site-packages 裡的檔案。

## 還在觀察：偶爾還是有一句不唸（429）

2026.10.12 晚上在台灣一台 Mac 上實測，新主機偶爾會拒絕一次請求，錯誤訊息是 `429, message='Invalid response status'`。間隔幾秒、一次只送一句也會發生，所以不太像是你送太多：每 3 秒送一句，20 次有 2 次被拒（稍早是 4 次有 1 次）。原因還不確定，可能是微軟對新主機加了限制。（三組數字是不同批測試。）

C 段的自動重試就是針對這個：加上之後連測 20 次、20 次成功；模擬連續被拒 2 次，第 3 次自動成功。

C 段的適用範圍（edge-tts 7.2.8 核對過）：只處理「連線一開始就被拒」的情況，聲音唸到一半斷掉不會重試、會照常報錯；用 `stream()` 與 `save()` 測過。`stream_sync()`／`save_sync()` 在套件本身就有「出錯時呼叫端可能一直等」的問題，C 段沒有修到；自己傳 `connector` 的程式也不在範圍內。升級 edge-tts 後請重新驗證；官方修好後可以拿掉第 2 部分。

這一段還在等更多驗證，結論可能會變。我們用的是「新主機＋舊版通行碼」的組合，微軟自己的 Edge 已經換新版通行碼；哪天舊通行碼被關掉，Edge 配音會整條不能用，那時看下一段。

## 其他解法：Edge 配音整條不能用時

Edge 配音本來就是非官方的免費通道。要長期穩定，或它整條掛掉時，可以換這些（都有台灣腔）。不想折騰的人，直接看第 1 個。

1. 微軟官方 Azure 語音服務（推薦，已實測）
   ：同一個曉臻，聲音完全一樣，走有金鑰的正式服務，不會被當成不明流量擋掉（仍可能遇到額度、限流或服務錯誤）；逐句時間戳也照樣拿得到。免費等級（F0）每月 50 萬字、每分鐘 20 次；這個語音資源只要維持 F0，月額度用完就是被拒絕到下個月，不會轉成付費（帳號裡其他付費資源另計）。
   申請：用個人微軟帳號登入 Azure（要綁卡驗證身分）→ 建立「語音服務」，定價層選 **Free F0**、區域例如 East Asia → 在資源的「金鑰與端點」複製金鑰 1。註冊時若跳「不具免費試用資格」，照提示改開「隨用隨付」帳號，我們這樣開仍可建立 F0（每個帳號每個區域通常只能有一個 F0）。額度與價格以 [官方價格頁](https://azure.microsoft.com/pricing/details/cognitive-services/speech-services/)、[配額頁](https://learn.microsoft.com/azure/ai-services/speech-service/speech-services-quotas-and-limits)為準。
   接法：edge-tts 不用換，把 C 段第 1 部分的網址換成官方網址就好（`eastasia` 換成你的區域，金鑰別寫死在程式裡，放鑰匙圈或環境變數）：
   ```python
   import os, edge_tts, edge_tts.communicate
   edge_tts.communicate.WSS_URL = ("wss://eastasia.tts.speech.microsoft.com/cognitiveservices/websocket/v1"
                                   "?Ocp-Apim-Subscription-Key=" + os.environ["AZURE_SPEECH_KEY"])
   ```
   C 段第 2 部分的重試可以照留。2026.10.12 實測：同一支 edge-tts 7.2.8 連官方端點，中文逐句時間戳正常；金鑰錯會回 401。注意：這樣金鑰會出現在網址裡，錯誤訊息或除錯紀錄可能把整串網址印出來，貼 log、截圖前先遮掉。這是借 edge-tts 的協定連官方服務，不是微軟官方 SDK；要正式產品用，改用 Azure Speech SDK。
2. Mac 內建「美佳」
   ：離線、免費、沒有次數上限，台灣腔但機器感較重。適合當最後一道保底，我們自己的工具已經設成「前面都失敗就改用美佳」。
   ```bash
   say -v Meijia -o out.aiff "要唸的文字"
   ffmpeg -i out.aiff -b:a 64k out.mp3   # 要 mp3 再轉
   ```
3. Mac 的 Siri「聲音 2」（音質比美佳好，要電腦解鎖）
   ：一般程式叫不到 Siri 聲音（
   say
   、AVSpeechSynthesizer 都會被系統換成美佳，WWDC 2020 Session 10022），但蘋果自己的「捷徑」App 叫得到。在捷徑 App 做一個「把輸入的文字做成語音、聲音選聲音 2、輸出音檔」的捷徑，再用命令列呼叫：
   ```bash
   shortcuts run "你的捷徑名稱" -i 文字.txt -o 輸出音檔
   ```
   2026.10.12 實測：電腦解鎖時輸出 48 kHz 的聲音 2（不是美佳）；螢幕鎖著時回「此捷徑需要解鎖你的 Mac」。所以人坐在電腦前用的導讀工具可以用它，人不在電腦前、要遠端推播的（例如推到手機）不行。我們鎖著時沒找到辦法，有成功方法的歡迎回報。
4. **Google Cloud 文字轉語音**：有台灣中文聲音，每月有免費額度，要開 Google Cloud 計費帳號。（未實測。）

iPhone 上也有 Siri 聲音 2（設定 → 輔助使用 → 朗讀內容），一般 App 一樣叫不到，但系統內建的「朗讀螢幕」（兩指從螢幕頂端下滑）可以用它唸任何畫面，適合當手動備案。

試過但不建議：開源中文語音模型（CosyVoice 2、IndexTTS 2）就算用台灣口音的聲音當樣本，出來仍是混雜的怪腔（2026.08 實測）；Gemini TTS 可以下指令講台灣腔，但偶爾會抽到大陸腔、短句會被安全過濾誤擋。

給 agent：要做自動備援，建議順序是「Azure 官方（有金鑰才走）→ Edge（含 C 段重試）→ Mac 的 `say -v Meijia`」，每一層遇到 429／503 先重試再換下一層。兩個實作注意：`WSS_URL` 是整個程序共用的設定，同時有多個合成任務時不要用它切換服務（各服務分開程序跑）；換到下一層時會整段重新合成，存檔請先寫暫存檔、整段成功才取代正式檔。

## 之後

edge-tts 官方已有人送出換主機的修正（GitHub PR #491），還沒合併、沒有發新版。官方出新版後，升級並重新驗證一次；新版已經換主機，就拿掉 C 段第 1 部分；新版自己會處理 429，就拿掉第 2 部分。

Aloud 規格書的「地雷第 10 條」有完整紀錄。

資料來源

- edge-tts GitHub issue #490（2026.10.12 回報 403）、PR #491（改走 api.msedgeservices.com）
- 本機實測：edge-tts 7.2.8，舊主機 403；新主機中文、英文、逐句與逐字時間戳都正常（2026.10.12）
- 新主機 429：每 3 秒送一句連送 20 次，被拒 2 次；加上 C 段重試後 20/20 通過，模擬連續被拒 2 次第 3 次成功（edge-tts 7.2.8，2026.10.12 晚上）
- Siri 聲音不開放給第三方程式：Apple WWDC 2020 Session 10022；本機實測 AVSpeechSynthesizer 與 say 都退回美佳
- Azure 語音免費等級額度與次數上限：Azure 官方價格與配額頁（2026.10 查詢）；實際申請 F0（East Asia）並用 edge-tts 7.2.8 連官方端點合成通過（2026.10.12）
- Siri 聲音 2 經「捷徑」：解鎖時輸出 48 kHz 非美佳音檔；鎖屏 30 秒後執行回「此捷徑需要解鎖你的 Mac」（macOS，2026.10.12）
- Aloud 2.3 打包版、唸書機兩支建置程式，修正後各實際合成一句通過（2026.10.12）

[← 回到小高工具間](https://tools.arminkao.com/)

---
網頁版：https://tools.arminkao.com/research/fix-edge-tts-403.html｜小高工具間：https://tools.arminkao.com/｜全站目錄：https://tools.arminkao.com/llms.txt
作者：高偉鳴 Armin Kao｜Instagram：https://www.instagram.com/17187kao/｜作品集：https://arminkao.com/
