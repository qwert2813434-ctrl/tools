/* ── 小高工具間 會員登入 ──
   Google 一鍵登入＋email 登入連結（免密碼）。登入後在 Firestore members/{uid} 留一筆。
   用法：下載鈕加 data-member（沒登入點下去先跳登入框，登入完自動接著下載）；
         區塊加 data-member-box（登入後 .is-member 讓它換成會員內容）；按鈕加 data-member-login 直接開登入框；
         <div data-lesson="課文id"> 登入後從 Firestore lessons/{id} 讀 html 放進來（真鎖：規則要求登入才能讀）。
   頁面要先放 window.MEMBER_CONFIG；樣式在 assets/member.css，這支自己載入。
   注意：這是「軟門」——檔案網址本身還是公開的，付費內容要另外放受保護的空間。
   10/02 小高定：收信要另外勾（預設勾、取消要一眼看得到）；告知補齊個資法 §8；會員自己能取消通知、刪除資料。 */
import { initializeApp } from 'https://www.gstatic.com/firebasejs/10.12.2/firebase-app.js';
import {
  getAuth, onAuthStateChanged, signInWithPopup, GoogleAuthProvider, signOut, deleteUser,
  sendSignInLinkToEmail, isSignInWithEmailLink, signInWithEmailLink
} from 'https://www.gstatic.com/firebasejs/10.12.2/firebase-auth.js';
import {
  getFirestore, doc, getDoc, setDoc, updateDoc, deleteDoc, serverTimestamp
} from 'https://www.gstatic.com/firebasejs/10.12.2/firebase-firestore.js';

const css = document.createElement('link');
css.rel = 'stylesheet'; css.href = new URL('assets/member.css', import.meta.url).href;
document.head.appendChild(css);

const CONFIG = window.MEMBER_CONFIG;          /* index.html 裡填 Firebase 網頁設定 */
const NOTICE = '2026-10-15b';                   /* 告知文字版本；文字改了就換日期 */
const MAIL_KEY = 'tools.member.mail';
const SUB_KEY = 'tools.member.notify';         /* email 連結登入時，先記住三個勾選框的狀態（JSON） */
/* 三種通知（10/15 小高定）：異動預設勾、教學與最新消息預設不勾 */
const KINDS = [
  ['changes', '異動通知', '你用的工具或課程有更新、修正、下架時通知你', true],
  ['lessons', '教學通知', '新的教學、課程上架時通知你', false],
  ['news',    '所有最新消息', '新工具、新研究和其他消息', false],
];
const NONE = { changes: false, lessons: false, news: false };
const anyOn = (n) => Object.values(n).some(Boolean);

const app  = initializeApp(CONFIG);
const auth = getAuth(app);
const db   = getFirestore(app);
auth.languageCode = 'zh-TW';

let user = null;
let pending = null;                            /* 登入前點的那顆下載鈕 */
let wantSub = { ...NONE };                      /* 只有這頁真的按登入（或從 email 連結回來）才取勾選框；背景恢復登入一律不訂閱 */

const store = {
  get(k){ try { return localStorage.getItem(k); } catch (e) { return null; } },
  set(k, v){ try { localStorage.setItem(k, v); } catch (e) {} },
  del(k){ try { localStorage.removeItem(k); } catch (e) {} }
};

/* ── 登入框 ── */
const dlg = document.createElement('dialog');
dlg.className = 'mdlg';
dlg.innerHTML = `
  <form method="dialog" class="mclose"><button aria-label="關閉">×</button></form>
  <div class="eyebrow">免費會員</div>
  <h2>登入就能看完整版</h2>
  <p class="mlead">不用付錢，留一個 email 就好。</p>
  <button class="btn mgoogle" type="button">用 Google 登入</button>
  <div class="mor">或用 email 收登入連結</div>
  <form class="mmail">
    <input type="email" required placeholder="you@example.com" autocomplete="email" aria-label="email">
    <button class="btn quiet" type="submit">寄連結</button>
  </form>
  <div class="mchecks">${KINDS.map(([k, t, d, on]) => `<label class="mcheck"><input type="checkbox" data-k="${k}"${on ? ' checked' : ''}> <span><b>${t}</b>　${d}</span></label>`).join('')}
  <p class="mhint">第一次加入時適用；之後在右上角「會員」隨時改。</p></div>
  <p class="mmsg" aria-live="polite"></p>
  <div class="mnote"><details><summary>個人資料怎麼用</summary><ul>
    <li>誰收集：小高工具間（高偉鳴）。聯絡：Instagram @17187kao 私訊。</li>
    <li>收集什麼：email、Google 帳號顯示名稱、登入方式、第一次加入與最近登入的時間、從哪一頁加入、你選了哪幾種通知。</li>
    <li>做什麼用：開放會員內容（完整施工圖、課程）；只寄你勾選的那幾種通知。不登入也能看公開內容；取消通知不影響會員閱讀。</li>
    <li>存在哪：Google Firebase 受託保管——名單在台灣機房（Firestore），登入帳號由 Firebase Authentication 保管、可能存放在美國等地。只有小高能讀名單，不出售、不提供給其他人。</li>
    <li>存多久：到你刪除為止。</li>
    <li>你的權利：登入後點右上角「會員」可以查看、改通知、刪除全部資料；要更正或有其他要求，用上面的聯絡方式找我。不提供 email 就無法登入，但公開內容照樣能看。</li>
  </ul></details></div>`;
document.body.appendChild(dlg);
const msg = dlg.querySelector('.mmsg');
const picked = (root) => Object.fromEntries([...root.querySelectorAll('[data-k]')].map(i => [i.dataset.k, i.checked]));

function open(){ msg.textContent = ''; dlg.showModal(); }

dlg.querySelector('.mgoogle').addEventListener('click', async () => {
  wantSub = picked(dlg);
  try { await signInWithPopup(auth, new GoogleAuthProvider()); }
  catch (e) { if (e.code !== 'auth/popup-closed-by-user') msg.textContent = '登入沒成功，再試一次（' + e.code + '）'; }
});

dlg.querySelector('.mmail').addEventListener('submit', async (ev) => {
  ev.preventDefault();
  const mail = ev.target.querySelector('input').value.trim();
  try {
    const url = new URL(location.href);
    if (pending) url.searchParams.set('dl', pending.getAttribute('href'));
    await sendSignInLinkToEmail(auth, mail, { url: url.href, handleCodeInApp: true });
    store.set(MAIL_KEY, mail);
    store.set(SUB_KEY, JSON.stringify(picked(dlg)));
    msg.textContent = '已寄出，去信箱點連結就登入了（沒看到記得翻垃圾信）。';
  } catch (e) { msg.textContent = '寄送失敗（' + e.code + '）'; }
});

/* ── 從信裡的連結回來：完成登入，順手接續下載 ── */
if (isSignInWithEmailLink(auth, location.href)) {
  let mail = store.get(MAIL_KEY);
  if (!mail) mail = prompt('請再輸入一次你的 email 以完成登入');
  try { wantSub = { ...NONE, ...JSON.parse(store.get(SUB_KEY) || '{}') }; } catch (e) { wantSub = { ...NONE }; }   /* 換裝置開信＝沒有勾選紀錄，全部不收（10/15 GPT 審） */
  if (mail) {
    signInWithEmailLink(auth, mail, location.href).then(() => {
      store.del(MAIL_KEY); store.del(SUB_KEY);
      const raw = new URL(location.href).searchParams.get('dl');
      history.replaceState(null, '', location.pathname);
      /* 只接續本站的相對路徑下載，別人塞的外部網址不跟 */
      if (raw && /^[\w一-鿿.\-]+$/.test(raw)) download(raw);
    }).catch(e => alert('登入連結失效或已用過（' + e.code + '），請重新寄一次。'));
  }
}

/* ── 會員名單：第一次登入建檔，之後只更新最後登入 ── */
async function record(u){
  const ref = doc(db, 'members', u.uid);
  const snap = await getDoc(ref);
  const base = {
    email: u.email || '',
    name: u.displayName || '',
    provider: (u.providerData[0] || {}).providerId || 'emailLink',
    lastLogin: serverTimestamp()
  };
  if (!snap.exists()) {
    await setDoc(ref, { ...base, createdAt: serverTimestamp(), notice: NOTICE, notify: wantSub, subscribed: anyOn(wantSub),
                        from: pending ? pending.getAttribute('href') : location.pathname });
    return wantSub;
  }
  await setDoc(ref, base, { merge: true });
  const d = snap.data();
  return d.notify || (d.subscribed ? { changes: true, lessons: true, news: true } : { ...NONE });   /* 舊格式只有 subscribed */
}

function download(href){
  const a = document.createElement('a');
  a.href = href; a.setAttribute('download', '');
  document.body.appendChild(a); a.click(); a.remove();
}

/* ── 會員面板：看自己的資料、取消／恢復通知、刪除、登出 ── */
const me = document.createElement('dialog');
me.className = 'mdlg mme';
me.innerHTML = `
  <form method="dialog" class="mclose"><button aria-label="關閉">×</button></form>
  <div class="eyebrow">會員</div>
  <h2>你的資料</h2>
  <p class="mwho"></p>
  <div class="mrow">
    <div class="mchecks mnotify">${KINDS.map(([k, t, d]) => `<label class="mcheck"><input type="checkbox" data-k="${k}"> <span><b>${t}</b>　${d}</span></label>`).join('')}</div>
    <button class="btn quiet mout" type="button">登出</button>
    <button class="btn quiet danger mdel" type="button">刪除我的全部資料</button>
  </div>
  <p class="mmsg" aria-live="polite"></p>`;
document.body.appendChild(me);
const meMsg = me.querySelector('.mmsg');
let subscribed = { ...NONE };
function paintMe(){
  me.querySelector('.mwho').textContent = (user && user.email || '') + (anyOn(subscribed) ? '' : '　·　目前不收任何通知');
  me.querySelectorAll('.mnotify [data-k]').forEach(i => { i.checked = !!subscribed[i.dataset.k]; });
}
me.querySelectorAll('.mnotify [data-k]').forEach(i => i.addEventListener('change', async () => {
  const next = picked(me.querySelector('.mnotify'));
  try {
    await updateDoc(doc(db, 'members', user.uid), { notify: next, subscribed: anyOn(next) });
    subscribed = next; paintMe();
    meMsg.textContent = '已存好。';
  } catch (e) { i.checked = !i.checked; meMsg.textContent = '沒改成功，再試一次（' + (e.code || e.message) + '）'; }
}));
me.querySelector('.mout').addEventListener('click', async () => { await signOut(auth); me.close(); });
let delArmed = false;
me.querySelector('.mdel').addEventListener('click', async (ev) => {
  if (!delArmed) { delArmed = true; ev.target.textContent = '確定刪除？再按一次'; return; }
  try {
    await deleteDoc(doc(db, 'members', user.uid));
    try { await deleteUser(user); }
    catch (e) {                                  /* 登入太久要重登才能刪帳號：名單已刪，帳號還在，先登出免得下次自動重建名單 */
      await signOut(auth);
      meMsg.textContent = '名單資料已刪除，也已幫你登出；登入帳號本身要重新登入後，再按一次刪除才會刪掉。';
      delArmed = false; ev.target.textContent = '刪除我的全部資料';
      return;
    }
    me.close();
    alert('已刪除你的全部會員資料（名單與登入帳號）。');
  } catch (e) { meMsg.textContent = '刪除失敗（' + (e.code || e.message) + '）'; }
});

/* ── 頂列的登入鈕 ── */
const pill = document.createElement('button');
pill.className = 'mpill';
document.querySelector('.topbar .orb').before(pill);
pill.addEventListener('click', () => {
  if (!user) { pending = null; open(); return; }
  delArmed = false; me.querySelector('.mdel').textContent = '刪除我的全部資料';
  meMsg.textContent = ''; paintMe(); me.showModal();
});

onAuthStateChanged(auth, async (u) => {
  user = u;
  document.documentElement.classList.toggle('is-member', !!u);
  pill.textContent = u ? '會員 · ' + (u.email || '').split('@')[0] : '登入';
  if (!u) { clearLessons(); return; }
  loadLessons();
  try { subscribed = await record(u); } catch (e) { console.warn('會員紀錄寫入失敗', e); }
  if (dlg.open) dlg.close();
  if (pending) { const p = pending; pending = null; p.click(); }   /* 已登入，這次點擊會直接放行，保留原本的 download 檔名 */
});

/* ── 會員限定的下載鈕、區塊裡的登入鈕、複製鈕 ── */
document.querySelectorAll('[data-member]').forEach(a => {
  a.addEventListener('click', ev => {
    if (user) return;
    ev.preventDefault();
    pending = a;
    open();
  });
});
document.querySelectorAll('[data-member-login]').forEach(b => b.addEventListener('click', () => { pending = null; open(); }));
document.querySelectorAll('[data-member-box] [data-copy]').forEach(b => b.addEventListener('click', async () => {
  const code = b.parentElement.querySelector('code').textContent;
  try { await navigator.clipboard.writeText(code); b.textContent = '已複製'; }
  catch (e) { getSelection().selectAllChildren(b.parentElement.querySelector('code')); b.textContent = '已選取，按 ⌘C'; }
  setTimeout(() => { b.textContent = '複製'; }, 1800);
}));

/* ── 會員課文：登入後讀 lessons/{id}.html 放進 [data-lesson]（內容是小高自己寫的，上傳腳本 _AI/會員系統/上傳課文.py） ── */
function clearLessons(){
  document.querySelectorAll('[data-lesson]').forEach(box => { box.textContent = '讀取中…'; delete box.dataset.loaded; });
}
async function loadLessons(){
  const uid = user && user.uid;
  for (const box of document.querySelectorAll('[data-lesson]')) {
    if (box.dataset.loaded) continue;
    try {
      const snap = await getDoc(doc(db, 'lessons', box.dataset.lesson));
      if (!user || user.uid !== uid) return;     /* 讀完時已經登出或換人，不放 */
      if (snap.exists()) { box.innerHTML = snap.data().html; box.dataset.loaded = '1'; }
      else box.textContent = '這份內容還沒上架。';
    } catch (e) { box.textContent = '讀取失敗，重新整理再試一次（' + (e.code || e.message) + '）'; }
  }
}
