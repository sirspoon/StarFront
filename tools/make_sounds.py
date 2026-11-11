#!/usr/bin/env python3
"""Makes StarFront's sound effects from scratch (no recordings), into sounds/*.wav.

Each sound is layered the way film and game sound designers build weapon sounds:
a deep sine "thump" for weight, filtered noise for the blast body, a short bright
crack for the attack, sparse clicks for debris, soft saturation for punch, and an
echoey room/outdoor tail. Every sound has a few variants so repeats don't sound
identical. Re-run after changing anything here:  python3 tools/make_sounds.py
Needs numpy.
"""
import os
import wave
import zlib

import numpy as np

SR = 32000
OUT = os.path.join(os.path.dirname(__file__), "..", "sounds")


# ---------------------------------------------------------------- building blocks

def T(dur):
    return np.arange(int(dur * SR)) / SR


def noise(n, rng):
    return rng.standard_normal(n)


def filt(x, lo=None, hi=None, order=2):
    """Soft band filter in the frequency domain (circular, so loops stay seamless)."""
    n = len(x)
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1 / SR)
    g = np.ones_like(f)
    if hi:
        g /= 1 + (f / hi) ** (2 * order)
    if lo:
        g /= 1 + (lo / np.maximum(f, 1e-3)) ** (2 * order)
    return np.fft.irfft(X * g, n)


def env(n, attack, decay, hold=0.0):
    t = np.arange(n) / SR
    e = np.minimum(1.0, t / max(attack, 1e-5))
    tail = np.clip(t - attack - hold, 0, None)
    return e * np.exp(-tail / decay)


def chirp(dur, f0, f1, curve=4.0):
    """A sine sweeping from f0 to f1, quickly at first (exponential glide)."""
    t = T(dur)
    k = 1 - np.exp(-curve * t / dur)
    k /= k[-1] if k[-1] else 1
    f = f0 + (f1 - f0) * k
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def sat(x, drive):
    return np.tanh(x * drive) / np.tanh(drive)


def place(dst, src, at):
    i = int(at * SR)
    if i >= len(dst):
        return
    j = min(len(dst), i + len(src))
    dst[i:j] += src[: j - i]


def reverb(x, t60, wet, rng, bright=4000, slap=None):
    """Convolve with decaying noise (a room or the open air between buildings)."""
    n = int(t60 * SR)
    ir = filt(noise(n, rng), hi=bright) * np.exp(-6.9 * np.arange(n) / n)
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    out_n = len(x) + n
    N = 1 << int(np.ceil(np.log2(out_n)))
    wetsig = np.fft.irfft(np.fft.rfft(x, N) * np.fft.rfft(ir, N), N)[: len(x)]
    y = x + wet * wetsig
    if slap:  # distinct echoes off far walls
        for delay, gain in slap:
            echo = np.zeros_like(y)
            place(echo, filt(x, hi=1800) * gain, delay)
            y += echo
    return y


def finish(x, peak=0.89, fade=0.08):
    x = x - np.mean(x)
    # small speakers (phones, laptops) barely play below ~200 Hz: lift the "punch" band
    # they do play, and trim the deepest sub-bass that only eats headroom
    x = x + 0.9 * filt(x, lo=170, hi=650) - 0.6 * filt(x, hi=32)
    x = sat(x / (np.max(np.abs(x)) + 1e-9), 1.3)
    f = int(fade * SR)
    if f and len(x) > f:
        x[-f:] *= np.linspace(1, 0, f)
    return x / (np.max(np.abs(x)) + 1e-9) * peak


def save(name, x):
    os.makedirs(OUT, exist_ok=True)
    data = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def debris(n, rng, start, end, count, lo=700, hi=4000, size=1.0):
    """Falling stones and fragments: a shower of short knocks, thinning out."""
    out = np.zeros(n)
    for _ in range(count):
        at = start + (end - start) * rng.random() ** 1.8
        ln = int(rng.uniform(0.006, 0.03) * SR)
        k = filt(noise(ln, rng), lo=lo * rng.uniform(0.6, 1.4), hi=hi) * env(ln, 0.0005, ln / SR / 4)
        place(out, k * rng.uniform(0.15, 1.0) * size * (1 - (at - start) / (end - start + 1e-9)) ** 0.7, at)
    return out


# ---------------------------------------------------------------- the sounds

def explosion(rng, dur=3.8, size=1.0):
    n = int(dur * SR)
    x = np.zeros(n)
    sub = chirp(dur, 80, 26, 6) * env(n, 0.004, 0.5 * size)
    body = filt(noise(n, rng), hi=420) * env(n, 0.003, 0.8 * size) * 2.2
    mid = filt(noise(n, rng), lo=250, hi=2600) * env(n, 0.001, 0.22 * size) * 1.8
    crack = filt(noise(n, rng), lo=1800) * env(n, 0.0003, 0.025) * 1.4
    am = filt(noise(n, rng), hi=6) * 4
    rumble = filt(noise(n, rng), hi=160) * env(n, 0.06, 1.7 * size) * (0.6 + 0.4 * np.tanh(am)) * 2.0
    x += sub * 1.4 + body + mid + crack + rumble
    x += debris(n, rng, 0.12, 2.6 * size, int(70 * size), size=0.9)
    x = sat(x / np.max(np.abs(x)) * 1.0, 2.6)
    x = reverb(x, 2.4, 0.45, rng, bright=2500, slap=[(0.31, 0.25), (0.74, 0.14)])
    return finish(x, fade=0.4)


def small_explosion(rng):
    n = int(1.9 * SR)
    sub = chirp(1.9, 110, 40, 7) * env(n, 0.002, 0.18)
    body = filt(noise(n, rng), hi=900) * env(n, 0.002, 0.3) * 1.8
    crack = filt(noise(n, rng), lo=1500) * env(n, 0.0003, 0.02) * 1.3
    x = sub * 1.2 + body + crack + debris(n, rng, 0.05, 1.0, 30, size=0.6)
    x = sat(x / np.max(np.abs(x)), 2.4)
    x = reverb(x, 1.6, 0.35, rng, bright=3000, slap=[(0.24, 0.2)])
    return finish(x, fade=0.3)


def cannon(rng):
    """The tank's siege cannon going off: a huge crack and thump, echoing round the ruins."""
    n = int(3.0 * SR)
    crack = filt(noise(n, rng), lo=900) * env(n, 0.0002, 0.03) * 2.0
    sub = chirp(3.0, 70, 38, 5) * env(n, 0.002, 0.35) * 1.8
    body = filt(noise(n, rng), hi=700) * env(n, 0.002, 0.45) * 2.0
    bark = filt(noise(n, rng), lo=400, hi=3000) * env(n, 0.0005, 0.07) * 1.8
    x = sat(crack + sub + body + bark, 3.0)
    x = reverb(x, 2.6, 0.5, rng, bright=2200, slap=[(0.19, 0.4), (0.46, 0.25), (0.9, 0.12)])
    return finish(x, fade=0.5)


def fusion(rng, big=True):
    """A fusion weapon: a falling electric zap, crackling buzz and a heavy thump."""
    dur = 2.4 if big else 0.9
    n = int(dur * SR)
    zap = sat(chirp(dur, 2600 if big else 3200, 140, 9), 3) * env(n, 0.001, 0.22 if big else 0.08)
    buzz_mod = 0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 120 * T(dur)))
    buzz = filt(noise(n, rng), lo=900, hi=6000) * buzz_mod * env(n, 0.001, 0.3 if big else 0.1) * 1.3
    sub = chirp(dur, 90, 35, 6) * env(n, 0.003, 0.4 if big else 0.12) * (1.6 if big else 0.8)
    x = zap * 0.8 + buzz + sub
    x += debris(n, rng, 0.05, 0.8 if big else 0.3, 40 if big else 12, lo=2000, hi=8000, size=0.5)
    x = sat(x / np.max(np.abs(x)), 2.0)
    x = reverb(x, 1.8 if big else 0.9, 0.4, rng, bright=5000, slap=[(0.22, 0.2)] if big else None)
    return finish(x, fade=0.3 if big else 0.1)


def laser(rng):
    """The Legion's lumen rifle: a sharp pop with a falling electric tone."""
    dur = 0.55
    n = int(dur * SR)
    f0 = rng.uniform(1900, 2600)
    tone = chirp(dur, f0, rng.uniform(260, 380), 10)
    tone = (tone + 0.35 * np.sin(2 * np.arcsin(np.clip(tone, -1, 1)))) * env(n, 0.0005, 0.045)
    pop = filt(noise(n, rng), lo=400, hi=5000) * env(n, 0.0002, 0.012) * 1.6
    thump = chirp(dur, 180, 90, 6) * env(n, 0.001, 0.035) * 0.9
    x = sat(tone * 0.9 + pop + thump, 1.8)
    x = reverb(x, 0.8, 0.28, rng, bright=6000, slap=[(0.16, 0.15)])
    return finish(x, peak=0.8, fade=0.1)


def round_(rng, weight, n):
    """One heavy round firing: crack, blast body, low thump and the bolt's clack."""
    crack = filt(noise(n, rng), lo=2000) * env(n, 0.0002, 0.008) * 1.5
    body = filt(noise(n, rng), lo=80, hi=1400 / weight) * env(n, 0.0008, 0.05 * weight) * 2.0
    thump = chirp(n / SR, 95 / weight ** 0.5, 45, 6) * env(n, 0.001, 0.06 * weight) * 1.4 * weight
    clack = np.zeros(n)
    place(clack, filt(noise(int(0.01 * SR), rng), lo=3000, hi=7000) * env(int(0.01 * SR), 0.0002, 0.003) * 0.4, 0.028)
    blast = filt(noise(n, rng), lo=500, hi=3500) * env(n, 0.0003, 0.018 * weight) * 1.6  # the bark
    return crack + body + thump + clack + blast


def burst(rng, rounds, gap, weight, explosive=False, spin=False, tail=1.4):
    dur = rounds * gap + tail
    n = int(dur * SR)
    x = np.zeros(n)
    rn = int(0.4 * SR)
    for k in range(rounds):
        at = k * gap + rng.uniform(-0.006, 0.006) * (k > 0)
        place(x, round_(rng, weight * rng.uniform(0.9, 1.1), rn) * rng.uniform(0.85, 1.0), max(at, 0))
        if explosive:  # mass-reactive bolts burst a moment later, downrange
            pn = int(0.15 * SR)
            pop = filt(noise(pn, rng), hi=1800) * env(pn, 0.001, 0.04) * 0.55
            place(x, pop, at + rng.uniform(0.07, 0.14))
    if spin:  # the rotor cannon's barrels spinning up and down
        t = T(dur)
        on = np.clip(t / 0.15, 0, 1) * np.clip((rounds * gap + 0.25 - t) / 0.3, 0, 1)
        whine = sum(np.sin(2 * np.pi * f * t) / (i + 1) for i, f in enumerate([310, 620, 930]))
        x += whine * on * 0.18 + filt(noise(n, rng), lo=200, hi=900) * on * 0.25
    x = sat(x / np.max(np.abs(x)), 2.2)
    x = reverb(x, 1.3, 0.35, rng, bright=3000, slap=[(0.2, 0.22), (0.55, 0.1)])
    return finish(x, fade=0.4)


def ricochet(rng):
    dur = 0.6
    n = int(dur * SR)
    t = T(dur)
    f0 = rng.uniform(2600, 3600)
    f1 = rng.uniform(700, 1200)
    f = f0 + (f1 - f0) * (t / dur) ** 0.6 + 60 * np.sin(2 * np.pi * rng.uniform(25, 40) * t)
    whine = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.004, 0.18)
    ping = filt(noise(n, rng), lo=2500) * env(n, 0.0002, 0.006) * 1.2
    x = reverb(whine * 0.8 + ping, 0.7, 0.3, rng, bright=7000)
    return finish(x, peak=0.7, fade=0.1)


def clang(rng):
    """A round bouncing off armour plate."""
    dur = 0.7
    n = int(dur * SR)
    t = T(dur)
    f0 = rng.uniform(260, 420)
    x = sum(np.sin(2 * np.pi * f0 * r * t) * env(n, 0.0005, 0.25 / (i + 1)) / (i + 1)
            for i, r in enumerate([1.0, 2.76, 5.4, 8.93]))
    x += filt(noise(n, rng), lo=2000) * env(n, 0.0002, 0.005)
    return finish(reverb(x, 0.5, 0.2, rng), peak=0.7, fade=0.1)


def collapse(rng):
    """A wall coming down: a heavy thud, then rubble pouring and settling."""
    dur = 3.2
    n = int(dur * SR)
    thud = chirp(dur, 70, 35, 5) * env(n, 0.01, 0.3) * 1.5
    pour = filt(noise(n, rng), lo=60, hi=700) * env(n, 0.05, 1.0) * 1.3
    x = thud + pour + debris(n, rng, 0.05, 2.8, 160, lo=300, hi=3000, size=1.0)
    x = sat(x / np.max(np.abs(x)), 2.0)
    x = reverb(x, 1.8, 0.35, rng, bright=2500)
    return finish(x, fade=0.4)


def lance(rng):
    """A lance rocket launching: ignition pop, then a hissing whoosh away."""
    dur = 1.3
    n = int(dur * SR)
    t = T(dur)
    pop = filt(noise(n, rng), hi=1500) * env(n, 0.001, 0.05) * 1.5
    centre = 2500 * np.exp(-t * 1.5) + 600
    hiss = np.zeros(n)
    w = noise(n, rng)
    for k in range(0, n, 1024):  # sweep the band down as the rocket flies off
        seg = slice(k, min(n, k + 1024))
        c = centre[k]
        hiss[seg] = filt(w, lo=c * 0.5, hi=c * 2)[seg]
    hiss *= env(n, 0.02, 0.5) * 1.2
    x = sat(pop + hiss, 1.6)
    return finish(reverb(x, 1.2, 0.3, rng, slap=[(0.25, 0.15)]), fade=0.3)


def engine(rng, dur=2.0):
    """A tracked vehicle's engine and tracks, as a seamless loop: diesel chug,
    exhaust rumble and the clatter of track links."""
    n = int(dur * SR)
    t = T(dur)
    chug = 0.6 + 0.4 * np.maximum(0, np.sin(2 * np.pi * 7.5 * t)) ** 2  # 15 cycles: loops cleanly
    drone = sum(np.sin(2 * np.pi * 30 * h * t + rng.uniform(0, 6)) / h ** 0.8 for h in range(1, 7))
    x = sat(drone * chug * 0.5, 2.5)
    x += filt(noise(n, rng), hi=260) * chug * 1.4  # circular filter: still loops seamlessly
    clatter = np.zeros(n)
    for k in range(20):  # 10 links a second
        at = k * dur / 20 + rng.uniform(-0.005, 0.005)
        ln = int(0.02 * SR)
        knock = filt(noise(ln, rng), lo=900, hi=4000) * env(ln, 0.0005, 0.005) * (0.5 if k % 2 else 0.8)
        i = int(at * SR) % n
        idx = (np.arange(ln) + i) % n
        clatter[idx] += knock
    x += clatter * 0.6
    x = x + 0.9 * filt(x, lo=170, hi=650)  # (circular, so it still loops)
    return x / np.max(np.abs(x)) * 0.85  # no fade: it loops


# ---------------------------------------------------------------- make them all

def main():
    makers = {
        "explosion_big": (3, lambda r: explosion(r, 3.8, 1.0)),
        "explosion_small": (3, small_explosion),
        "cannon": (2, cannon),
        "fusion": (2, lambda r: fusion(r, True)),
        "fusion_small": (2, lambda r: fusion(r, False)),
        "laser": (4, laser),
        "stubber": (2, lambda r: burst(r, 6, 0.09, 1.0)),
        "carbine": (3, lambda r: burst(r, 4, 0.08, 1.35, explosive=True)),
        "rotor": (2, lambda r: burst(r, 5, 0.1, 2.0, spin=True, tail=1.6)),
        "ricochet": (4, ricochet),
        "clang": (2, clang),
        "collapse": (2, collapse),
        "lance": (2, lance),
        "engine": (1, engine),
    }
    for name, (count, fn) in makers.items():
        for i in range(count):
            rng = np.random.default_rng(zlib.crc32(("%s_%d" % (name, i)).encode()))
            save("%s_%d" % (name, i), fn(rng))
            print("made", name, i)


if __name__ == "__main__":
    main()
