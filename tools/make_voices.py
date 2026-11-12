#!/usr/bin/env python3
"""Makes the Sworn's voice lines into sounds/voice_*.wav.

A neural text-to-speech voice (Piper, British male "alan") reads each line, then it
is turned into a deep, armoured, robotic voice: pitched down, a light metallic ring,
the boxy resonance of a voice inside a helmet, the grit of a vox grille, and the
click of the vox opening and closing.

Needs:  pip install piper-tts numpy
and the voice files en_GB-alan-medium.onnx(.json) from
https://huggingface.co/rhasspy/piper-voices/tree/main/en/en_GB/alan/medium
in the folder given by PIPER_VOICES (default /tmp/claude-0/voices).
"""
import io
import os
import wave
import zlib

import numpy as np
from piper import PiperVoice
from piper.config import SynthesisConfig

SR = 32000
OUT = os.path.join(os.path.dirname(__file__), "..", "sounds")
VOICES = os.environ.get("PIPER_VOICES", "/tmp/claude-0/voices")

LINES = {
    "sworn_move": ["Confirmed.", "On our way.", "Your will."],
    "sworn_attack": ["On my mark.", "Fire!", "Unleash hell!"],
    "sworn_death": ["Ugh!", "Aargh!", "Gah!"],
}


def filt(x, lo=None, hi=None, order=2):
    n = len(x)
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1 / SR)
    g = np.ones_like(f)
    if hi:
        g /= 1 + (f / hi) ** (2 * order)
    if lo:
        g /= 1 + (lo / np.maximum(f, 1e-3)) ** (2 * order)
    return np.fft.irfft(X * g, n)


def speak(voice, text, speed):
    cfg = SynthesisConfig(length_scale=speed)
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        voice.synthesize_wav(text, w, syn_config=cfg)
    buf.seek(0)
    with wave.open(buf) as w:
        sr = w.getframerate()
        x = np.frombuffer(w.readframes(w.getnframes()), np.int16) / 32768.0
    return x, sr


def robot(x, sr, pitch, rng):
    # deepen: play slower (the speech was made faster to keep the timing)
    n_out = int(len(x) / pitch * SR / sr)
    x = np.interp(np.linspace(0, len(x) - 1, n_out), np.arange(len(x)), x)
    t = np.arange(len(x)) / SR
    # a light ring modulation for a metallic, synthetic edge
    ring = x * np.sin(2 * np.pi * rng.uniform(55, 70) * t)
    x = 0.78 * x + 0.32 * ring
    # the helmet: short feeding-back echoes (a boxy, resonant cavity)
    y = np.copy(x)
    for delay_ms, gain in [(3.1, 0.45), (5.3, 0.35), (8.7, 0.25)]:
        d = int(delay_ms / 1000 * SR)
        for k in range(1, 5):
            y[d * k:] += x[: len(x) - d * k] * gain ** k
    # the vox grille: band-limited, a little gritty, chest-weight kept
    y = filt(y, lo=90, hi=4200)
    y = y + 0.6 * filt(y, lo=110, hi=420)
    y = np.tanh(y / (np.max(np.abs(y)) + 1e-9) * 2.2)
    # vox squelch: a click as it opens and closes
    pad = int(0.06 * SR)
    out = np.zeros(len(y) + pad * 2)
    out[pad:pad + len(y)] = y
    for at in (int(pad * 0.4), pad + len(y) + int(pad * 0.2)):
        cl = int(0.012 * SR)
        click = filt(rng.standard_normal(cl), lo=1500, hi=6000) * np.exp(-np.arange(cl) / (cl / 5)) * 0.25
        out[at:at + cl] += click[: len(out) - at]
    f = int(0.02 * SR)
    out[-f:] *= np.linspace(1, 0, f)
    return out / (np.max(np.abs(out)) + 1e-9) * 0.9


def save(name, x):
    os.makedirs(OUT, exist_ok=True)
    data = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def main():
    voice = PiperVoice.load(os.path.join(VOICES, "en_GB-alan-medium.onnx"))
    for kind, lines in LINES.items():
        i = 0
        for line in lines:
            for take in range(2):  # two takes of each line, a little different
                rng = np.random.default_rng(zlib.crc32(("%s%d" % (line, take)).encode()))
                pitch = [0.78, 0.74][take]  # about 4-5 semitones down
                x, sr = speak(voice, line, speed=pitch * [1.05, 1.15][take])
                save("%s_%d" % (kind, i), robot(x, sr, pitch, rng))
                print("made", kind, i, line)
                i += 1


if __name__ == "__main__":
    main()
