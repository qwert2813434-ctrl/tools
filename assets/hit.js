/* 網站統計：頁面瀏覽＋點擊計數。用法：<script src=".../hit.js" data-site="passer" defer></script>
   不放 cookie。網址加 ?nohit=1 開一次＝這台瀏覽器之後不計（小高自己看站用），?nohit=0 取消 */
(function () {
  var me = document.currentScript, site = me && me.getAttribute("data-site");
  var U = "https://site-hits.qwert2813434.workers.dev/h";
  try {
    var q = new URLSearchParams(location.search).get("nohit");
    if (q === "1") localStorage.setItem("nohit", "1");
    if (q === "0") localStorage.removeItem("nohit");
    if (localStorage.getItem("nohit") === "1") return;
  } catch (_) {}
  if (!site || !navigator.sendBeacon) return;
  function ref() { try { return document.referrer ? "https://" + new URL(document.referrer).hostname : ""; } catch (_) { return ""; } }
  function send(e, t) {
    try {
      navigator.sendBeacon(U, JSON.stringify({ s: site, e: e, p: location.pathname, t: t || "", r: e === "view" ? ref() : "" }));
    } catch (_) {}
  }
  send("view");
  document.addEventListener("click", function (ev) {
    var el = ev.target && ev.target.closest && ev.target.closest("[data-hit],a[href],button");
    if (!el) return;
    var t = el.getAttribute("data-hit");
    if (!t && el.href) {
      var a = new URL(el.href, location.href);
      if (a.protocol === "mailto:" || a.protocol === "tel:") t = a.protocol.slice(0, -1);
      else if (a.host !== location.host) t = "外連 " + a.host + (/github\.com|apps\.apple\.com|youtube\.com|vimeo\.com/.test(a.host) ? a.pathname.slice(0, 50) : "");
      else if (/\.(zip|dmg|exe|pdf)$/i.test(a.pathname)) t = "下載 " + a.pathname;
      else return; // 站內換頁：下一頁會自己記一次瀏覽，不重複算
    }
    if (!t) t = "按鈕 " + (el.getAttribute("aria-label") || el.textContent || "").replace(/\s+/g, " ").trim().slice(0, 40);
    send("click", t);
  }, true);
})();
