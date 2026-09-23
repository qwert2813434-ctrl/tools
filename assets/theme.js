/* 研究頁共用的日夜主題（與 index.html <head> 內那段同一套邏輯、同一把 key）。在 <head> 同步載入，避免閃白。 */
(function(){
  var MAP = {day:'soft', night:'dusk'};
  var KEY = 'tools.theme';
  function isDay(d){ var h = d.getHours(); return h >= 7 && h < 19; }
  /* 覆寫的有效範圍＝「這一個白天」或「這一個夜晚」，所以要帶日期。
     凌晨算前一天的夜，半夜才不會自己跳回去。 */
  function phaseKey(d){
    var t = new Date(d.getTime());
    if(t.getHours() < 7) t.setDate(t.getDate() - 1);
    return t.toDateString() + (isDay(d) ? '|day' : '|night');
  }
  function auto(d){
    try{ if(matchMedia('(prefers-color-scheme: dark)').matches) return 'night'; }catch(e){}
    return isDay(d) ? 'day' : 'night';
  }
  function override(d){
    try{ var o = JSON.parse(localStorage.getItem(KEY) || 'null');
         return (o && o.k === phaseKey(d)) ? o.v : null; }catch(e){ return null; }
  }
  window.themeNow = function(){ var d = new Date(); return override(d) || auto(d); };
  window.applyTheme = function(v){ document.documentElement.dataset.theme = MAP[v]; };
  window.toggleTheme = function(){
    var d = new Date(), v = themeNow() === 'night' ? 'day' : 'night';
    try{ localStorage.setItem(KEY, JSON.stringify({v:v, k:phaseKey(d)})); }catch(e){}
    applyTheme(v); return v;
  };
  applyTheme(themeNow());
})();
