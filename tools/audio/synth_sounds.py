#!/usr/bin/env python3
"""Procedural sound design for Asthya (original, generated from noise and
sines; no samples). Ambience loops are seamless (cross-faded tail) and their
slow modulations use whole periods of the loop length.

usage: synth_sounds.py <repo_root>   -> assets/audio/<name>.wav (22.05 kHz mono)
requires numpy + scipy
"""
import sys
import wave
from pathlib import Path

import numpy as np
from scipy.signal import butter, lfilter

SR = 22050
rng = np.random.default_rng(1307)
OUT = Path(sys.argv[1] if len(sys.argv) > 1 else ".") / "assets/audio"
OUT.mkdir(parents=True, exist_ok=True)


def t_axis(sec):
    return np.arange(int(sec * SR)) / SR


def lp(x, hz, order=2):
    b, a = butter(order, hz / (SR / 2), "low")
    return lfilter(b, a, x)


def hp(x, hz, order=2):
    b, a = butter(order, hz / (SR / 2), "high")
    return lfilter(b, a, x)


def bp(x, lo, hi, order=2):
    b, a = butter(order, [lo / (SR / 2), hi / (SR / 2)], "band")
    return lfilter(b, a, x)


def lfo(t, length, cycles, phase=0.0):
    """Slow sine with an integer number of cycles over the loop (seamless)."""
    return np.sin(2 * np.pi * cycles * t / length + phase)


def varying_lp(x, cut):
    """One-pole low-pass with a per-sample cutoff (wind gusts)."""
    a = np.exp(-2 * np.pi * cut / SR)
    y = np.empty_like(x)
    s = 0.0
    for i in range(len(x)):
        s = a[i] * s + (1 - a[i]) * x[i]
        y[i] = s
    return y


def reverb(x, wet=0.35, size=1.0):
    """Small Schroeder reverb (4 combs + 2 all-passes)."""
    out = np.zeros(len(x) + int(SR * 2.5 * size))
    xx = np.concatenate([x, np.zeros(len(out) - len(x))])
    acc = np.zeros_like(out)
    for d, g in ((1557, 0.84), (1617, 0.83), (1491, 0.85), (1422, 0.86)):
        d = int(d * size)
        a = np.zeros(d + 1); a[0] = 1; a[d] = -g
        acc += lfilter([1.0], a, xx)
    acc /= 4
    for d, g in ((225, 0.5), (556, 0.5)):
        b = np.zeros(d + 1); b[0] = -g; b[d] = 1
        a = np.zeros(d + 1); a[0] = 1; a[d] = -g
        acc = lfilter(b, a, acc)
    out = xx * (1 - wet) + acc * wet
    return out


def loopify(x, fade_sec=2.0):
    """x has `fade` extra seconds at the end: cross-fade them into the start."""
    f = int(fade_sec * SR)
    body = x[:-f].copy()
    tail = x[-f:]
    ramp = np.linspace(0, 1, f)
    body[:f] = body[:f] * ramp + tail * (1 - ramp)
    return body


def norm(x, peak=0.8):
    m = np.max(np.abs(x)) or 1.0
    return x / m * peak


def write(name, x, peak=0.8):
    x = norm(x, peak)
    data = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(f"{name}: {len(x) / SR:.1f}s")


def wind(length, strength=1.0, brightness=600.0, fade=2.0):
    t = t_axis(length + fade)
    L = length
    n = rng.standard_normal(len(t))
    gust = 0.5 + 0.25 * lfo(t, L, 2) + 0.15 * lfo(t, L, 5, 1.3) + 0.1 * lfo(t, L, 11, 0.4)
    cut = brightness * (0.35 + 0.65 * np.clip(gust, 0, 1)) * strength
    w = varying_lp(n, cut)
    w = hp(w, 60)
    w *= 0.4 + 0.6 * np.clip(gust, 0, 1)
    whistle = bp(n, 700, 900, 2) * 0.15 * np.clip(lfo(t, L, 3, 2.0), 0, 1)
    return w + whistle


def drone(length, freqs, fade=2.0, amp=0.3):
    t = t_axis(length + fade)
    L = length
    d = np.zeros(len(t))
    for i, f in enumerate(freqs):
        f = round(f * L) / L  # whole cycles over the loop
        beat = 0.6 + 0.4 * lfo(t, L, 1 + i, i)
        d += np.sin(2 * np.pi * f * t) * beat / (i + 1)
    return d * amp


# ------------------------------------------------------------- ambiences
L = 24.0
write("amb_menu", loopify(wind(L, 1.0, 700) + drone(L, [55, 82.5, 110], amp=0.18)), 0.7)
hall_air = lp(rng.standard_normal(int((L + 2) * SR)), 300) * 0.6
write("amb_hall", loopify(reverb(hall_air + drone(L, [41, 61.5, 123], amp=0.5), 0.5)[: int((L + 2) * SR)]), 0.6)
t = t_axis(L + 2)
hum = drone(L, [65.4, 130.8, 196.2, 261.6], amp=0.5) * (0.7 + 0.3 * lfo(t, L, 12))
chant = bp(rng.standard_normal(len(t)), 300, 700) * 0.25 * (0.5 + 0.5 * lfo(t, L, 4, 0.7))
write("amb_ritual", loopify(hum + chant), 0.7)
void = lp(rng.standard_normal(len(t)), 220) * (0.6 + 0.4 * lfo(t, L, 3)) + drone(L, [32.7, 49, 98], amp=0.6)
write("amb_void", loopify(reverb(void, 0.6, 1.4)[: len(t)]), 0.7)
write("amb_meadow", loopify(wind(L, 0.8, 1400) * 0.8 + hp(lp(rng.standard_normal(len(t)), 4000), 1500) * 0.03), 0.55)


# ------------------------------------------------------------- one-shots
def env(t, attack, decay):
    return np.minimum(t / max(attack, 1e-4), 1.0) * np.exp(-t / decay)


t = t_axis(1.2)
partials = [(196, 1.0, 0.9), (503, 0.7, 0.7), (787, 0.5, 0.6), (1131, 0.35, 0.45), (1560, 0.25, 0.35), (2210, 0.15, 0.25)]
clang = sum(a * np.sin(2 * np.pi * f * t) * env(t, 0.002, d) for f, a, d in partials)
clang += hp(rng.standard_normal(len(t)), 2000) * env(t, 0.001, 0.03) * 0.6
write("clang", reverb(clang, 0.55, 1.6), 0.85)

t = t_axis(3.0)
rise = bp(rng.standard_normal(len(t)), 400, 3000) * np.clip(t / 0.8, 0, 1) * np.exp(-np.clip(t - 0.8, 0, None) * 4)
boom = np.sin(2 * np.pi * (48 + 30 * np.exp(-t * 6)) * t) * np.where(t > 0.8, np.exp(-(t - 0.8) * 2.2), 0)
shimmer = sum(np.sin(2 * np.pi * f * t) * np.where(t > 0.8, np.exp(-(t - 0.8) * 1.5), 0) for f in (880, 1318, 1760)) * 0.08
write("ritual", reverb(rise * 0.5 + boom + shimmer, 0.4), 0.9)

t = t_axis(3.0)
n = rng.standard_normal(len(t))
cut = 2500 * np.exp(-t * 1.2) + 120
whoosh = varying_lp(n, cut) * np.sin(np.pi * np.clip(t / 3.0, 0, 1)) ** 0.6
write("void", reverb(whoosh, 0.5, 1.3), 0.8)

t = t_axis(1.4)
rustle = np.zeros(len(t))
for start, dur in ((0.05, 0.25), (0.4, 0.3), (0.85, 0.35)):
    m = (t > start) & (t < start + dur)
    rustle[m] += np.sin(np.pi * (t[m] - start) / dur)
write("getup", bp(rng.standard_normal(len(t)), 1500, 5000) * rustle, 0.35)

t = t_axis(0.12)
click = np.sin(2 * np.pi * 1400 * t) * env(t, 0.001, 0.015) + hp(rng.standard_normal(len(t)), 3000) * env(t, 0.0005, 0.004) * 0.3
write("ui_move", click, 0.35)
t = t_axis(0.7)
chime = sum(a * np.sin(2 * np.pi * f * t) * env(t, 0.002, d) for f, a, d in ((988, 1.0, 0.25), (1482, 0.5, 0.18), (2470, 0.2, 0.1)))
write("ui_confirm", chime, 0.4)
t = t_axis(0.2)
write("ui_back", np.sin(2 * np.pi * 520 * t) * env(t, 0.001, 0.03) + np.sin(2 * np.pi * 390 * t) * env(t, 0.03, 0.03), 0.35)
t = t_axis(0.6)
op = bp(rng.standard_normal(len(t)), 2000, 6000) * env(t, 0.02, 0.08) * 0.5 + sum(
    np.sin(2 * np.pi * f * t) * env(t, 0.004, 0.2) for f in (659, 988)) * 0.6
write("ui_open", op, 0.35)
