'use strict';
/*
 * Sensory play for a toddler with a keyboard and a trackpad.
 * Every key, move and click does something gentle. Enter changes scene.
 * Typing the word "grownup" asks the laptop to show a login prompt (see docs/PARENT.md).
 */
(() => {
  const canvas = document.getElementById('c');
  const ctx = canvas.getContext('2d');
  const TAU = Math.PI * 2;
  const rand = (a, b) => a + Math.random() * (b - a);
  const hashStr = (s) => { let h = 7; for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0; return h; };

  let W = 0, H = 0, M = 0;
  function resize() {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    W = innerWidth; H = innerHeight; M = Math.min(W, H);
    canvas.width = Math.round(W * dpr); canvas.height = Math.round(H * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    scene && scene.reset && scene.reset();
  }

  /* ---------------------------------------------------------------- sound */
  const Sound = (() => {
    let ac = null, bus = null, voices = 0;
    const SCALE = [0, 2, 4, 7, 9]; // major pentatonic: everything sounds nice together
    function init() {
      if (ac) { if (ac.state === 'suspended') ac.resume(); return; }
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return;
      ac = new AC();
      const master = ac.createGain(); master.gain.value = 0.35;
      const comp = ac.createDynamicsCompressor();
      const delay = ac.createDelay(1); delay.delayTime.value = 0.27;
      const fb = ac.createGain(); fb.gain.value = 0.35;
      const wet = ac.createGain(); wet.gain.value = 0.3;
      const lp = ac.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 2200;
      bus = ac.createGain();
      bus.connect(master); bus.connect(delay);
      delay.connect(lp); lp.connect(fb); fb.connect(delay); lp.connect(wet); wet.connect(master);
      master.connect(comp); comp.connect(ac.destination);
    }
    function freq(step, base) {
      const n = ((step % 5) + 5) % 5, oct = Math.floor(step / 5);
      return base * Math.pow(2, (SCALE[n] + 12 * oct) / 12);
    }
    function tone(step, o = {}) {
      if (!ac || !bus || voices > 10) return;
      const { dur = 1.3, type = 'sine', gain = 0.22, base = 261.63 } = o;
      const t = ac.currentTime, osc = ac.createOscillator(), g = ac.createGain();
      voices++;
      osc.type = type; osc.frequency.value = freq(step, base);
      g.gain.setValueAtTime(0, t);
      g.gain.linearRampToValueAtTime(gain, t + 0.015);
      g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
      osc.connect(g); g.connect(bus);
      osc.onended = () => { voices--; g.disconnect(); };
      osc.start(t); osc.stop(t + dur + 0.05);
    }
    function pop() {
      if (!ac || !bus || voices > 12) return;
      const t = ac.currentTime, osc = ac.createOscillator(), g = ac.createGain();
      voices++;
      osc.type = 'sine';
      osc.frequency.setValueAtTime(rand(500, 800), t);
      osc.frequency.exponentialRampToValueAtTime(120, t + 0.09);
      g.gain.setValueAtTime(0.28, t);
      g.gain.exponentialRampToValueAtTime(0.0001, t + 0.12);
      osc.connect(g); g.connect(bus);
      osc.onended = () => { voices--; g.disconnect(); };
      osc.start(t); osc.stop(t + 0.14);
    }
    return { init, tone, pop };
  })();

  /* ------------------------------------------------------------ particles */
  const parts = [];
  const MAX_PARTS = 500;
  function spawn(p) { if (parts.length < MAX_PARTS) parts.push(p); }
  function burst(x, y, hue, n = 16, speed = 260) {
    for (let i = 0; i < n; i++) {
      const a = rand(0, TAU), s = rand(speed * 0.3, speed);
      spawn({ x, y, vx: Math.cos(a) * s, vy: Math.sin(a) * s, life: 0, max: rand(0.7, 1.4),
              size: rand(M * 0.008, M * 0.022), hue: hue + rand(-25, 25), drag: 1.8, g: 0 });
    }
  }
  function updateParts(dt) {
    for (let i = parts.length - 1; i >= 0; i--) {
      const p = parts[i];
      p.life += dt;
      if (p.life >= p.max) { parts.splice(i, 1); continue; }
      const d = Math.exp(-p.drag * dt);
      p.vx *= d; p.vy = p.vy * d + p.g * dt;
      p.x += p.vx * dt; p.y += p.vy * dt;
    }
  }
  function drawParts() {
    ctx.globalCompositeOperation = 'lighter';
    for (const p of parts) {
      const k = 1 - p.life / p.max;
      ctx.fillStyle = `hsla(${p.hue},95%,62%,${k * 0.9})`;
      ctx.beginPath(); ctx.arc(p.x, p.y, p.size * (0.4 + k), 0, TAU); ctx.fill();
    }
    ctx.globalCompositeOperation = 'source-over';
  }

  /* --------------------------------------------------------------- shapes */
  function path(shape, r) {
    ctx.beginPath();
    switch (shape) {
      case 0: ctx.arc(0, 0, r, 0, TAU); break;
      case 1: // star
        for (let i = 0; i < 10; i++) {
          const rr = i % 2 ? r * 0.45 : r, a = -Math.PI / 2 + i * Math.PI / 5;
          i ? ctx.lineTo(Math.cos(a) * rr, Math.sin(a) * rr) : ctx.moveTo(Math.cos(a) * rr, Math.sin(a) * rr);
        } ctx.closePath(); break;
      case 2: // heart
        ctx.moveTo(0, r * 0.9);
        ctx.bezierCurveTo(-r * 1.3, r * 0.1, -r * 0.9, -r * 0.95, 0, -r * 0.35);
        ctx.bezierCurveTo(r * 0.9, -r * 0.95, r * 1.3, r * 0.1, 0, r * 0.9);
        ctx.closePath(); break;
      case 3: // triangle
        ctx.moveTo(0, -r); ctx.lineTo(r * 0.95, r * 0.7); ctx.lineTo(-r * 0.95, r * 0.7); ctx.closePath(); break;
      case 4: // rounded square
        if (ctx.roundRect) ctx.roundRect(-r * 0.8, -r * 0.8, r * 1.6, r * 1.6, r * 0.25);
        else ctx.rect(-r * 0.8, -r * 0.8, r * 1.6, r * 1.6);
        break;
      default: // flower
        for (let i = 0; i < 6; i++) {
          const a = i * TAU / 6;
          ctx.moveTo(Math.cos(a) * r * 0.5 + r * 0.45, Math.sin(a) * r * 0.5);
          ctx.arc(Math.cos(a) * r * 0.5, Math.sin(a) * r * 0.5, r * 0.45, 0, TAU);
        }
    }
  }
  const easeOutBack = (t) => { const c = 1.9; t = Math.min(1, t); return 1 + (c + 1) * Math.pow(t - 1, 3) + c * Math.pow(t - 1, 2); };

  /* --------------------------------------------------------------- scenes */
  const pointer = { x: innerWidth / 2, y: innerHeight / 2, vx: 0, vy: 0, seen: false };
  let clock = 0;

  const sparkle = {
    emoji: '✨',
    shapes: [],
    reset() { this.shapes.length = 0; },
    key(info) {
      if (this.shapes.length > 14) this.shapes.shift();
      const r = M * rand(0.14, 0.26);
      const x = rand(r, W - r), y = rand(r, H - r);
      this.shapes.push({ x, y, r, hue: info.hue, shape: info.hash % 6, letter: info.letter, age: 0, life: 3.2 });
      burst(x, y, info.hue, 20);
      Sound.tone(info.step, { type: 'triangle' });
    },
    move(x, y) {
      if (Math.random() < 0.6) spawn({ x, y, vx: rand(-30, 30), vy: rand(-30, 30), life: 0, max: 0.9,
        size: M * 0.02, hue: (clock * 60) % 360, drag: 2, g: 0 });
    },
    down(x, y) { burst(x, y, rand(0, 360), 24); Sound.tone(Math.floor(rand(0, 10)), { type: 'triangle' }); },
    update(dt) { for (let i = this.shapes.length - 1; i >= 0; i--) { this.shapes[i].age += dt; if (this.shapes[i].age > this.shapes[i].life) this.shapes.splice(i, 1); } },
    draw() {
      const g = ctx.createLinearGradient(0, 0, W, H);
      const h = (clock * 8) % 360;
      g.addColorStop(0, `hsl(${h},55%,14%)`); g.addColorStop(1, `hsl(${(h + 70) % 360},55%,20%)`);
      ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
      for (const s of this.shapes) {
        const k = s.age / s.life, sc = easeOutBack(s.age / 0.45);
        ctx.save(); ctx.translate(s.x, s.y); ctx.scale(sc, sc); ctx.rotate(Math.sin(s.age * 2) * 0.08);
        ctx.globalAlpha = Math.max(0, 1 - Math.pow(k, 3));
        path(s.shape, s.r);
        ctx.fillStyle = `hsl(${s.hue},85%,60%)`; ctx.shadowColor = `hsl(${s.hue},90%,60%)`; ctx.shadowBlur = 40; ctx.fill();
        ctx.shadowBlur = 0;
        if (s.letter) {
          ctx.fillStyle = 'rgba(255,255,255,0.95)'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
          ctx.font = `bold ${s.r * 1.1}px "DejaVu Sans", sans-serif`; ctx.fillText(s.letter, 0, s.r * 0.05);
        }
        ctx.restore();
      }
    },
  };

  const bubbles = {
    emoji: '🫧',
    list: [], timer: 0,
    reset() { this.list.length = 0; },
    add(x) {
      this.list.push({ x: x ?? rand(0.05 * W, 0.95 * W), y: H + M * 0.1, r: M * rand(0.05, 0.12),
        vy: rand(40, 90), ph: rand(0, TAU), hue: rand(170, 320) });
    },
    popAt(x, y, force) {
      for (let i = this.list.length - 1; i >= 0; i--) {
        const b = this.list[i];
        if (Math.hypot(b.x - x, b.y - y) < b.r * (force ? 1.2 : 0.9)) {
          this.list.splice(i, 1); burst(b.x, b.y, b.hue, 12, 200); Sound.pop();
        }
      }
    },
    key(info) { for (let i = 0; i < 2; i++) this.add(); Sound.tone(info.step, { gain: 0.12, dur: 0.8 }); },
    move(x, y) { this.popAt(x, y, false); },
    down(x, y) { this.popAt(x, y, true); },
    update(dt) {
      this.timer -= dt;
      if (this.timer <= 0 && this.list.length < 25) { this.add(); this.timer = rand(0.5, 1.4); }
      for (let i = this.list.length - 1; i >= 0; i--) {
        const b = this.list[i];
        b.y -= b.vy * dt; b.x += Math.sin(clock * 1.3 + b.ph) * 22 * dt;
        if (b.y < -b.r * 2) this.list.splice(i, 1);
      }
    },
    draw() {
      const g = ctx.createLinearGradient(0, 0, 0, H);
      g.addColorStop(0, '#12385c'); g.addColorStop(1, '#0b6b78');
      ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
      for (const b of this.list) {
        const rg = ctx.createRadialGradient(b.x - b.r * 0.3, b.y - b.r * 0.3, b.r * 0.1, b.x, b.y, b.r);
        rg.addColorStop(0, 'rgba(255,255,255,0.75)');
        rg.addColorStop(0.6, `hsla(${b.hue},80%,70%,0.25)`);
        rg.addColorStop(1, `hsla(${b.hue},90%,75%,0.55)`);
        ctx.fillStyle = rg; ctx.beginPath(); ctx.arc(b.x, b.y, b.r, 0, TAU); ctx.fill();
        ctx.strokeStyle = 'rgba(255,255,255,0.5)'; ctx.lineWidth = 2; ctx.stroke();
      }
    },
  };

  const calm = {
    emoji: '🌙',
    orbs: [], rings: [],
    reset() {
      this.orbs = Array.from({ length: 26 }, () => ({ x: rand(0, W), y: rand(0, H), vx: 0, vy: 0,
        r: M * rand(0.03, 0.09), hue: rand(200, 290), ph: rand(0, TAU) }));
      this.rings.length = 0;
    },
    key(info) {
      this.rings.push({ x: rand(0.1 * W, 0.9 * W), y: rand(0.1 * H, 0.9 * H), age: 0, hue: 200 + (info.hash % 90) });
      if (this.rings.length > 8) this.rings.shift();
      Sound.tone(info.step % 8, { dur: 3.2, gain: 0.14, base: 130.81 });
    },
    move() {},
    down(x, y) { this.rings.push({ x, y, age: 0, hue: rand(200, 290) }); Sound.tone(Math.floor(rand(0, 6)), { dur: 3, gain: 0.12, base: 130.81 }); },
    update(dt) {
      for (const o of this.orbs) {
        o.vx += Math.cos(clock * 0.3 + o.ph) * 8 * dt; o.vy += Math.sin(clock * 0.25 + o.ph * 2) * 8 * dt;
        if (pointer.seen) { const dx = pointer.x - o.x, dy = pointer.y - o.y, d = Math.hypot(dx, dy) + 1; o.vx += dx / d * 14 * dt; o.vy += dy / d * 14 * dt; }
        o.vx *= Math.exp(-0.6 * dt); o.vy *= Math.exp(-0.6 * dt);
        o.x = (o.x + o.vx * dt + W) % W; o.y = (o.y + o.vy * dt + H) % H;
      }
      for (let i = this.rings.length - 1; i >= 0; i--) { this.rings[i].age += dt; if (this.rings[i].age > 4) this.rings.splice(i, 1); }
    },
    draw() {
      const g = ctx.createLinearGradient(0, 0, 0, H);
      g.addColorStop(0, '#0a0f2c'); g.addColorStop(1, '#1b1040');
      ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
      ctx.globalCompositeOperation = 'lighter';
      for (const o of this.orbs) {
        const pulse = 1 + Math.sin(clock * 0.8 + o.ph) * 0.12, r = o.r * pulse;
        const rg = ctx.createRadialGradient(o.x, o.y, 0, o.x, o.y, r * 2);
        rg.addColorStop(0, `hsla(${o.hue},80%,65%,0.55)`); rg.addColorStop(1, `hsla(${o.hue},80%,50%,0)`);
        ctx.fillStyle = rg; ctx.beginPath(); ctx.arc(o.x, o.y, r * 2, 0, TAU); ctx.fill();
      }
      for (const r of this.rings) {
        const k = r.age / 4;
        ctx.strokeStyle = `hsla(${r.hue},80%,70%,${(1 - k) * 0.7})`; ctx.lineWidth = M * 0.012 * (1 - k) + 1;
        ctx.beginPath(); ctx.arc(r.x, r.y, M * (0.05 + k * 0.5), 0, TAU); ctx.stroke();
      }
      ctx.globalCompositeOperation = 'source-over';
    },
  };

  const paint = {
    emoji: '🌈',
    last: null, fresh: true,
    reset() { this.fresh = true; this.last = null; },
    key(info) {
      const x = pointer.seen ? pointer.x : W / 2, y = pointer.seen ? pointer.y : H / 2;
      for (let i = 0; i < 9; i++) {
        ctx.fillStyle = `hsla(${info.hue + rand(-30, 30)},90%,60%,0.85)`;
        ctx.beginPath(); ctx.arc(x + rand(-M * 0.12, M * 0.12), y + rand(-M * 0.12, M * 0.12), M * rand(0.02, 0.07), 0, TAU); ctx.fill();
      }
      Sound.tone(info.step, { type: 'sine', gain: 0.18 });
    },
    move(x, y) {
      const sp = Math.hypot(pointer.vx, pointer.vy);
      if (this.last) {
        ctx.strokeStyle = `hsl(${(clock * 90) % 360},90%,60%)`;
        ctx.lineWidth = M * 0.015 + Math.min(sp * 0.02, M * 0.04); ctx.lineCap = 'round';
        ctx.beginPath(); ctx.moveTo(this.last.x, this.last.y); ctx.lineTo(x, y); ctx.stroke();
      }
      this.last = { x, y };
    },
    down(x, y) {
      ctx.fillStyle = `hsl(${rand(0, 360)},90%,60%)`; ctx.beginPath(); ctx.arc(x, y, M * 0.09, 0, TAU); ctx.fill();
      Sound.tone(Math.floor(rand(0, 10)), { gain: 0.18 });
    },
    update() {},
    draw() { // persistent canvas: slowly fade instead of clearing
      if (this.fresh) { ctx.fillStyle = '#0b1020'; ctx.fillRect(0, 0, W, H); this.fresh = false; }
      ctx.fillStyle = 'rgba(11,16,32,0.035)'; ctx.fillRect(0, 0, W, H);
    },
  };

  const scenes = [sparkle, bubbles, calm, paint];
  let sceneIdx = 0, scene = scenes[0], bannerAge = 99;

  function setScene(i) {
    sceneIdx = (i + scenes.length) % scenes.length; scene = scenes[sceneIdx];
    parts.length = 0; scene.reset && scene.reset(); bannerAge = 0;
    Sound.tone(sceneIdx * 2 + 3, { dur: 0.8, gain: 0.15 });
  }

  /* ---------------------------------------------------------------- input */
  let lastInput = performance.now();
  const touch = () => { lastInput = performance.now(); Sound.init(); };

  let typed = '', typedAt = 0;
  function parentChord(e) {
    if (e.key.length !== 1) return;
    const now = performance.now();
    if (now - typedAt > 2000) typed = '';
    typedAt = now; typed = (typed + e.key.toLowerCase()).slice(-7);
    if (typed === 'grownup') {
      typed = '';
      fetch('/api/parent', { method: 'POST' }).catch(() => {});
      const n = document.getElementById('note');
      n.textContent = 'Grown-up mode… log in on the next screen.'; n.hidden = false;
    }
  }

  addEventListener('keydown', (e) => {
    e.preventDefault(); touch();
    parentChord(e);
    if (e.repeat) return;
    if (e.key === 'Enter') { setScene(sceneIdx + 1); return; }
    const hash = hashStr(e.code || e.key);
    const letter = /^[a-z0-9]$/i.test(e.key) ? e.key.toUpperCase() : '';
    scene.key({ hash, hue: (hash * 47) % 360, step: hash % 12, letter });
  }, true);
  addEventListener('keyup', (e) => e.preventDefault(), true);

  addEventListener('pointermove', (e) => {
    touch();
    pointer.vx = e.clientX - pointer.x; pointer.vy = e.clientY - pointer.y;
    pointer.x = e.clientX; pointer.y = e.clientY; pointer.seen = true;
    scene.move(pointer.x, pointer.y);
  });
  addEventListener('pointerdown', (e) => { touch(); pointer.x = e.clientX; pointer.y = e.clientY; pointer.seen = true; scene.down(e.clientX, e.clientY); });
  for (const t of ['contextmenu', 'dragstart', 'wheel', 'auxclick']) addEventListener(t, (e) => e.preventDefault(), { passive: false });

  /* ----------------------------------------------------------------- loop */
  let prev = performance.now();
  function frame(now) {
    const dt = Math.min((now - prev) / 1000, 0.05); prev = now; clock += dt;
    const idle = (now - lastInput) / 1000;

    if (idle > 300) { // sleepy: black screen, one slow star, almost no CPU
      ctx.fillStyle = '#000'; ctx.fillRect(0, 0, W, H);
      ctx.fillStyle = `rgba(255,255,255,${0.2 + 0.2 * Math.sin(clock)})`;
      ctx.beginPath(); ctx.arc(W * (0.3 + 0.4 * ((clock / 60) % 1)), H * 0.5, 3, 0, TAU); ctx.fill();
      scene.fresh = true;
      setTimeout(() => requestAnimationFrame(frame), 250);
      return;
    }

    scene.update(dt); updateParts(dt);
    scene.draw(); drawParts();

    if (pointer.seen) { // soft glow cursor
      ctx.globalCompositeOperation = 'lighter';
      const rg = ctx.createRadialGradient(pointer.x, pointer.y, 0, pointer.x, pointer.y, M * 0.05);
      rg.addColorStop(0, 'rgba(255,255,255,0.9)'); rg.addColorStop(1, 'rgba(255,255,255,0)');
      ctx.fillStyle = rg; ctx.beginPath(); ctx.arc(pointer.x, pointer.y, M * 0.05, 0, TAU); ctx.fill();
      ctx.globalCompositeOperation = 'source-over';
    }
    if (bannerAge < 1.3) { // scene emoji
      bannerAge += dt;
      ctx.globalAlpha = Math.max(0, 1 - bannerAge / 1.3);
      ctx.font = `${M * 0.3}px "Noto Color Emoji", sans-serif`; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillText(scene.emoji, W / 2, H / 2); ctx.globalAlpha = 1;
    }
    requestAnimationFrame(frame);
  }

  /* ------------------------------------------- pick up updates when idle */
  let loadedVersion = null;
  async function checkVersion() {
    try {
      const r = await fetch('/version.json', { cache: 'no-store' });
      const v = (await r.json()).version;
      if (loadedVersion === null) loadedVersion = v;
      else if (v !== loadedVersion && (performance.now() - lastInput) / 1000 > 45) location.reload();
    } catch (_) { /* server restarting; try again later */ }
  }
  setInterval(checkVersion, 30000); checkVersion();

  addEventListener('resize', resize);
  resize(); setScene(0); bannerAge = 99;
  requestAnimationFrame(frame);
})();
