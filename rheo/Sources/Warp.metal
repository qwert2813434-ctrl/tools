#include <metal_stdlib>
using namespace metal;

// 扭曲引擎：全部效果共用一張位移場（float16 貼圖），每幀「擴散一點再衰減」＝慢慢流回來。
// 與 WebGL 原型同構（原型：扭曲鏡實驗/原型/手指扭曲原型.html）。座標一律左上原點。

struct Uniforms {
    float2 c;        // 觸點／筆刷中心
    float2 dir;      // 筆刷推力方向
    float2 px;       // 一個像素的 uv 大小（觀景窗 3:4，xy 不同）
    float  r;        // 半徑（uv）
    float  amt;      // 強度 0…1
    float  k;        // 鏡片融入速度
    float  decay;    // 回彈衰減（每幀）
    float  diff;     // 擴散量
    float  wave;     // 波長滑桿 0…1（噪聲蠕動／水波鏡面／水紋玻璃的紋理尺度）
    float  time;
    int    mode;     // 0凸鏡 1黑洞 2放射 3向前推 4側推 5流體 6噪聲 7自身位移 8水波鏡面
                     // ─ 桌面新家族（2026-08-14 定案：全部筆刷互動、場遮罩羽化）─
                     // 9細條長虹 10寬條長虹 11水紋玻璃 12長虹色散
                     // 13快門拖曳 14光軌拖曳（15/16 保留編號未用）
                     // 17漩渦絲綢 18拖曳絲流 19順紋流 20亂流大理石
    int    peek;     // 按住看原圖
};

struct VOut { float4 pos [[position]]; float2 uv; };

vertex VOut v_main(uint vid [[vertex_id]]) {
    // 一顆覆蓋全螢幕的大三角形
    float2 p = float2(vid == 1 ? 3.0 : -1.0, vid == 2 ? 3.0 : -1.0);
    VOut o;
    o.pos = float4(p, 0, 1);
    o.uv = float2(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5);
    return o;
}

constexpr sampler smp(filter::linear, address::clamp_to_edge);

// ── 液化：沿手指軌跡加一筆高斯衰減的向量 ──────────────────
fragment float4 f_stamp(VOut in [[stage_in]],
                        texture2d<float> f [[texture(0)]],
                        constant Uniforms& u [[buffer(0)]]) {
    float2 prev = f.sample(smp, in.uv).xy;
    float d = distance(in.uv, u.c) / u.r;
    return float4(prev + u.dir * u.amt * exp(-d * d), 0, 1);
}

// ── 反向清除（⌥ 拖曳）：把場在筆刷圓內乘小＝效果被局部擦掉 ──
fragment float4 f_erase(VOut in [[stage_in]],
                        texture2d<float> f [[texture(0)]],
                        constant Uniforms& u [[buffer(0)]]) {
    float2 prev = f.sample(smp, in.uv).xy;
    float d = distance(in.uv, u.c) / u.r;
    float k = 1.0 - u.amt * exp(-d * d);
    return float4(prev * max(k, 0.0), 0, 1);
}

// ── 鏡片：把鏡片形狀 mix 進位移場（放開就沒人寫，交給回彈）──
fragment float4 f_lens(VOut in [[stage_in]],
                       texture2d<float> f [[texture(0)]],
                       constant Uniforms& u [[buffer(0)]]) {
    float2 prev = f.sample(smp, in.uv).xy;
    float2 d = in.uv - u.c;
    float len = length(d);
    float2 t = in.uv;
    if (u.mode == 0) {                                   // 凸鏡
        if (len < u.r) { float q = 1.0 - len / u.r; t = u.c + d * (1.0 - u.amt * q * q); }
    } else if (u.mode == 1) {                            // 黑洞
        t = u.c + normalize(d + 1e-6) * sqrt(len * len + u.r * u.r * u.amt);
    } else {                                             // 放射拉扯
        float R = u.r * (1.2 - u.amt * 0.6);
        if (len > R) t = u.c + normalize(d) * R;
    }
    return float4(mix(prev, in.uv - t, u.k), 0, 1);
}

// ── 回彈：先擴散（往外流）再衰減（流回原位）──────────────
fragment float4 f_relax(VOut in [[stage_in]],
                        texture2d<float> f [[texture(0)]],
                        constant Uniforms& u [[buffer(0)]]) {
    float2 mid = f.sample(smp, in.uv).xy;
    float2 blur = (mid * 4.0
        + f.sample(smp, in.uv + float2(u.px.x, 0)).xy + f.sample(smp, in.uv - float2(u.px.x, 0)).xy
        + f.sample(smp, in.uv + float2(0, u.px.y)).xy + f.sample(smp, in.uv - float2(0, u.px.y)).xy) / 8.0;
    return float4(mix(mid, blur, u.diff) * u.decay, 0, 1);
}

// ── 場域家族用的噪聲 ───────────────────────────────────────
static float hash(float2 p) { return fract(sin(dot(p, float2(41.3, 289.1))) * 43758.5453); }
static float vnoise(float2 p) {
    float2 i = floor(p), g = fract(p);
    g = g * g * (3.0 - 2.0 * g);
    return mix(mix(hash(i), hash(i + float2(1, 0)), g.x),
               mix(hash(i + float2(0, 1)), hash(i + float2(1, 1)), g.x), g.y);
}
static float fbm(float2 p) { return vnoise(p) * 0.6 + vnoise(p * 2.1) * 0.3 + vnoise(p * 4.3) * 0.1; }

// ═══ 桌面新家族：共同核心＝「沿方向多次取樣」＋「筆刷畫進位移場」═══════
// 統一互動（2026-08-14 小高定調，以拖曳絲流為範本）：9-20 全部＝抹到哪、效果長到哪。
// 場強度｜f｜當存在感遮罩＝邊緣自然羽化（治「單點像馬賽克貼上去」）、回彈時整片流回去。

// 玻璃感 9-12：條狀透鏡位移＋條內縱向拖影＋條緣明暗
// 11 水紋玻璃＝波帶會自己流（time）＋手指攪動（fv 疊進位移）
static float3 glassColor(int mode, float2 uv, texture2d<float> img, constant Uniforms& u,
                         float2 fv) {
    if (mode == 11) {
        float ws = exp2((u.wave - 0.375) * 4.0);           // 波長滑桿＝波的尺度（×0.35–×2.8）
        float amp = u.amt * 0.045 * sqrt(ws);            // 大波振幅跟著加成，不然拉大會變平
        float tm = u.time;
        float ph1 = (fbm(float2(uv.x * 2.6 / ws + tm * 0.05, 0.37)) - 0.5) * 5.2;
        float ph2 = (fbm(float2(uv.x * 4.4 / ws - tm * 0.04, 7.13)) - 0.5) * 4.4;
        float w1 = uv.y * 57.2 / ws + ph1 + tm * 0.7;
        float dy = amp * (sin(w1) + 0.5 * sin(uv.y * 139.6 / ws + ph2 - tm * 1.1));
        // 絲沿波帶切線走（樣本間第一版盒狀橫拖被打回：均勻糊≠流動感）
        float ph1b = (fbm(float2((uv.x + 0.004) * 2.6 / ws + tm * 0.05, 0.37)) - 0.5) * 5.2;
        float tilt = amp * cos(w1) * (ph1b - ph1) / 0.004;
        float2 dir = normalize(float2(1.0, tilt * 2.0 + dy / max(amp, 1e-4) * 0.12));
        float2 base = uv - float2(0.0, dy) - fv * 0.6;          // 手指攪動疊進波裡
        float3 acc = float3(0.0);
        for (int i = -8; i <= 8; i++) {
            acc += img.sample(smp, clamp(base + dir * float(i) * 0.0034, 0.001, 0.999)).rgb;
        }
        return acc / 17.0;
    }
    float period = max(0.012, u.r * 0.2) * (mode == 10 ? 2.8 : 1.0);   // 範圍滑桿＝條寬
    float mag = 1.0 + u.amt * 3.0;                                      // 強度滑桿＝放大率
    float idx = floor(uv.x / period);
    float cx = (idx + 0.5) * period;
    float jit = (hash(float2(idx, 3.71)) - 0.5) * u.amt * 0.03;         // 條與條縱向錯位
    float2 t = float2(cx + (uv.x - cx) / mag, uv.y - jit);
    float sm = u.amt * 0.045 * (mode == 10 ? 0.5 : 1.0);                // 條內縱向拖影
    float3 acc = float3(0.0);
    for (int i = -6; i <= 6; i++) {
        float2 p = clamp(t + float2(0.0, sm * float(i) / 6.0), 0.001, 0.999);
        if (mode == 12) {                               // 色散：RGB 各自的放大率
            float2 pr = clamp(float2(cx + (uv.x - cx) / (mag * 1.16), p.y), 0.001, 0.999);
            float2 pb = clamp(float2(cx + (uv.x - cx) / (mag * 0.88), p.y), 0.001, 0.999);
            acc += float3(img.sample(smp, pr).r, img.sample(smp, p).g, img.sample(smp, pb).b);
        } else {
            acc += img.sample(smp, p).rgb;
        }
    }
    float su = fract(uv.x / period) - 0.5;              // 條緣壓暗＋亮稜線
    float edge = mode == 10 ? 0.8 : 1.0;
    float shade = 1.0 - 0.30 * edge * pow(abs(su) * 2.0, 2.5)
                + 0.22 * edge * exp(-pow((abs(su) - 0.44) / 0.04, 2.0));
    return acc / 13.0 * shade;
}

// 慢快門 13-15：快門軌跡＝抹過的方向與力道，亂抹＝亂竄
// 13 快門拖曳、14 光軌拖曳、15 移動高光（太陽慢快門：底圖不動，只有亮部拖出光痕）
static float3 shutterColor(int mode, float2 uv, texture2d<float> img, constant Uniforms& u,
                           float2 fv, float fm) {
    float2 v = fv / max(fm, 1e-5) * min(fm * 6.0, 0.22) * (0.3 + u.amt * 1.4);
    const int N = 12;
    float wpow = mode == 14 ? (2.0 + u.amt * 5.0) : 1.5;   // 光軌＝亮度高次方加權
    float3 acc = float3(0.0);
    float wsum = 0.0;
    for (int i = -N; i <= N; i++) {
        float2 p = clamp(uv + v * (float(i) / float(N) * 0.5), 0.001, 0.999);
        float3 s = img.sample(smp, p).rgb;
        float wgt = pow(dot(s, float3(0.299, 0.587, 0.114)) + 0.03, wpow);
        acc += s * wgt;
        wsum += wgt;
    }
    return acc / wsum;
}

// 移動高光 15：底圖清晰，高光沿「場線」絲滑推開（太陽慢快門）。
// 第一版用直線多點取樣被打回（小高：「像塗抹液化」）——25 點對長軌跡太疏，
// 每點一份太陽複製品疊成月牙梯。改 LIC 場線密步進＝連續光帶，距離衰減＝推開後慢慢散、不黏源頭
static float3 lightTrail(float2 uv, texture2d<float> img, texture2d<float> f,
                         constant Uniforms& u, float fm) {
    float3 orig = img.sample(smp, uv).rgb;
    float slen = 0.005 * (0.3 + u.amt) * min(fm / 0.02, 1.0);   // 強度拉滿單側可達 ~0.36
    const int STEPS = 40;
    float3 trail = float3(0.0);
    for (int s = 0; s < 2; s++) {
        float sgn = s == 0 ? 1.0 : -1.0;
        float2 p = uv;
        for (int i = 0; i < STEPS; i++) {
            float2 d = f.sample(smp, p).xy;
            float m = length(d);
            if (m < 1e-5) break;                        // 走出筆跡＝光帶自然停
            p = clamp(p + d / m * slen * sgn, 0.001, 0.999);
            float3 c = img.sample(smp, p).rgb;
            float fall = 1.0 - float(i) / float(STEPS); // 距離衰減
            float w = smoothstep(0.65, 0.90, dot(c, float3(0.299, 0.587, 0.114))) * fall;
            trail = max(trail, c * w);
        }
    }
    return 1.0 - (1.0 - orig) * (1.0 - trail);          // screen 疊加＝光痕畫在清晰底圖上
}

// 拖曳流動 17-20：沿場線逐步取樣（LIC）＝絲綢紋；方向都從「抹出來的場」長出來
static float2 silkDir(int mode, float2 p, texture2d<float> img, texture2d<float> f) {
    float2 fv = f.sample(smp, p).xy;
    if (mode == 17) return float2(-fv.y, fv.x);          // 漩渦絲綢：絲繞著筆劃打轉
    if (mode == 18) return fv;                           // 拖曳絲流：絲順著筆劃
    if (mode == 19) {                                    // 順紋流：亮度梯度轉 90°＝沿內容輪廓
        float2 e = float2(3.5 / (float)img.get_width(), 3.5 / (float)img.get_height());
        float3 w3 = float3(0.299, 0.587, 0.114);
        float2 g = float2(dot(img.sample(smp, p + float2(e.x, 0)).rgb, w3)
                        - dot(img.sample(smp, p - float2(e.x, 0)).rgb, w3),
                          dot(img.sample(smp, p + float2(0, e.y)).rgb, w3)
                        - dot(img.sample(smp, p - float2(0, e.y)).rgb, w3));
        return float2(g.y, -g.x);
    }
    return float2(fbm(p * 3.1) - 0.5, fbm(p * 3.1 + 11.3) - 0.5);   // 亂流大理石
}

static float3 silkColor(int mode, float2 uv, texture2d<float> img, texture2d<float> f,
                        constant Uniforms& u, float2 fv, float fm) {
    float2 base = uv - fv;                               // 位移照舊；回彈時絲跟著縮
    // 絲長跟著場強走＝邊緣的絲自然變短（羽化的另一半）
    float slen = 0.004 * (0.25 + u.amt * 1.5) * min(fm / 0.02, 1.0);
    float3 acc = img.sample(smp, clamp(base, 0.001, 0.999)).rgb;
    float n = 1.0;
    for (int s = 0; s < 2; s++) {                       // 正反兩向沿場線走
        float sgn = s == 0 ? 1.0 : -1.0;
        float2 p = base;
        for (int i = 0; i < 10; i++) {
            float2 d = silkDir(mode, p, img, f);
            float m = length(d);
            if (m < 1e-5) break;
            p = clamp(p + d / m * slen * sgn, 0.001, 0.999);
            acc += img.sample(smp, p).rgb;
            n += 1.0;
        }
    }
    return acc / n;
}

// 統一入口：場強度當遮罩，沒抹到＝原圖（也省效能）
static float3 desktopColor(int mode, float2 uv, texture2d<float> img, texture2d<float> f,
                           constant Uniforms& u) {
    float2 fv = f.sample(smp, uv).xy;
    float fm = length(fv);
    float m = smoothstep(0.0012, 0.014, fm);
    float3 orig = img.sample(smp, uv).rgb;
    if (m < 0.003) return orig;
    float3 col = mode <= 12 ? glassColor(mode, uv, img, u, fv)
               : (mode == 15 ? lightTrail(uv, img, f, u, fm)
               : (mode <= 16 ? shutterColor(mode, uv, img, u, fv, fm)
                             : silkColor(mode, uv, img, f, u, fv, fm)));
    return mix(orig, col, m);
}

// ── 上畫面 ─────────────────────────────────────────────────
fragment float4 f_draw(VOut in [[stage_in]],
                       texture2d<float> img [[texture(0)]],
                       texture2d<float> f [[texture(1)]],
                       constant Uniforms& u [[buffer(0)]]) {
    if (u.peek == 0 && u.mode >= 9) {                   // 桌面新家族＝筆刷畫進場、多次取樣
        return float4(desktopColor(u.mode, in.uv, img, f, u), 1);
    }
    float2 t = in.uv;
    if (u.peek == 0) {
        if (u.mode <= 5) {                               // 鏡片＋液化：讀同一張位移場
            t = in.uv - f.sample(smp, in.uv).xy;
        } else if (u.mode == 6) {                        // 噪聲蠕動：跟時間跑；波長滑桿調紋理尺度
            float ws = exp2((u.wave - 0.375) * 4.0);
            float2 n = float2(fbm(in.uv * 3.4 / ws + u.time * 0.12),
                              fbm(in.uv * 3.4 / ws - u.time * 0.09 + 7.3)) - 0.5;
            t = in.uv - n * u.amt * 0.55 * sqrt(ws);     // 大波振幅跟著加成，不然拉大會變平
        } else if (u.mode == 8) {                        // 鏡面震動：軟鏡面（鏡面布）被風吹的反射
            float tm = u.time;
            float ws = exp2((u.wave - 0.375) * 4.0);
            // 低頻大波＝薄膜的縐褶：縱向頻率高＝橫條紋，並隨時間漂移
            float n1 = fbm(in.uv * float2(2.0, 5.0) / ws + float2(0.0, tm * 0.13)) - 0.5;
            float n2 = fbm(in.uv * float2(3.0, 6.0) / ws + float2(tm * 0.09, 5.3)) - 0.5;
            // 疊一層快速抖動＝「一直震動」的那個高頻
            float vib = sin(in.uv.y * 40.0 / ws + tm * 22.0) * 0.35
                      + sin(in.uv.x * 26.0 / ws - tm * 17.0) * 0.25;
            float2 d = float2(n1 * 1.6 + vib * 0.15, n2 * 2.4 + vib * 0.25);
            t = in.uv - d * u.amt * 0.25 * sqrt(ws);
        } else {                                         // 自身位移：畫面明暗推自己
            float2 e = float2(3.5 / (float)img.get_width(), 3.5 / (float)img.get_height());
            float3 w = float3(0.299, 0.587, 0.114);
            float2 g = float2(dot(img.sample(smp, in.uv + float2(e.x, 0)).rgb, w)
                            - dot(img.sample(smp, in.uv - float2(e.x, 0)).rgb, w),
                              dot(img.sample(smp, in.uv + float2(0, e.y)).rgb, w)
                            - dot(img.sample(smp, in.uv - float2(0, e.y)).rgb, w));
            t = in.uv - g * u.amt * 1.6;
        }
    }
    // 來源已經先被裁成觀景窗比例，這裡直接取樣
    return float4(img.sample(smp, clamp(t, 0.001, 0.999)).rgb, 1);
}
