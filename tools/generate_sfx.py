"""Собственные короткие звуки физики и победы; только стандартная библиотека Python."""

from array import array
from math import exp, pi, sin, sqrt
from pathlib import Path
from random import Random
import sys
import wave

RATE = 24000
OUTPUT = Path(__file__).resolve().parents[1] / "assets" / "audio"


def save(name, samples):
    peak = max(abs(value) for value in samples) or 1.0
    samples = [value * 0.75 / peak for value in samples]
    samples[0] = samples[-1] = 0.0
    pcm = array("h", (round(value * 32767) for value in samples))
    if sys.byteorder != "little":
        pcm.byteswap()
    with wave.open(str(OUTPUT / f"sfx_{name}.wav"), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(pcm.tobytes())
    rms = sqrt(sum(value * value for value in samples) / len(samples))
    print(f"sfx_{name}.wav: {len(samples) / RATE:.2f}s, PCM16 mono {RATE}Hz, RMS={rms:.3f}")


def mechanical(name, duration, seed):
    rng = Random(seed)
    samples = []
    low_noise = 0.0
    phase = 0.0
    for index in range(int(RATE * duration)):
        time = index / RATE
        progress = time / duration
        noise = rng.uniform(-1.0, 1.0)
        low_noise = 0.86 * low_noise + 0.14 * noise
        if name == "tension":
            # Неровный короткий скрип резины, без непрерывного тона при удержании.
            phase += 2.0 * pi * (95.0 + 70.0 * progress) / RATE
            sound = (low_noise * 1.8 + sin(phase) * 0.10) * (0.5 + 0.5 * sin(time * 180.0) ** 2)
            envelope = sin(pi * progress) ** 1.8
        elif name == "release":
            phase += 2.0 * pi * (95.0 + 440.0 * exp(-time * 38.0)) / RATE
            sound = sin(phase) * 0.8 + low_noise * exp(-time * 60.0)
            envelope = min(1.0, time * 500.0) * exp(-time * 27.0) * (1.0 - progress)
        else:
            # Небольшая задержка атаки отделяет свист воздуха от щелчка выпуска.
            envelope = sin(pi * progress) ** 2.0
            sound = low_noise * 2.0 + noise * 0.05
        samples.append(sound * envelope)
    save(name, samples)


def material(name, duration, modes, seed):
    rng = Random(seed)
    impacts = [(0.0, 1.0)]
    for index in range(5 if name == "glass" else 3):
        impacts.append((rng.uniform(0.015, duration * 0.6), 0.36 / (index + 1)))
    samples = []
    low_noise = 0.0
    for index in range(int(RATE * duration)):
        time = index / RATE
        noise = rng.uniform(-1.0, 1.0)
        low_noise = 0.7 * low_noise + 0.3 * noise
        value = 0.0
        for start, gain in impacts:
            local = time - start
            if local < 0.0:
                continue
            attack = min(1.0, local * 1500.0)
            tone = sum(sin(2.0 * pi * hz * local) * weight * exp(-local * decay) for hz, weight, decay in modes)
            grit = noise if name == "glass" else low_noise
            value += gain * attack * (tone + grit * exp(-local * 75.0) * 0.7)
        samples.append(value * min(1.0, (duration - time) * 90.0))
    save(name, samples)


def victory():
    notes = [(0.0, 523.25), (0.17, 659.25), (0.34, 783.99), (0.56, 1046.5)]
    duration = 1.22
    samples = []
    for index in range(int(RATE * duration)):
        time = index / RATE
        value = 0.0
        for start, pitch in notes:
            local = time - start
            if local < 0.0:
                continue
            envelope = min(1.0, local * 100.0) * exp(-local * 7.0)
            value += envelope * (sin(2.0 * pi * pitch * local) + 0.22 * sin(2.0 * pi * pitch * 2.0 * local))
        samples.append(value * min(1.0, (duration - time) * 20.0))
    save("victory", samples)


if __name__ == "__main__":
    OUTPUT.mkdir(parents=True, exist_ok=True)
    mechanical("tension", 0.19, 510)
    mechanical("release", 0.16, 511)
    mechanical("flight", 0.34, 512)
    material("wood", 0.30, [(170, 0.7, 28), (420, 0.4, 37), (1130, 0.16, 64)], 520)
    material("glass", 0.52, [(1920, 0.32, 15), (2787, 0.30, 19), (4170, 0.23, 24)], 521)
    material("stone", 0.33, [(84, 0.9, 20), (183, 0.35, 28), (630, 0.15, 58)], 522)
    material("metal", 0.65, [(390, 0.6, 9), (877, 0.4, 11), (1403, 0.22, 16)], 523)
    victory()
