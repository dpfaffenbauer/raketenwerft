#!/usr/bin/env python3
"""Erzeugt alle Geräusche und Musikstücke der Raketenwerft als WAV-Dateien.

Aufruf:  ~/.local/share/paulgame-tts/venv-mlx/bin/python tools/make_sfx.py
Ausgabe: audio/sfx/*.wav (44,1 kHz, mono, 16 bit)
Alles ist synthetisch (Rauschen, Oszillatoren, Filter) – keine fremden Aufnahmen.
"""
import os, wave
import numpy as np
from scipy import signal

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), '..', 'audio', 'sfx')
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7)


def save(name, x, peak=0.89):
    x = np.asarray(x, dtype=np.float64)
    m = np.max(np.abs(x)) or 1.0
    x = x / m * peak
    pcm = (x * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name + '.wav'), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
    print(f'{name}.wav  {len(x) / SR:.2f}s')


def t_(d): return np.arange(int(SR * d)) / SR
def white(d): return rng.uniform(-1, 1, int(SR * d))
def brown(d):
    w = rng.uniform(-1, 1, int(SR * d))
    b = signal.lfilter([0.02], [1, -0.98], w)
    return b / (np.max(np.abs(b)) or 1)
def lp(x, f, order=2): b, a = signal.butter(order, f / (SR / 2), 'low'); return signal.lfilter(b, a, x)
def hp(x, f, order=2): b, a = signal.butter(order, f / (SR / 2), 'high'); return signal.lfilter(b, a, x)
def bp(x, f0, f1, order=2): b, a = signal.butter(order, [f0 / (SR / 2), f1 / (SR / 2)], 'band'); return signal.lfilter(b, a, x)
def env_exp(d, k=5.0, attack=0.005):
    t = t_(d); e = np.exp(-k * t / d)
    a = np.clip(t / attack, 0, 1); return e * a
def tone(f, d, kind='sine', k=5, to=None, attack=0.008):
    t = t_(d)
    freq = f if to is None else f * (to / f) ** (t / d)
    ph = 2 * np.pi * np.cumsum(freq) / SR
    if kind == 'sine': s = np.sin(ph)
    elif kind == 'triangle': s = 2 / np.pi * np.arcsin(np.sin(ph))
    elif kind == 'square': s = np.sign(np.sin(ph)) * 0.6
    else: s = (ph / np.pi % 2) - 1  # Sägezahn
    return s * env_exp(d, k, attack)
def mix(total, *parts):
    out = np.zeros(int(SR * total))
    for at, x, g in parts:
        i = int(at * SR); n = min(len(x), len(out) - i)
        if n > 0: out[i:i + n] += x[:n] * g
    return out
def seamless(x, fade=0.25):
    """Schleife ohne Knacks: Ende weich in den Anfang überblenden."""
    n = int(fade * SR); a = x[:-n].copy(); tail = x[-n:]
    r = np.linspace(0, 1, n); a[:n] = a[:n] * r + tail * (1 - r)
    return a

# ---------- Schleifen (laufen dauernd, Lautstärke regelt das Spiel) ----------
save('loop_engine', seamless(lp(brown(4.25), 420, 3) * 0.9 + lp(signal.sawtooth(2 * np.pi * 38 * t_(4.25)), 90) * 0.5))
save('loop_hiss', seamless(bp(white(3.25), 1200, 2600) * 0.6))
save('loop_wind', seamless(bp(white(4.25), 350, 1100) * (0.8 + 0.2 * np.sin(2 * np.pi * 0.4 * t_(4.25)))))
crackle = np.zeros(int(SR * 3.25)); idx = rng.integers(0, len(crackle), 400); crackle[idx] = rng.uniform(-1, 1, 400)
save('loop_heat', seamless(lp(brown(3.25), 700) + lp(crackle, 3000) * 0.6))

# ---------- Einzelgeräusche ----------
save('click', tone(880, 0.07, 'triangle', 8))
save('snap', mix(0.15, (0, tone(520, 0.06, 'square', 8), 0.5), (0.03, tone(1040, 0.09, 'triangle', 8), 0.8), (0, hp(white(0.05), 2500) * env_exp(0.05, 6), 0.5)))
save('beep', tone(880, 0.2, 'sine', 3))
save('beep_hi', tone(1320, 0.55, 'sine', 3))
save('ignite', mix(1.8, (0, lp(brown(1.7), 900) * env_exp(1.7, 2.5, 0.02), 1.0), (0, bp(white(0.5), 400, 2400) * env_exp(0.5, 4), 0.5)))
save('clack', mix(0.6, (0, tone(160, 0.12, 'square', 6, 60), 0.6), (0, bp(white(0.15), 500, 1600) * env_exp(0.15, 6), 0.9), (0.05, lp(brown(0.5), 300) * env_exp(0.5, 4), 0.6)))
save('chute', mix(1.3, (0, bp(white(0.25), 300, 2000) * env_exp(0.25, 3), 0.8), (0.15, bp(white(1.0), 300, 1500) * env_exp(1.0, 3), 0.6)))
sp = mix(1.4, (0, lp(white(0.9), 700) * env_exp(0.9, 3), 1.0), (0.1, bp(white(0.6), 900, 2500) * env_exp(0.6, 4), 0.5))
for i in range(6): sp = sp + mix(1.4, (0.25 + rng.uniform(0, 0.6), tone(rng.uniform(500, 1400), 0.08, 'sine', 6), 0.2))
save('splash', sp)
save('thud', mix(0.5, (0, lp(brown(0.4), 260) * env_exp(0.4, 4), 1.0), (0, tone(70, 0.3, 'sine', 4, 40), 0.8)))
save('dock', mix(0.6, (0, tone(110, 0.25, 'square', 5, 70), 0.6), (0, bp(white(0.2), 400, 900) * env_exp(0.2, 5), 0.8), (0.25, tone(1400, 0.08, 'triangle', 6), 0.4), (0.35, tone(1800, 0.08, 'triangle', 6), 0.4)))
save('ding', mix(0.7, (0, tone(988, 0.2, 'sine', 4), 0.7), (0.12, tone(1319, 0.5, 'sine', 4), 0.7)))
save('crack', mix(0.4, (0, bp(white(0.3), 300, 2500) * env_exp(0.3, 5), 1.0), (0, tone(240, 0.25, 'saw', 5, 60), 0.3)))
save('boom', mix(1.3, (0, lp(brown(1.2), 400) * env_exp(1.2, 3), 1.0), (0, tone(55, 0.9, 'sine', 3, 30), 1.0)))
save('win', mix(1.6, *[(0.13 * i, tone(f, 0.35, 'triangle', 4), 0.6) for i, f in enumerate([523, 659, 784, 1047])],
                *[(0.55 + 0.02 * i, tone(f, 0.7, 'sine', 3), 0.3) for i, f in enumerate([784, 988, 1175, 1568])]))
save('sad', mix(1.3, *[(0.22 * i, tone(f, 0.35, 'triangle', 4), 0.6) for i, f in enumerate([392, 349, 311, 262])]))
save('whoosh', bp(white(0.8), 300, 2500) * np.sin(np.pi * t_(0.8) / 0.8))

# ---------- Musik ----------
def mtof(n): return 440 * 2 ** ((n - 69) / 12)
def reverb(x, secs=2.8, wet=0.35):
    n = int(secs * SR); ir = rng.uniform(-1, 1, n) * (1 - np.arange(n) / n) ** 3.2
    y = signal.fftconvolve(np.concatenate([x, x]), ir)[len(x):2 * len(x)]  # wie im Kreis -> nahtlose Schleife
    y /= (np.max(np.abs(y)) or 1)
    return x * (1 - wet) + y * wet * np.max(np.abs(x))
def song(bpm, prog, arp, lead, bass, pad, bars_repeat=2, lead_gain=0.5, space=False):
    spb = 60 / bpm / 2  # Achtel
    steps = len(prog) * 8 * bars_repeat
    total = steps * spb
    out = np.zeros(int(total * SR) + SR)
    for st in range(steps):
        bar = (st // 8) % len(prog); ch = prog[bar]; k = st % 8
        note = ch[arp[k % len(arp)] % len(ch)] + 12; at = st * spb
        def add(x, g):
            i = int(at * SR); n = min(len(x), len(out) - i); out[i:i + n] += x[:n] * g
        if space:
            if k % 2 == 0: add(tone(mtof(note), spb * 3.5, lead, 3, attack=0.05), lead_gain)
        else:
            add(tone(mtof(note), spb * 1.6, lead, 4), lead_gain)
            if k % 2 == 0: add(tone(mtof(note + 12), spb * 0.8, 'sine', 5), lead_gain * 0.3)
        if bass and k % 4 == 0: add(tone(mtof(ch[0] - 12), spb * 3.6, 'triangle', 3), 0.9)
        if pad and k == 0:
            for n in ch: add(tone(mtof(n), spb * 16, 'triangle', 1.5, attack=0.4), pad)
        if not space and k % 4 == 2: add(hp(white(0.05), 5000) * env_exp(0.05, 6), 0.25)
    loop = out[:int(total * SR)] + np.concatenate([out[int(total * SR):], np.zeros(int(total * SR) - (len(out) - int(total * SR)))])
    return reverb(loop, wet=0.5 if space else 0.22)

save('music_werft', song(104, [[60, 64, 67], [57, 60, 64], [65, 69, 72], [67, 71, 74]], [0, 1, 2, 1, 0, 2, 1, 2], 'triangle', True, 0, lead_gain=0.45), 0.6)
save('music_space', song(54, [[50, 57, 62, 66], [47, 54, 59, 62], [43, 50, 55, 59], [45, 52, 57, 61]], [0, 2, 3, 1], 'sine', False, 0.25, lead_gain=0.45, space=True), 0.6)
save('music_launch', song(132, [[57, 64, 69], [53, 60, 65], [55, 62, 67], [52, 59, 64]], [0, 1, 2, 1, 2, 1, 0, 1], 'saw', True, 0, lead_gain=0.25), 0.6)
