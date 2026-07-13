#!/bin/bash
# 小高工具間 — 一鍵部署到 GitHub Pages
# 雙擊本檔即可執行。把「上線/」資料夾目前的內容全部推上去。
# 網址：https://qwert2813434-ctrl.github.io/tools/
#
# 認證：用 macOS 鑰匙圈（第一次 push 時 git 會問帳號＋token，輸入一次即記住）

set -e
cd "$(dirname "$0")"
echo "========================================"
echo " 小高工具間 → GitHub Pages 部署"
echo "========================================"

git add -A
if git diff --cached --quiet; then
  echo "沒有變更，不用部署。"
else
  git -c user.email="alignediosapp@gmail.com" -c user.name="qwert2813434-ctrl" \
    commit -m "更新 $(date '+%Y-%m-%d %H:%M')"
fi

echo "→ 推送到 GitHub…"
git push origin main

echo ""
echo "========================================"
echo " ✅ 完成！約 1 分鐘後生效："
echo "    https://qwert2813434-ctrl.github.io/tools/"
echo "========================================"
read -p "按 Enter 關閉…"
