# 小高工具間 TOOL.AI — 網站原始碼

台灣廣告導演高偉鳴（Armin Kao）自用的免費工具與實測研究網站，部署在 GitHub Pages：<https://tools.arminkao.com/>

> 給 AI agent：要讀內容不要讀這個 repo，先讀 [llms.txt](llms.txt)（全站目錄，線上：https://tools.arminkao.com/llms.txt）。每篇研究都有同名 `.md` 純文字版；有「給 AI Agent」段落的頁面照那段做。

## 結構

| 路徑 | 是什麼 |
|---|---|
| `index.html` | 首頁：研究卡、工具卡、更新紀錄 |
| `research/*.html` | 研究頁（實測紀錄，每篇標最後驗證日） |
| `research/*.md` | 研究頁的純文字版（由 HTML 自動產生，轉換程式在作者的維護工作區、不在本 repo；不要手改） |
| `llms.txt` | 給 AI agent 的全站目錄 |
| `*.html`（根層） | 免安裝網頁工具：濾鏡工坊、幾何 icon 工坊、隱形 QR、串珠門簾、Credits 規格 |
| `aligned-templates/` | ALIGNED 排版範本（可下載專案檔） |
| `aligncam/`、`rheo-help/` | App 的隱私權與說明頁 |
| `aligned-latest.json`、`stb-latest.json` | App 內「有新版」提示讀的版本資訊 |
| `*.zip` | 可下載的工具（AE 工具包、參考片下載工具） |

## 相關 repo

- 開源規格書（給 AI 照著蓋）：[aloud](https://github.com/qwert2813434-ctrl/aloud)、[whisperbar](https://github.com/qwert2813434-ctrl/whisperbar)、[collection-wall](https://github.com/qwert2813434-ctrl/collection-wall)
- 開源工具與 App：[shuji 唸書機](https://github.com/qwert2813434-ctrl/shuji)、[ALIGNED](https://github.com/qwert2813434-ctrl/ALIGNED)、[STB](https://github.com/qwert2813434-ctrl/STB)、[RHEO](https://github.com/qwert2813434-ctrl/RHEO)
