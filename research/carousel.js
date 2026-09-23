/* IG 輪播：scroll-snap 左右滑＋箭頭＋頁碼。媒體在正式網址時直接向 github.io 取，不經 Netlify 代理（省流量額度）。 */
(function(){
  var GH = 'https://qwert2813434-ctrl.github.io/tools/research/';
  var remote = location.hostname === 'tools.arminkao.com';
  document.querySelectorAll('.cara').forEach(function(c){
    var track = c.querySelector('.track'), slides = [].slice.call(track.children);
    if (remote) c.querySelectorAll('[src],[poster]').forEach(function(el){
      ['src','poster'].forEach(function(a){ var v = el.getAttribute(a); if (v && v.indexOf('media/') === 0) el.setAttribute(a, GH + v); });
    });
    var count = c.querySelector('.count'), dots = c.querySelector('.dots'), prev = c.querySelector('.prev'), next = c.querySelector('.next');
    dots.innerHTML = slides.map(function(){ return '<i></i>'; }).join('');
    function idx(){ return Math.round(track.scrollLeft / track.clientWidth); }
    function sync(){
      var i = idx();
      count.textContent = (i + 1) + ' / ' + slides.length;
      [].forEach.call(dots.children, function(d, k){ d.classList.toggle('on', k === i); });
      prev.disabled = i === 0; next.disabled = i === slides.length - 1;
      slides.forEach(function(s, k){ var v = s.querySelector('video'); if (!v) return; if (k === i) { var p = v.play(); if (p && p.catch) p.catch(function(){}); } else v.pause(); });
    }
    function go(d){ track.scrollTo({ left: (idx() + d) * track.clientWidth, behavior: 'smooth' }); }
    prev.onclick = function(){ go(-1); }; next.onclick = function(){ go(1); };
    var t; track.addEventListener('scroll', function(){ clearTimeout(t); t = setTimeout(sync, 60); });
    c.tabIndex = 0; c.addEventListener('keydown', function(e){ if (e.key === 'ArrowLeft') go(-1); if (e.key === 'ArrowRight') go(1); });
    sync();
  });
})();

/* 提示詞複製鈕 */
document.querySelectorAll('.prompt .copy').forEach(function(b){
  b.addEventListener('click', function(){
    var t = b.closest('.prompt').querySelector('pre').innerText;
    var ok = function(){ b.textContent = '已複製'; b.classList.add('done'); setTimeout(function(){ b.textContent = '複製'; b.classList.remove('done'); }, 1600); };
    if (navigator.clipboard) navigator.clipboard.writeText(t).then(ok, function(){ fallback(); }); else fallback();
    function fallback(){ var a = document.createElement('textarea'); a.value = t; document.body.appendChild(a); a.select(); try { document.execCommand('copy'); ok(); } catch(e){} a.remove(); }
  });
});
