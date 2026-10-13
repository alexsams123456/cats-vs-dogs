"""Создать мягкое мяуканье с голосовым источником и переходом гласных.

Только стандартная библиотека Python; запуск из любой папки. Готовые WAV
хранятся в проекте, поэтому для игры Python не требуется. Без внешних сэмплов.
"""

from array import array
from math import exp, pi, sin, sqrt
from pathlib import Path
from random import Random
import sys
import wave

RATE = 24000
OUTPUT = Path(__file__).resolve().parents[1] / "assets" / "audio"


def curve(points, position):
    for (left, first), (right, second) in zip(points, points[1:]):
        if position <= right:
            blend = max(0.0, (position - left) / (right - left))
            blend = blend * blend * (3.0 - 2.0 * blend)
            return first + (second - first) * blend
    return points[-1][1]


def make_meow(name, pitch, duration, seed):
    rng = Random(seed)
    samples = []
    envelopes = []
    phase = 0.0
    jitter = 0.0
    breath = 0.0
    filtered = 0.0
    softened = 0.0
    filter_blend = 1.0 - exp(-2.0 * pi * 2300.0 / RATE)
    for index in range(int(RATE * duration)):
        seconds = index / RATE
        progress = seconds / duration
        frequency = pitch * curve(
            [(0, 420), (0.2, 590), (0.38, 560), (0.74, 390), (1, 260)], progress
        )
        jitter = 0.995 * jitter + 0.005 * rng.uniform(-1.0, 1.0)
        frequency *= 1.0 + 0.006 * sin(2.0 * pi * 6.0 * seconds) + 0.04 * jitter
        phase += 2.0 * pi * frequency / RATE
        formant_one = curve([(0, 340), (0.2, 580), (0.46, 820), (0.8, 560), (1, 380)], progress)
        formant_two = curve([(0, 1700), (0.2, 1850), (0.50, 1350), (1, 850)], progress)
        voice = 0.0
        for harmonic in range(1, 15):
            hz = harmonic * frequency
            resonance = (
                0.1
                + 1.5 * exp(-0.5 * ((hz - formant_one) / 270.0) ** 2)
                + 0.55 * exp(-0.5 * ((hz - formant_two) / 400.0) ** 2)
            )
            voice += (sin(harmonic * phase + 0.13 * harmonic) * resonance
                      * exp(-(hz / 2900.0) ** 2) / harmonic ** 1.65)
        # Немного дыхания и носовой призвук; без насыщения, создающего резкие обертоны.
        nasal = sin(phase * 0.5) * 0.07 * exp(-progress * 8.0)
        breath = 0.82 * breath + 0.18 * rng.uniform(-1.0, 1.0)
        filtered += filter_blend * (voice + nasal + 0.04 * breath - filtered)
        softened += filter_blend * (filtered - softened)
        attack = sin(0.5 * pi * min(1.0, seconds / 0.045)) ** 2
        release = sin(0.5 * pi * min(1.0, (duration - seconds) / 0.12)) ** 2
        envelope = attack * release * sin(pi * progress) ** 0.65
        samples.append(softened * envelope)
        envelopes.append(envelope)
    offset = sum(samples) / sum(envelopes)
    samples = [value - offset * envelope for value, envelope in zip(samples, envelopes)]
    peak = max(abs(value) for value in samples)
    samples = [value * 0.7 / peak for value in samples]
    samples[0] = samples[-1] = 0.0
    pcm = array("h", (round(value * 32767) for value in samples))
    if sys.byteorder != "little":
        pcm.byteswap()
    path = OUTPUT / f"meow_{name}.wav"
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(pcm.tobytes())
    rms = sqrt(sum(value * value for value in samples) / len(samples))
    print(f"{path.name}: {duration:.2f}s, PCM16 mono {RATE}Hz, peak=0.70, RMS={rms:.3f}")


if __name__ == "__main__":
    OUTPUT.mkdir(parents=True, exist_ok=True)
    make_meow("classic", 1.0, 0.46, 10)
    make_meow("bomb", 0.86, 0.50, 20)
    make_meow("zigzag", 1.13, 0.43, 30)
