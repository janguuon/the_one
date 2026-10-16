"""Create THE ONE's original, deterministic PCM soundtrack and combat cues.

No samples, pretrained model, network download, or third-party library is used.
Run from the repository with Python 3: python tools/generate_audio.py
"""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
import random
import struct
import wave

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "audio"
RATE = 22050
TAU = math.tau
MANIFEST = {"schema": 1, "sample_rate": RATE, "format": "PCM16 stereo", "generator": "tools/generate_audio.py", "assets": {}}


def tone(t, hz):
    return math.sin(TAU * hz * t)


def write(name, duration, source, *, music=False):
    count = round(duration * RATE)
    samples = [source(i / RATE, i) for i in range(count)]
    # Common -8 dBFS per-asset ceiling leaves headroom for the capped mixer.
    peak = max(max(abs(x[0]), abs(x[1])) for x in samples) or 1
    gain = min(1.0, 0.398 / peak)
    raw = b"".join(struct.pack("<hh", round(l * gain * 32767), round(r * gain * 32767)) for l, r in samples)
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / (name + ".wav")
    with wave.open(str(path), "wb") as f:
        f.setnchannels(2)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(raw)
    MANIFEST["assets"][name] = {"file": name + ".wav", "frames": count, "seconds": count / RATE, "peak": peak * gain, "loop": music, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def sfx(name, duration, frequency, *, noise=0.2, decay=10, sweep=0, pan=0, metallic=0, double=False):
    rng = random.Random(name)
    def synth(t, i):
        attack = min(1, t / 0.004)
        end = min(1, (duration - t) / 0.015)
        envelope = attack * end * math.exp(-t * decay)
        pitch = frequency + sweep * t
        signal = tone(t, pitch) * 0.45 + tone(t, pitch * 2.73) * metallic + rng.uniform(-1, 1) * noise
        if double and t >= 0.075:
            signal += tone(t - 0.075, frequency * 0.73) * math.exp(-(t - 0.075) * 15) * 0.3
        value = signal * envelope
        return value * (1 - pan * 0.4), value * (1 + pan * 0.4)
    write(name, duration, synth)


def music(phase):
    # 16 seconds = eight bars at 120 BPM. Every oscillation fits the cycle.
    # A cyclic window is never cut mid-note; the exported seam is zero.
    duration = 16
    rng = random.Random(600 + phase)
    crackles = [rng.uniform(-1, 1) for _ in range(round(duration * RATE))]
    def synth(t, i):
        edge = min(1, t / 0.08, (duration - t) / 0.08)
        drone = (tone(t, 55) + tone(t, 82.5) * 0.37 + tone(t, 110) * 0.16) * (0.065 + 0.018 * tone(t, 0.125))
        stone = crackles[i] * (0.014 + 0.009 * tone(t, 0.25))
        left, right = drone + stone, drone - stone * 0.7
        if phase <= 4:
            interval = {1: 4, 2: 4, 3: 1, 4: 2}[phase]
            beat = t % interval
            drum = tone(beat, 44 + 20 * math.exp(-beat * 12)) * math.exp(-beat * 11) * 0.17
            if phase == 3:
                second = (t - 0.22) % interval
                drum += tone(second, 58) * math.exp(-second * 16) * 0.12
            if phase == 4:
                echo = (t - 0.35) % interval
                drum += tone(echo, 73) * math.exp(-echo * 10) * 0.09
            left += drum
            right += drum
        if phase == 2:
            crack = t % 4
            shimmer = crackles[i] * math.exp(-crack * 6) * 0.06
            side = 1 if int(t / 4) % 2 else -1
            left += shimmer * (1 + side * 0.65)
            right += shimmer * (1 - side * 0.65)
        if phase == 5:
            # Sparse breath and one low fifth; the finale deliberately thins.
            breath = math.sin(math.pi * (t % 4) / 4) ** 4 * crackles[i] * 0.05
            left = drone * 0.7 + breath
            right = drone * 0.7 + breath * 0.8
        return left * edge, right * edge
    write("phase_%d" % phase, duration, synth, music=True)


def main():
    for phase in range(1, 6):
        music(phase)
    # Silhouettes have different mass and spectra, preserving five identities.
    for weapon, frequency, noise, decay, metal in [(1, 700, .42, 16, .12), (2, 1150, .24, 23, .08), (3, 1550, .32, 28, .05), (4, 90, .65, 8, .05), (5, 930, .38, 10, .25)]:
        sfx("attack_W%02d" % weapon, .36 if weapon != 4 else .55, frequency, noise=noise, decay=decay, sweep=-frequency * .8, metallic=metal)
        sfx("hit_W%02d" % weapon, .34 if weapon != 4 else .62, frequency * .46, noise=noise + .12, decay=decay * .65, metallic=metal + .08, double=weapon == 5)
    sfx("warning_preview", .22, 1500, noise=.015, decay=13, sweep=450)
    sfx("warning_lock", .18, 2200, noise=.01, decay=16, metallic=.1)
    sfx("warning_execute", .34, 130, noise=.38, decay=11)
    sfx("warning_echo", .38, 590, noise=.08, decay=9, double=True)
    sfx("dodge", .28, 210, noise=.48, decay=17, sweep=-160)
    sfx("hurt", .5, 88, noise=.5, decay=9, metallic=.04)
    sfx("pickup_fire", .48, 523.25, noise=.14, decay=7, sweep=240)
    sfx("pickup_frost", .6, 1318.5, noise=.025, decay=6, metallic=.18)
    sfx("pickup_lightning", .32, 1760, noise=.3, decay=13, sweep=-450)
    sfx("pickup_void", .7, 164.8, noise=.09, decay=4, sweep=-55, metallic=.12)
    sfx("transition", 1.2, 110, noise=.16, decay=2.5, sweep=45, metallic=.12)
    sfx("death", 1.8, 82.4, noise=.08, decay=2.1, sweep=-19)
    sfx("victory", 2.3, 261.6, noise=.01, decay=1.4, metallic=.11)
    sfx("menu_move", .1, 660, noise=.025, decay=30)
    sfx("menu_confirm", .22, 880, noise=.015, decay=16, sweep=220)
    sfx("weapon_swap", .5, 330, noise=.11, decay=8, metallic=.2)
    sfx("oath", .7, 440, noise=.03, decay=5, metallic=.15)
    (OUT / "manifest.json").write_text(json.dumps(MANIFEST, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Generated", len(MANIFEST["assets"]), "original audio assets")


if __name__ == "__main__":
    main()
