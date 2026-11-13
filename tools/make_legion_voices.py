#!/usr/bin/env python3
"""Makes the Legion's voices into sounds/legion_*.wav.

Spoken lines: English with a Russian accent, said by Kokoro (kokoro-onnx, an open neural voice
far more natural than Piper, which sounded robotic): the English is turned into phonemes and the
sounds a Russian speaker would swap for his own are swapped (w -> v, th -> s / z, h -> kh, a rolled
r, the short i and u), then two men say each line: George (British) and Onyx (deep). The battle
cry "Urrah!" is given as Russian phonemes.

Then each line is given emotion and the Legion's kit: shouted lines are faster, higher and
driven harder; frightened ones shake; all come through the conscript's rebreather mask
(muffled, a nasal resonance) and a cheap field radio (narrow band, a little grit, a squelch
click), with the hiss of the rebreather drawing breath after.

Pain and death sounds are not words: a synthesised human voice (glottal pulses with jitter
and breath, shaped by vowel formant resonators) yelps, grunts or screams with a pitch that
jumps and breaks, through the mask, and a death ends with the body and its kit hitting the
ground.

Needs: pip install kokoro-onnx numpy scipy (and piper-tts, imported but no longer used for
speech), and in PIPER_VOICES/kokoro (default /tmp/claude-0/voices/kokoro) kokoro-v1.0.onnx and
voices-v1.0.bin from https://github.com/thewh1teagle/kokoro-onnx/releases (model-files-v1.0).
"""
import os
import wave
import zlib

import numpy as np
from piper import PiperVoice
from piper.config import SynthesisConfig
from scipy.signal import butter, lfilter, sosfilt

SR = 32000
OUT = os.path.join(os.path.dirname(__file__), "..", "sounds")
VOICES = os.environ.get("PIPER_VOICES", "/tmp/claude-0/voices")

# kind: [(text, mood)]   mood: calm / shout / fear. Text in Cyrillic is said as Russian.
LINES = {
    "legion_move": [("Onwards, comrades!", "shout"), ("Get moving, you dogs!", "shout"), ("We move together.", "calm"), ("Advance!", "shout")],
    "legion_attack": [("Let them have it!", "shout"), ("Fire!", "shout"), ("Safety off, boys!", "shout"), ("Not one step backwards!", "shout"), ("Ура!", "shout")],
    "legion_pinned": [("We are pinned down!", "fear"), ("Heads down! Heads down!", "fear"), ("They are everywhere!", "fear")],
    "legion_rout": [("Fall back! Fall back!", "fear"), ("Get back! Get back!", "fear"), ("We cannot hold!", "fear")],
}
# English sounds a Russian speaker swaps for his own (the accent)
SWAP = {"w": "v", "θ": "s", "ð": "z", "ɪ": "i", "ʊ": "u", "ɹ": "r", "h": "x", "ŋ": "n",
        "ɜ": "e", "ɒ": "o", "ɔ": "o"}  # (the vowels of "advance", "have", "comrades" kept: shouted, they got lost)


# ---------------------------------------------------------------- small tools

def bp(x, lo, hi, order=2):
    sos = butter(order, [lo, hi], btype="band", fs=SR, output="sos")
    return sosfilt(sos, x)


def lp(x, hi, order=2):
    return sosfilt(butter(order, hi, btype="low", fs=SR, output="sos"), x)


def hp(x, lo, order=2):
    return sosfilt(butter(order, lo, btype="high", fs=SR, output="sos"), x)


def resonator(x, f, bw):
    """A two-pole resonance at f Hz (bandwidth bw): one formant of the voice."""
    r = np.exp(-np.pi * bw / SR)
    c = 2 * r * np.cos(2 * np.pi * f / SR)
    return lfilter([1 - r], [1, -c, r * r], x)


def resample(x, sr_in, factor=1.0):
    """To SR, and up in pitch (and shorter) by factor."""
    n = int(len(x) * SR / sr_in / factor)
    return np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x)


def norm(x, peak=0.9):
    return x / (np.max(np.abs(x)) + 1e-9) * peak


def save(name, x):
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())


# ---------------------------------------------------------------- speech

def say(en, ru_voice, text, speed):
    cyr = any("Ѐ" <= ch <= "ӿ" for ch in text)
    # English is said with Russian sounds by the English voice (a Russian voice reading English
    # was too hard to follow: a speech recogniser caught under half the words); Russian text by
    # the Russian voice
    voice = ru_voice if cyr else en
    out = []
    for sent in voice.phonemize(text):
        ph = sent if cyr else [SWAP.get(p, p) for p in sent]
        ph = [p for p in ph if p in voice.config.phoneme_id_map]
        ids = voice.phonemes_to_ids(ph)
        out.append(np.asarray(voice.phoneme_ids_to_audio(ids, SynthesisConfig(length_scale=speed)), dtype=np.float64))
    return np.concatenate(out), voice.config.sample_rate


def mask_and_radio(x, rng, breath=True, drive=1.8, light=False):
    """Through the rebreather mask and a field radio, with the squelch and a breath after
    (light: a gentler mask and a wider radio, for speech)."""
    x = x + (0.18 if light else 0.35) * resonator(x, rng.uniform(950, 1150), 160)  # the mask's nasal, boxed-in ring
    x = lp(x, 4200 if light else 3300, 3)
    x = bp(x, 200 if light else 260, 4500 if light else 3500)
    x = np.tanh(norm(x) * drive) / np.tanh(drive)  # a cheap radio pushed hard
    x += rng.standard_normal(len(x)) * (0.006 if light else 0.012)  # the hiss of the set
    pad = int(0.05 * SR)
    tail = int(0.38 * SR) if breath else int(0.05 * SR)
    out = np.zeros(pad + len(x) + tail)
    out[pad:pad + len(x)] = x
    for at in (int(pad * 0.3), pad + len(x)):  # squelch clicks as the radio opens and closes
        cl = int(0.01 * SR)
        out[at:at + cl] += bp(rng.standard_normal(cl), 1800, 6000) * np.exp(-np.arange(cl) / (cl / 5)) * 0.3
    if breath:  # the rebreather valve drawing breath: a filtered rasp swelling and dying
        n = int(0.3 * SR)
        t = np.linspace(0, 1, n)
        b = bp(rng.standard_normal(n), 1200, 3800) * np.sin(np.pi * t) ** 1.5 * 0.12
        at = pad + len(x) + int(0.04 * SR)
        out[at:at + n] += b[: len(out) - at]
    f = int(0.02 * SR)
    out[-f:] *= np.linspace(1, 0, f)
    return norm(out)


def moods(x, sr, mood, rng):
    """Kept light: pitch shifting and hard clipping are what made the first voices robotic.
    Shouts and fear come mostly from how Kokoro says them (faster, the punctuation)."""
    x = resample(x, sr, 1.0)
    if mood == "shout":
        return np.tanh(norm(x) * 1.5) / np.tanh(1.5), 1.5
    if mood == "fear":
        t = np.arange(len(x)) / SR
        x = x * (1 + 0.1 * np.sin(2 * np.pi * rng.uniform(6, 8) * t))  # a slight shake
        return x, 1.3
    return x, 1.2


# ---------------------------------------------------------------- pain

VOWELS = {  # formants (Hz) of the vowels a hurt man makes
    "a": [800, 1250, 2600], "e": [550, 1800, 2600], "u": [380, 950, 2400], "uh": [620, 1200, 2550], "i": [320, 2200, 2900],
}


def voice_source(f0, rng, breath):
    """Glottal pulses following the pitch track f0 (Hz per sample), with jitter, shimmer and breath."""
    n = len(f0)
    f0 = f0 * (1 + 0.012 * rng.standard_normal(n))  # jitter
    phase = np.cumsum(f0) / SR
    frac = phase % 1.0
    # a Rosenberg-like pulse: a quick open, a sharper close, then shut
    open_q = 0.6
    pulse = np.where(frac < open_q * 0.7, 0.5 - 0.5 * np.cos(np.pi * frac / (open_q * 0.7)),
                     np.where(frac < open_q, np.cos(0.5 * np.pi * (frac - open_q * 0.7) / (open_q * 0.3)), 0.0))
    src = np.diff(pulse, prepend=0.0)  # the flow's derivative excites the vocal tract
    shimmer = 1 + 0.08 * lp(rng.standard_normal(n), 40)
    src *= shimmer
    asp = hp(rng.standard_normal(n), 900) * breath * 0.08 * (0.5 + 0.5 * (frac < open_q))
    return src + asp


def vocal(f0, vowel_a, vowel_b, rng, breath=0.5):
    n = len(f0)
    src = voice_source(f0, rng, breath)
    k = np.linspace(0, 1, n)
    out = np.zeros(n)
    for i, (fa, fb) in enumerate(zip(VOWELS[vowel_a], VOWELS[vowel_b])):
        # the vowel glides: filter in short blocks with the formant moving
        bw = [90, 110, 160][i]
        amp = [1.0, 0.55, 0.25][i]
        blk = 256
        y = np.zeros(n)
        for s in range(0, n, blk):
            f = fa + (fb - fa) * k[s]
            seg = src[max(0, s - 64): s + blk]
            r = resonator(seg, f, bw)
            y[s: s + blk] = r[-len(src[s: s + blk]):]
        out += y * amp
    return out


def contour(points, dur):
    """A pitch track through (time fraction, Hz) points."""
    n = int(dur * SR)
    t = np.linspace(0, 1, n)
    xs, ys = zip(*points)
    return np.interp(t, xs, ys)


def env(n, attack, release_from):
    t = np.linspace(0, 1, n)
    e = np.minimum(1, t / max(attack, 1e-3))
    return e * np.where(t > release_from, np.exp(-(t - release_from) / 0.12), 1.0)


def hurt(i, rng):
    """A man hit: a yelp, a grunt, a gasp or a cry, each different."""
    kinds = [
        # (pitch points, length s, vowel from, vowel to, breath, strain)
        ([(0, 240), (0.12, 430), (0.5, 330), (1, 190)], 0.42, "a", "e", 0.5, 0.7),   # "AH!" a yelp
        ([(0, 160), (0.3, 175), (1, 105)], 0.26, "uh", "uh", 0.3, 0.4),             # "uhh" winded
        ([(0, 300), (0.08, 470), (0.35, 390), (1, 230)], 0.55, "a", "a", 0.6, 0.9),  # "AAH!" sharp
        ([(0, 130), (0.5, 150), (1, 95)], 0.3, "uh", "u", 0.25, 0.5),                # "ngh" teeth gritted
        ([(0, 260), (0.2, 380), (0.6, 300), (1, 170)], 0.65, "e", "a", 0.7, 0.8),    # "EH-AAH" a cry
        ([(0, 210), (0.1, 330), (1, 150)], 0.35, "a", "uh", 0.4, 0.6),               # "agh"
        ([(0, 340), (0.15, 520), (0.4, 420), (1, 260)], 0.5, "i", "a", 0.6, 0.95),   # high-pitched shriek
        ([(0, 150), (0.4, 190), (1, 120)], 0.38, "uh", "a", 0.45, 0.5),              # "oof"
    ]
    pts, dur, va, vb, breath, strain = kinds[i % len(kinds)]
    f0 = contour(pts, dur * rng.uniform(0.9, 1.1))
    if strain > 0.6:  # the voice cracking: a wobble and a moment where it breaks upward
        t = np.arange(len(f0)) / SR
        f0 *= 1 + 0.05 * np.sin(2 * np.pi * rng.uniform(9, 13) * t)
        b = int(len(f0) * rng.uniform(0.25, 0.45))
        f0[b: b + int(0.04 * SR)] *= 1.25
    x = vocal(f0, va, vb, rng, breath)
    x *= env(len(x), 0.03, 0.55)
    # a sharp intake of breath after (a gasp through the mask)
    gn = int(0.22 * SR)
    g = bp(rng.standard_normal(gn), 900, 3200) * np.sin(np.linspace(0, np.pi, gn)) ** 2 * 0.06
    gap = int(0.06 * SR)
    out = np.concatenate([norm(x) * (0.9 + strain * 0.1), np.zeros(gap), g * (0.0 if i % 3 == 1 else 1.0)])
    return out


def death(i, rng):
    """A death cry: a scream that breaks and fails, or a choked groan; then he and his kit hit the ground."""
    kinds = [
        ([(0, 260), (0.1, 480), (0.4, 420), (0.75, 300), (1, 160)], 1.0, "a", "uh", 0.7),
        ([(0, 200), (0.15, 300), (0.6, 220), (1, 110)], 0.8, "uh", "a", 0.6),
        ([(0, 320), (0.07, 540), (0.3, 460), (0.7, 280), (1, 140)], 1.15, "a", "a", 0.8),
        ([(0, 150), (0.3, 180), (1, 85)], 0.6, "uh", "u", 0.5),  # a groan, fading
        ([(0, 280), (0.12, 450), (0.5, 380), (1, 170)], 0.9, "e", "uh", 0.75),
        ([(0, 230), (0.1, 360), (0.45, 330), (1, 120)], 0.85, "a", "u", 0.65),
    ]
    pts, dur, va, vb, breath = kinds[i % len(kinds)]
    f0 = contour(pts, dur)
    t = np.arange(len(f0)) / SR
    f0 *= 1 + 0.06 * np.sin(2 * np.pi * rng.uniform(5, 8) * t) * np.linspace(0.3, 1.0, len(f0))  # a failing wobble
    # vocal fry as the breath gives out: the pitch drops and the pulses go ragged
    fry = t > dur * 0.8
    f0[fry] *= np.linspace(1, 0.55, fry.sum())
    x = vocal(f0, va, vb, rng, breath)
    x *= env(len(x), 0.03, 0.62)
    x = norm(x)
    # the body falling: a soft thump, the clatter of his rifle and kit
    tn = int(0.6 * SR)
    tt = np.arange(tn) / SR
    fall = np.sin(2 * np.pi * (75 - 30 * tt / 0.6) * tt) * np.exp(-tt / 0.07) * 0.6
    fall += lp(rng.standard_normal(tn), 900) * np.exp(-tt / 0.05) * 0.35
    for _ in range(3):  # the rifle and kit rattling down
        c = int(rng.uniform(0.04, 0.3) * SR)
        cl = int(0.03 * SR)
        fall[c: c + cl] += bp(rng.standard_normal(cl), 1500, 4500)[: tn - c] * np.exp(-np.arange(cl) / (cl / 6))[: tn - c] * rng.uniform(0.1, 0.25)
    out = np.zeros(len(x) + tn)
    out[: len(x)] = x
    at = int(len(x) * 0.85)
    out[at: at + tn] += fall[: len(out) - at]
    return out


# Kokoro (kokoro-onnx): far more natural than Piper. Two men: George (British) and Onyx (deep).
KOKORO = os.path.join(VOICES, "kokoro")
MEN = [("bm_george", "en-gb"), ("am_onyx", "en-us")]


def kokoro_say(k, text, man, speed):
    voice, lang = MEN[man]
    if any(0x400 <= ord(ch) <= 0x4FF for ch in text):
        ph = "ʊrˈɑː!"  # "Ura!" (a Russian cheer), said the Russian way
    else:
        ph = "".join(SWAP.get(c, c) for c in k.tokenizer.phonemize(text, lang))
    a, sr = k.create(ph, voice=voice, speed=speed, lang=lang, is_phonemes=True)
    return np.asarray(a, dtype=np.float64), sr


def main():
    from kokoro_onnx import Kokoro
    k = Kokoro(os.path.join(KOKORO, "kokoro-v1.0.onnx"), os.path.join(KOKORO, "voices-v1.0.bin"))
    for kind, lines in LINES.items():
        i = 0
        for text, mood in lines:
            for take in range(2):  # two men saying each line
                rng = np.random.default_rng(zlib.crc32(("%s%d" % (text, take)).encode()))
                speed = {"calm": 1.0, "shout": 1.12, "fear": 1.18}[mood]
                x, sr = kokoro_say(k, text, take, speed)
                x, drive = moods(x, sr, mood, rng)
                save("%s_%d" % (kind, i), mask_and_radio(x, rng, breath=mood != "shout", drive=drive, light=True))
                print("made", kind, i, text, mood)
                i += 1
    for i in range(8):
        rng = np.random.default_rng(zlib.crc32(("hurt%d" % i).encode()))
        save("legion_hurt_%d" % i, mask_and_radio(hurt(i, rng), rng, breath=False, drive=1.6))
        print("made hurt", i)
    for i in range(6):
        rng = np.random.default_rng(zlib.crc32(("death%d" % i).encode()))
        save("legion_death_%d" % i, mask_and_radio(death(i, rng), rng, breath=False, drive=1.5))
        print("made death", i)


if __name__ == "__main__":
    main()
