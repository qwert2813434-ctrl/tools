/* ── 小高工具間 登入框的玻璃水（2026-10-17 示範，研究正本在 01 - 研究/水波研究）──
   登入框後面墊一層玻璃：看得到後面網頁的模糊快照，框一動（彈出、輸錯搖頭）裡面的水就晃。
   字、輸入框、按鈕都是原本的網頁元素，水只畫在它們後面，字不扭（10/17 小高定）。
   不支援 WebGL2／設了「減少動態」／任何一步失敗 → 什麼都不做，登入框維持原樣。
   10/18 加：玻璃換成冰塊（研究頁 16 號：反光尖折痕＋小碎片長在龜裂口），滑鼠／手指在框上快速劃過＝手電筒＋撥水（光長在被撥起的浪頭上，很快熄）。
   用法：member.js 在建好 dlg 之後 import('./member-water.js').then(m => m.attach(dlg)).catch(() => {}); */

const P = {               /* 10/17 定版（視窗水波）；甩動力道用登入框示範的 .6 */
  slosh: .6, keep: .31, speed: .95, margin: .5, corner: .6, bowl: .7, rough: .35,
  warp: 1, lens: 1.45, chroma: 2, shine: 1.75, tint: .5, bounce: .45,
  ice: 1, torch: 1, trail: 0, stir: 2,   /* 10/18 冰塊＋手電筒（小高在手電筒冰水頁調的）；霧度 .62→.5 冰才透得出來 */
  backBlur: 6, glassBlur: 9,    /* 跟 member.css 的 ::backdrop 一樣糊 6px，再加玻璃本身 9px */
};
const CELL = 4, G = 1, DEPTH = .1;

const BIL = `vec4 bil(sampler2D t,vec2 uv){vec2 sz=vec2(textureSize(t,0));vec2 p=uv*sz-.5,f=fract(p);ivec2 i=ivec2(floor(p)),m=ivec2(sz)-1;
 return mix(mix(texelFetch(t,clamp(i,ivec2(0),m),0),texelFetch(t,clamp(i+ivec2(1,0),ivec2(0),m),0),f.x),
            mix(texelFetch(t,clamp(i+ivec2(0,1),ivec2(0),m),0),texelFetch(t,clamp(i+ivec2(1,1),ivec2(0),m),0),f.x),f.y);}`;
const SD = `float sdBox(vec2 p,vec2 b,float r){vec2 d=abs(p)-b+r;return min(max(d.x,d.y),0.)+length(max(d,0.))-r;}`;
const BASIN = `${SD}${BIL}
uniform float uH0,uCorner,uBowl,uRough;
float hash(vec2 p){p=fract(p*vec2(123.34,456.21));p+=dot(p,p+45.32);return fract(p.x*p.y);}
float vnoise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);
 return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
float basinSD(vec2 c){vec2 hb=uSimRes*.5;return sdBox(c-hb,hb-.5,uCorner*min(hb.x,hb.y));}
float depth(vec2 c){float d=-basinSD(c);if(d<=0.)return 0.;
 vec2 q=(c-uSimRes*.5)/(uSimRes*.5);float r=pow(pow(abs(q.x),4.)+pow(abs(q.y),4.),.25);   // 圓滑的碗：用超橢圓距離，盆底沒有折角（距牆距離會在中線、對角線折出稜，晃水時浮出一條線）
 float bowl=mix(1.,.25+.75*(1.-smoothstep(.3,1.,r)),uBowl);
 float n=vnoise(c*.045+3.1)*.65+vnoise(c*.11+7.7)*.35;
 return uH0*bowl*(1.+(n-.5)*1.6*uRough);}`;
/* 淺水方程：r＝水面高低，gb＝流速。唯一的外力＝登入框的加速度（反向慣性力） */
const SIM_VEL = `#version 300 es
precision highp float;uniform sampler2D uState;uniform vec2 uSimRes,uAcc,uM0,uM1,uMv;uniform float uG,uDamp,uVisc,uStir,uGlowIn,uGlowKeep;out vec4 o;
${BASIN}
void main(){vec2 c=gl_FragCoord.xy,e=1./uSimRes,uv=c*e;
 vec2 sg=uM1-uM0;float st=clamp(dot(c-uM0,sg)/max(dot(sg,sg),1e-4),0.,1.);float dm=length(c-uM0-sg*st);   /* 這一步滑鼠劃過的線段 */
 float wS=exp(-dm*dm/64.),wG=exp(-dm*dm/20.);
 float gl0=bil(uState,(c-bil(uState,uv).gb)*e).a*uGlowKeep+uGlowIn*wG;             /* 光場：跟著水流走、很快熄 */
 if(depth(c)<=0.){o=vec4(bil(uState,uv).r,0.,0.,min(gl0,3.));return;}
 vec4 s=bil(uState,uv);
 vec2 u=bil(uState,(c-s.gb)*e).gb;
 vec4 L=bil(uState,uv-vec2(e.x,0.)),R=bil(uState,uv+vec2(e.x,0.)),D=bil(uState,uv-vec2(0.,e.y)),U=bil(uState,uv+vec2(0.,e.y));
 float hL=depth(c-vec2(1,0))>0.?L.r:s.r,hR=depth(c+vec2(1,0))>0.?R.r:s.r,hD=depth(c-vec2(0,1))>0.?D.r:s.r,hU=depth(c+vec2(0,1))>0.?U.r:s.r;
 u+=uVisc*((L.gb+R.gb+D.gb+U.gb)*.25-s.gb);
 u+=-uG*vec2(hR-hL,hU-hD)*.5+uAcc;
 vec2 tg=uMv*.45*uStir;float tl=length(tg);if(tl>.7)tg*=.7/tl;
 u=mix(u,tg,wS*.1*step(.001,uStir));                                          /* 撥水：流速往滑鼠方向帶 */
 u*=uDamp;
 float ul=length(u);if(ul>.85)u*=.85/ul;                                      /* 一步不超過 0.85 格，狂撥也不會爆（研究頁 10/18 實測） */
 float sd=basinSD(c);
 if(sd>-1.5){vec2 n=normalize(vec2(basinSD(c+vec2(1,0))-basinSD(c-vec2(1,0)),basinSD(c+vec2(0,1))-basinSD(c-vec2(0,1)))+1e-6);
  u-=max(dot(u,n),0.)*n;}
 o=vec4(s.r,u,min(gl0,3.));}`;
const SIM_H = `#version 300 es
precision highp float;uniform sampler2D uState;uniform vec2 uSimRes;uniform float uVisc;out vec4 o;
${BASIN}
void main(){vec2 c=gl_FragCoord.xy,e=1./uSimRes,uv=c*e;
 vec4 s=bil(uState,uv);
 vec4 L=bil(uState,uv-vec2(e.x,0.)),R=bil(uState,uv+vec2(e.x,0.)),D=bil(uState,uv-vec2(0.,e.y)),U=bil(uState,uv+vec2(0.,e.y));
 float dC=depth(c),dL=depth(c-vec2(1,0)),dR=depth(c+vec2(1,0)),dD=depth(c-vec2(0,1)),dU=depth(c+vec2(0,1));
 if(dC<=0.){float sum=0.,w=0.;if(dL>0.){sum+=L.r;w++;}if(dR>0.){sum+=R.r;w++;}if(dD>0.){sum+=D.r;w++;}if(dU>0.){sum+=U.r;w++;}
  o=vec4(w>0.?sum/w:s.r*.98,0.,0.,s.a);return;}
 float fL=dL>0.?(dL+L.r)*L.g:0.,fR=dR>0.?(dR+R.r)*R.g:0.,fD=dD>0.?(dD+D.r)*D.b:0.,fU=dU>0.?(dU+U.r)*U.b:0.;
 float div=(fR-fL+fU-fD)*.5;
 float hL=dL>0.?L.r:s.r,hR=dR>0.?R.r:s.r,hD=dD>0.?D.r:s.r,hU=dU>0.?U.r:s.r;
 float h=s.r-div+uVisc*((hL+hR+hD+hU)*.25-s.r);
 o=vec4(clamp(h,-.8*dC,1.5*dC),s.gb,s.a);}`;
/* 合成：畫布只蓋登入框那一塊；取樣後面網頁的快照（座標換成整個視窗的） */
const COMP = `#version 300 es
precision highp float;
uniform sampler2D uSnap,uSharp,uSim;
uniform vec2 uView,uSimRes;uniform vec4 uWin;uniform vec3 uCard;
uniform float uRadius,uWarp,uLens,uChroma,uShine,uDpr,uCorner,uMargin,uTint,uIce;uniform vec3 uTorch;
out vec4 o;
${SD}${BIL}
vec3 snap(vec2 p){vec2 r=9.*uDpr/uView;vec2 u=clamp(p/uView,0.,1.);   /* 五點取樣，把縮小格的方塊感抹掉 */
 return (texture(uSnap,u).rgb*2.+texture(uSnap,u+vec2(r.x,r.y)).rgb+texture(uSnap,u+vec2(-r.x,r.y)).rgb+texture(uSnap,u+vec2(r.x,-r.y)).rgb+texture(uSnap,u-r).rgb)/6.;}
float hash(vec2 p){p=fract(p*vec2(123.34,456.21));p+=dot(p,p+45.32);return fract(p.x*p.y);}
float vn(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);
 return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
float fbm(vec2 p){float v=0.,a=.5;for(int i=0;i<5;i++){v+=a*vn(p);p=p*2.03+vec2(1.7,9.2);a*=.5;}return v;}
vec2 fbmGrad(vec2 p){float e=.03;return vec2(fbm(p+vec2(e,0))-fbm(p-vec2(e,0)),fbm(p+vec2(0,e))-fbm(p-vec2(0,e)))/(2.*e);}
float ridge(vec2 p){float v=0.,a=.5;for(int i=0;i<5;i++){v+=a*(1.-abs(vn(p)*2.-1.));p=p*2.03+vec2(1.7,9.2);a*=.5;}return v;}
vec2 ridGrad(vec2 p){float e=.015;return vec2(ridge(p+vec2(e,0))-ridge(p-vec2(e,0)),ridge(p+vec2(0,e))-ridge(p-vec2(0,e)))/(2.*e);}
void main(){
 vec2 lp=vec2(gl_FragCoord.x,uWin.w-gl_FragCoord.y);          /* 畫布內、左上原點 */
 vec2 hb=uWin.zw*.5;float sd=sdBox(lp-hb,hb,uRadius);
 vec2 suv=(lp+uMargin)/(uWin.zw+2.*uMargin),e=1./uSimRes;
 vec2 g=vec2(bil(uSim,suv+vec2(e.x,0)).r-bil(uSim,suv-vec2(e.x,0)).r,
             bil(uSim,suv+vec2(0,e.y)).r-bil(uSim,suv-vec2(0,e.y)).r);
 {vec2 cp=suv*uSimRes,hc=uSimRes*.5;g*=smoothstep(0.,5.,-sdBox(cp-hc,hc-.5,uCorner*min(hc.x,hc.y)));}
 vec2 off=-g*uWarp*1800.*uDpr;
 float hl=dot(g,normalize(vec2(-1,-1.3)))*60.*uShine;
 float dep=-sd,band=30.*uDpr*max(uLens,.001),t=clamp(dep/band,0.,1.);
 float bend=(1.-sqrt(1.-(1.-t)*(1.-t)))*step(.001,uLens);
 vec2 n2=vec2(0);if(bend>0.){vec2 gv=vec2(sdBox(lp+vec2(1,0)-hb,hb,uRadius)-sd,sdBox(lp+vec2(0,1)-hb,hb,uRadius)-sd);float gl=length(gv);if(gl>1e-4)n2=gv/gl;}   // 只在邊緣帶算方向；中線、對角線上方向會翻轉，舊寫法在那裡算出無效值、畫出一條細線
 vec2 lensOff=-n2*bend*band*.9,dir=off+lensOff;
 vec2 ch=(length(dir)>1e-4?dir/length(dir):vec2(0))*min(length(dir),40.*uDpr)*.18*uChroma;
 /* 冰塊：紋理、碎片釘在框上，跟著水折彎 */
 vec2 ip=lp/uDpr+off/uDpr*.35;float k=uIce,k1=min(k,1.);
 vec2 nX=fbmGrad(ip*.012)*.10*k1;
 float cl=smoothstep(.45,.75,fbm(ip*.008+3.));
 float m=min(smoothstep(.56,.74,ridge(ip*.010))+.45*smoothstep(.62,.8,fbm(ip*.02+9.)),1.)*step(.001,k);   /* 碎片長在反光折痕（龜裂口） */
 float fq=fbm(ip*vec2(.028,.075)+vec2(4.,1.))+(vn(ip*vec2(.5,1.2))-.5)*.08;fq=clamp((fq-.5)*2.6+.5,0.,1.);
 float lq=fq*6.,lv=floor(lq)/6.,fr=fract(lq),edge=1.-smoothstep(0.,.06,min(fr,1.-fr));
 vec2 shd=(vec2((lv-.5)*70.,(lv-.5)*7.)+vec2((hash(vec2(lv,3.))-.5)*30.,0.))*uDpr*m*k1;
 vec2 q=uWin.xy+lp+off+lensOff-nX*46.*uDpr*1.6+shd;
 vec3 c=vec3(snap(q-ch).r,snap(q).g,snap(q+ch).b);
 vec2 qs=clamp(q/uView,0.,1.);
 c=mix(c,texture(uSharp,qs).rgb,.55*m*k1);                     /* 碎片處清楚一點，後面的字被錯開才看得出來 */
 c=mix(c,vec3(1),cl*.18*k1);
 c=mix(c,uCard,uTint);
 vec2 nS=ridGrad(ip*.010)*.09*k;
 vec3 N=normalize(vec3(-(nX+nS+g*12.*uShine),1.)),H=normalize(normalize(vec3(-.55,-.7,.8))+vec3(0,0,1));
 float spec=pow(max(dot(N,H),0.),260.)*1.6*k;
 c+=spec*.55;
 /* 手電筒：快速劃過才亮；光長在被撥起的浪頭上（水面越陡越亮，中心白外緣藍） */
 vec2 tv=uTorch.xy-lp;float att=uTorch.z*exp(-dot(tv,tv)/pow(230.*uDpr,2.));
 float glow=bil(uSim,suv).a;
 vec3 Ht=normalize(normalize(vec3(tv/(260.*uDpr),.45))+vec3(0,0,1));
 float specT=pow(max(dot(N,Ht),0.),110.)*2.2*k*(att+glow*.35);
 c+=vec3(.82,.93,1.)*min(specT,1.)*.3;
 float lit=min(att+glow,1.4)*smoothstep(.15,1.2,length(g)*uDpr*900.);
 float hot=lit*(.6+.8*m+.6*edge*m);
 c+=mix(vec3(.25,.55,1.),vec3(1.),smoothstep(.5,1.5,hot))*hot*.5;
 c+=edge*m*(.15+.9*step(.82,vn(ip*vec2(.9,2.2))))*(.12+spec*1.2+max(hl,0.)*.5)*k1;   /* 碎片斷口閃點 */
 c+=min(max(hl,0.),1.)*.45-min(max(-hl,0.),1.)*.16;
 c+=bend*.05;
 c+=(1.-smoothstep(0.,1.6*uDpr,dep))*(.22+.3*clamp(1.-lp.y/uWin.w*2.,0.,1.));
 o=vec4(c,1.)*(1.-smoothstep(-.75,.75,sd));                          /* 圓角外透明（premultiplied） */
}`;

let h2cLoading = null;
function loadH2C() {
  if (window.html2canvas) return Promise.resolve(window.html2canvas);
  return h2cLoading ||= new Promise((ok, bad) => {
    const s = document.createElement('script');
    s.src = new URL('assets/vendor/html2canvas.min.js', import.meta.url).href;   /* 自己站上的固定版本 1.4.1，不從外部載 */
    s.onload = () => ok(window.html2canvas); s.onerror = bad;
    document.head.appendChild(s);
  });
}

export function attach(dlg) {
  const rm = matchMedia('(prefers-reduced-motion: reduce)');
  if (rm.matches) return;
  const cv = document.createElement('canvas');
  const gl = cv.getContext('webgl2', { premultipliedAlpha: true, alpha: true, antialias: false });
  if (!gl || !gl.getExtension('EXT_color_buffer_float')) return;

  const style = document.createElement('style');
  style.textContent = `.mdlg.mwater{background:transparent}
.mdlg>canvas.mwater-cv{position:absolute;inset:0;width:100%;height:100%;z-index:-1;pointer-events:none;border-radius:inherit;opacity:0;transition:opacity .25s}
.mdlg.mwater>canvas.mwater-cv{opacity:1}`;
  document.head.appendChild(style);
  cv.className = 'mwater-cv'; cv.setAttribute('aria-hidden', 'true');
  dlg.prepend(cv);
  dlg.dataset.water = 'gl';

  /* ── GL 小工具 ── */
  const VERT = `#version 300 es
in vec2 a;void main(){gl_Position=vec4(a,0,1);}`;
  const compile = (type, src) => { const s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s);
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s)); return s; };
  const program = fs => { const p = gl.createProgram(); gl.attachShader(p, compile(gl.VERTEX_SHADER, VERT)); gl.attachShader(p, compile(gl.FRAGMENT_SHADER, fs));
    gl.bindAttribLocation(p, 0, 'a'); gl.linkProgram(p); if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(p));
    p.u = {}; const n = gl.getProgramParameter(p, gl.ACTIVE_UNIFORMS);
    for (let i = 0; i < n; i++) { const nm = gl.getActiveUniform(p, i).name; p.u[nm] = gl.getUniformLocation(p, nm); } return p; };
  const buf = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, buf); gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
  gl.enableVertexAttribArray(0); gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
  let pV, pH, pC;
  try { pV = program(SIM_VEL); pH = program(SIM_H); pC = program(COMP); } catch (e) { cv.remove(); return; }
  const mkTex = (flt = gl.LINEAR) => { const t = gl.createTexture(); gl.bindTexture(gl.TEXTURE_2D, t);
    for (const [k, v] of [[gl.TEXTURE_MIN_FILTER, flt], [gl.TEXTURE_MAG_FILTER, flt], [gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE], [gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE]]) gl.texParameteri(gl.TEXTURE_2D, k, v); return t; };
  const texSnap = mkTex(), texSharp = mkTex();   /* 糊的（玻璃底）＋清楚的（冰碎片裡看得到字被錯開） */

  let sim = null;
  function makeSim(w, h) {
    if (sim) { sim.texs.forEach(t => gl.deleteTexture(t)); sim.fbs.forEach(f => gl.deleteFramebuffer(f)); }
    const texs = [0, 1].map(() => { const t = mkTex(gl.NEAREST); gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA32F, w, h, 0, gl.RGBA, gl.FLOAT, null); return t; });
    const fbs = texs.map(t => { const f = gl.createFramebuffer(); gl.bindFramebuffer(gl.FRAMEBUFFER, f); gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, t, 0);
      gl.clearColor(0, 0, 0, 0); gl.clear(gl.COLOR_BUFFER_BIT); return f; });
    if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) !== gl.FRAMEBUFFER_COMPLETE) throw new Error('fbo');   /* 不支援浮點畫布 → 交給外層 catch，框維持原樣 */   /* 不支援浮點畫布 → 交給外層 catch，框維持原樣 */
    sim = { res: [w, h], texs, fbs, cur: 0, acc: 0 };
  }
  function simPass(p, setup) {
    const dst = 1 - sim.cur;
    gl.bindFramebuffer(gl.FRAMEBUFFER, sim.fbs[dst]); gl.viewport(0, 0, ...sim.res); gl.useProgram(p);
    gl.activeTexture(gl.TEXTURE1); gl.bindTexture(gl.TEXTURE_2D, sim.texs[sim.cur]); gl.uniform1i(p.u.uState, 1); gl.uniform2f(p.u.uSimRes, ...sim.res);
    gl.uniform1f(p.u.uH0, DEPTH); gl.uniform1f(p.u.uCorner, P.corner); gl.uniform1f(p.u.uBowl, P.bowl); gl.uniform1f(p.u.uRough, P.rough);
    setup && setup(); gl.drawArrays(gl.TRIANGLES, 0, 3); sim.cur = dst;
  }

  /* ── 後面網頁的快照：打開前（游標移到登入鈕上）先拍，打開時沒拍好就當場拍 ── */
  let snapKey = '', snapping = null, snapReady = false;
  const keyNow = () => [scrollX, scrollY, innerWidth, innerHeight, document.documentElement.dataset.theme].join(',');
  function snapshot() {
    const k = keyNow(), T0 = performance.now();
    if (k === snapKey && (snapReady || snapping)) return snapping || Promise.resolve();
    snapKey = k; snapReady = false;
    snapping = loadH2C().then(h2c => h2c(document.body, {
      x: scrollX, y: scrollY, width: innerWidth, height: innerHeight, windowWidth: innerWidth, windowHeight: innerHeight,
      scale: .5, logging: false, useCORS: true,
      ignoreElements: el => el.tagName === 'DIALOG',
      /* iPhone Safari：快照裡畫進 SVG（顆粒底紋、內嵌圖示）就會被標成不安全、不准給 WebGL → 拍之前拿掉，糊成一片看不出差 */
      onclone: doc => {
        doc.querySelectorAll('svg').forEach(e => e.remove());
        const cs = doc.defaultView.getComputedStyle.bind(doc.defaultView);
        doc.querySelectorAll('*').forEach(e => { if (/svg/i.test(cs(e).backgroundImage)) e.style.backgroundImage = 'none'; });
      },
    })).then(shot => {
      if (snapKey !== k) return;
      /* 糊：一半一半縮小到約每 8 個 CSS 像素一格，放大時由 GPU 內插＋合成時多點取樣變柔
         （iPhone Safari 不支援 2D 畫布的 filter: blur，10/17 實測沒糊、還被放大成拉伸） */
      { const d = document.createElement('canvas'); d.width = shot.width; d.height = shot.height; const dx = d.getContext('2d'); dx.drawImage(shot, 0, 0);
        dx.fillStyle = 'rgba(20,18,16,.32)'; dx.fillRect(0, 0, d.width, d.height);
        gl.bindTexture(gl.TEXTURE_2D, texSharp); gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, d); }
      let c = shot; const target = Math.max(8, innerWidth / 14);   /* 約每 14 個 CSS 像素一格 */
      while (c.width > target * 2) {
        const n = document.createElement('canvas'); n.width = Math.max(1, c.width >> 1); n.height = Math.max(1, c.height >> 1);
        const nx = n.getContext('2d'); nx.imageSmoothingQuality = 'high'; nx.drawImage(c, 0, 0, n.width, n.height); c = n;
      }
      const x = c.getContext('2d');
      x.fillStyle = 'rgba(20,18,16,.32)'; x.fillRect(0, 0, c.width, c.height);   /* 跟 ::backdrop 一樣蓋 32% 暗 */
      gl.bindTexture(gl.TEXTURE_2D, texSnap); gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, c);
      snapReady = true; if (dlg.open) { dlg.classList.add('mwater'); kick(); }   /* 快照比動畫晚到也要重畫一次 */
      dlg.dataset.water = 'snap ' + Math.round(performance.now() - T0) + 'ms';
    }).catch(e => {
      if (snapKey !== k) return;                                  /* 過期的那次失敗不要蓋掉新快照 */
      /* 保底：快照還是被擋 → 用網頁底色當玻璃底。後面的畫面透不出來，但水的亮光與晃動照樣看得到 */
      dlg.dataset.water = 'snapfail ' + (e && e.message || e);
      try {
        const c = document.createElement('canvas'); c.width = c.height = 4; const x = c.getContext('2d');
        x.fillStyle = getComputedStyle(document.body).backgroundColor || '#888'; x.fillRect(0, 0, 4, 4);
        x.fillStyle = 'rgba(20,18,16,.32)'; x.fillRect(0, 0, 4, 4);
        for (const t of [texSnap, texSharp]) { gl.bindTexture(gl.TEXTURE_2D, t); gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, c); }
        snapReady = true; if (dlg.open && snapKey === k) { dlg.classList.add('mwater'); kick(); }
        dlg.dataset.water += '（改用底色）';
      } catch (e2) {}
    });
    const job = snapping; job.finally(() => { if (snapping === job) snapping = null; });   /* 只清掉自己這次 */
    return snapping;
  }
  const warm = e => { if (e.target.closest?.('.mpill,[data-member],[data-member-login]')) snapshot(); };
  addEventListener('pointerover', warm, { passive: true });
  let scrollT = 0;
  addEventListener('scroll', () => { if (!dlg.open) return; clearTimeout(scrollT); scrollT = setTimeout(snapshot, 150); }, { passive: true });
  addEventListener('resize', () => { if (dlg.open) { measure(); snapshot(); kick(); } });   /* 改畫布尺寸會清空，要重畫 */

  /* ── 位置：登入框掛在彈簧上，用 CSS translate 動它；水只吃它的加速度 ── */
  const sp = { x: 0, y: 0, vx: 0, vy: 0 };
  let rest = { x: 0, y: 0, w: 0, h: 0 }, dpr = 1, run = 0, quietSince = 0, last = 0;
  let px0 = null, py0 = null, svx = 0, svy = 0;
  function measure() {
    dlg.style.translate = '0px 0px';
    const r = dlg.getBoundingClientRect(); rest = { x: r.left, y: r.top, w: r.width, h: r.height };
    dlg.style.translate = `${sp.x}px ${sp.y}px`;
    dpr = Math.min(devicePixelRatio || 1, 2);
    cv.width = Math.round(rest.w * dpr); cv.height = Math.round(rest.h * dpr);
    const m = 2 * P.margin * 240, w = Math.round((rest.w + m) / CELL), h = Math.round((rest.h + m) / CELL);
    if (!sim || sim.res[0] !== w || sim.res[1] !== h) makeSim(w, h);
  }
  function physics(dt) {
    const wx = rest.x + sp.x, wy = rest.y + sp.y;
    if (px0 === null) { px0 = wx; py0 = wy; }
    const vx = (wx - px0) / dt, vy = (wy - py0) / dt; px0 = wx; py0 = wy;
    const k = Math.min(1, dt * 30), nvx = svx + (vx - svx) * k, nvy = svy + (vy - svy) * k;
    let ax = (nvx - svx) / dt, ay = (nvy - svy) / dt; svx = nvx; svy = nvy;
    const am = Math.hypot(ax, ay); if (am > 30000) { ax *= 30000 / am; ay *= 30000 / am; }
    const sps = 8 * P.speed * 60, f = -P.slosh * .15 / (CELL * sps * sps), fx = ax * f, fy = ay * f;
    const damp = 1 - (1 - P.keep) * .004 - .0002;
    torchStep(dt, wx, wy);
    sim.acc += 8 * P.speed * dt * 60; let n = 0; const ns = Math.max(1, Math.floor(sim.acc));
    const s0 = torch.s0, s1 = torch.s1, mv = torch.mv;
    const keep = Math.exp(-1 / ((.06 + P.trail * .5) * sps)), gin = torch.E * P.torch * .12;
    while (sim.acc >= 1 && n < 24) { sim.acc -= 1; n++; const a0 = (n - 1) / ns, a1 = Math.min(1, n / ns);
      simPass(pV, () => { gl.uniform2f(pV.u.uAcc, fx, fy); gl.uniform1f(pV.u.uG, G); gl.uniform1f(pV.u.uDamp, damp); gl.uniform1f(pV.u.uVisc, .08);
        gl.uniform2f(pV.u.uM0, s0[0] + (s1[0] - s0[0]) * a0, s0[1] + (s1[1] - s0[1]) * a0); gl.uniform2f(pV.u.uM1, s0[0] + (s1[0] - s0[0]) * a1, s0[1] + (s1[1] - s0[1]) * a1);
        gl.uniform2f(pV.u.uMv, mv[0] / ns, mv[1] / ns); gl.uniform1f(pV.u.uStir, P.stir * torch.E); gl.uniform1f(pV.u.uGlowIn, gin); gl.uniform1f(pV.u.uGlowKeep, keep); });
      simPass(pH, () => gl.uniform1f(pH.u.uVisc, .08)); }
    return am;
  }
  /* ── 手電筒：滑鼠／手指在框上快速移動才亮（速度→亮度），同時撥水 ── */
  const torch = { x: -9999, y: -9999, lx: null, ly: null, E: 0, sp: 0, s0: [-99, -99], s1: [-99, -99], mv: [0, 0] };
  function torchStep(dt, wx, wy) {
    if (torch.lx === null) { torch.lx = torch.x; torch.ly = torch.y; }
    const v = Math.hypot(torch.x - torch.lx, torch.y - torch.ly) / dt; torch.sp += (v - torch.sp) * Math.min(1, dt * 25);
    const tgt = Math.min(1, Math.max(0, (torch.sp - 250) / 1300));
    torch.E += (tgt - torch.E) * (tgt > torch.E ? Math.min(1, dt * 18) : Math.min(1, dt / (.05 + P.trail * .2)));
    const m = P.margin * 240, cell = (x, y) => [(x - wx + m) / CELL, (y - wy + m) / CELL];
    torch.s0 = cell(torch.lx, torch.ly); torch.s1 = cell(torch.x, torch.y); torch.mv = [(torch.x - torch.lx) / CELL, (torch.y - torch.ly) / CELL];
    torch.lx = torch.x; torch.ly = torch.y;
  }
  dlg.addEventListener('pointermove', e => { const d = Math.hypot(e.clientX - torch.x, e.clientY - torch.y); torch.x = e.clientX; torch.y = e.clientY;
    if (d > 8 && dlg.open && dlg.classList.contains('mwater')) kick(); }, { passive: true });   /* 慢慢移不喚醒，省電 */
  function render() {
    gl.bindFramebuffer(gl.FRAMEBUFFER, null); gl.viewport(0, 0, cv.width, cv.height); gl.useProgram(pC); const u = pC.u;
    gl.activeTexture(gl.TEXTURE0); gl.bindTexture(gl.TEXTURE_2D, texSnap); gl.uniform1i(u.uSnap, 0);
    gl.activeTexture(gl.TEXTURE1); gl.bindTexture(gl.TEXTURE_2D, sim.texs[sim.cur]); gl.uniform1i(u.uSim, 1);
    gl.activeTexture(gl.TEXTURE2); gl.bindTexture(gl.TEXTURE_2D, texSharp); gl.uniform1i(u.uSharp, 2);
    gl.uniform2f(u.uView, innerWidth * dpr, innerHeight * dpr); gl.uniform2f(u.uSimRes, ...sim.res);
    gl.uniform4f(u.uWin, (rest.x + sp.x) * dpr, (rest.y + sp.y) * dpr, cv.width, cv.height);
    gl.uniform1f(u.uRadius, (parseFloat(getComputedStyle(dlg).borderTopLeftRadius) || 26) * dpr); gl.uniform1f(u.uDpr, dpr);
    gl.uniform1f(u.uWarp, P.warp); gl.uniform1f(u.uLens, P.lens); gl.uniform1f(u.uChroma, P.chroma); gl.uniform1f(u.uShine, P.shine);
    gl.uniform1f(u.uCorner, P.corner); gl.uniform1f(u.uMargin, P.margin * 240 * dpr); gl.uniform1f(u.uTint, P.tint); gl.uniform1f(u.uIce, P.ice);
    gl.uniform3f(u.uTorch, (torch.x - rest.x - sp.x) * dpr, (torch.y - rest.y - sp.y) * dpr, torch.E * P.torch);
    const card = getComputedStyle(dlg).getPropertyValue('--card').trim() || '#FCFAF9';
    const hx = i => parseInt(card.slice(i, i + 2), 16) / 255;
    if (/^#[0-9a-f]{6}$/i.test(card)) gl.uniform3f(u.uCard, hx(1), hx(3), hx(5));
    gl.drawArrays(gl.TRIANGLES, 0, 3);
  }
  let lastFrame = 0;
  const home = () => { if (run) cancelAnimationFrame(run); run = 0; sp.x = sp.y = sp.vx = sp.vy = 0; dlg.style.translate = ''; };
  const off = () => { home(); dlg.classList.remove('mwater'); dead = true; };   /* GPU 掉了／中途開「減少動態」→ 停掉，回原本登入框 */
  let dead = false;
  cv.addEventListener('webglcontextlost', e => { e.preventDefault(); off(); });
  rm.addEventListener?.('change', () => { if (rm.matches) off(); });
  function frame(now) { try { step(now); } catch (e) { home(); dlg.classList.remove('mwater'); } }   /* 出錯：框立刻回原位，登入照常 */
  function step(now) {
    lastFrame = performance.now();
    const dt = Math.max(.001, Math.min(.05, (now - last) / 1000)); last = now;
    const z = .95 - .8 * P.bounce;
    for (let i = 0; i < 4; i++) { const h = dt / 4;
      sp.vy += (-170 * sp.y - 2 * Math.sqrt(170) * z * sp.vy) * h; sp.y += sp.vy * h;
      sp.vx += (-700 * sp.x - 2 * Math.sqrt(700) * .09 * sp.vx) * h; sp.x += sp.vx * h; }
    dlg.style.translate = `${sp.x}px ${sp.y}px`;
    const am = physics(dt); render();
    const moving = Math.abs(sp.y) + Math.abs(sp.x) > .3 || Math.abs(sp.vy) + Math.abs(sp.vx) > 2 || am > 50 || torch.E > .02;
    if (moving) quietSince = now;
    /* 靜下來 2.5 秒就停止計算，不空轉耗電 */
    if (dlg.open && now - quietSince < 2500) run = requestAnimationFrame(frame);
    else { run = 0; sp.x = sp.y = 0; dlg.style.translate = ''; }
  }
  function kick() { if (!run && !dead) { last = quietSince = performance.now(); run = requestAnimationFrame(frame); } }

  /* ── 打開：從上方滑進來；輸錯：左右搖頭 ── */
  /* 打開時鎖住後面網頁的捲動：玻璃裡是快照，後面一滑就露餡（10/17 iPhone 實測） */
  const de = document.documentElement, lockSave = {};
  const lock = () => { lockSave.h = de.style.overflow; lockSave.b = document.body.style.overflow; de.style.overflow = document.body.style.overflow = 'hidden'; };
  const unlock = () => { de.style.overflow = lockSave.h || ''; document.body.style.overflow = lockSave.b || ''; };
  dlg.addEventListener('touchmove', e => { if (e.target === dlg) e.preventDefault(); }, { passive: false });
  const origShow = dlg.showModal.bind(dlg);
  dlg.showModal = () => {
    if (dlg.open) return origShow();                              /* 已經開著：不要再鎖一次（否則關掉後網頁不能捲） */
    origShow(); lock();
    if (dead) return;
    try {
      measure(); makeSim(...sim.res); px0 = null; svx = svy = 0; torch.lx = null; torch.E = torch.sp = 0;
      sp.x = 0; sp.vx = 0; sp.vy = 0; sp.y = -(rest.y + rest.h + 40);
      dlg.style.translate = `0px ${sp.y}px`;
      if (snapReady && snapKey === keyNow()) dlg.classList.add('mwater'); else snapshot();
      kick();
      /* 保險：動畫沒在跑（分頁在背景、瀏覽器暫停 rAF）→ 1.2 秒後框直接放回原位，不會卡在畫面外 */
      setTimeout(() => { if (dlg.open && performance.now() - lastFrame > 300 && (sp.x || sp.y)) home(); }, 1200);
    } catch (e) { dlg.classList.remove('mwater'); home(); }
  };
  dlg.addEventListener('close', () => { dlg.classList.remove('mwater'); home(); unlock(); });
  const msg = dlg.querySelector('.mmsg');
  if (msg) new MutationObserver(() => { if (/沒成功|失敗/.test(msg.textContent) && dlg.open) { sp.vx += 900; kick(); } })
    .observe(msg, { childList: true, characterData: true, subtree: true });
}
