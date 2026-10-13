"""Создать три собственных коротких голоса собак без записей и внешних сэмплов.

Только стандартная библиотека Python; запуск из любой папки. Готовые WAV
хранятся в проекте, поэтому для игры Python не требуется.
"""

from array import array
from math import cos, exp, pi, sin, sqrt
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


def make_bark(name, pitch, throat, duration, seed):
    rng = Random(seed)
    samples = []
    envelopes = []
    phase = 0.0
    jitter = 0.0
    low_noise = 0.0
    softened = 0.0
    filtered_voice = 0.0
    filter_blend = 1.0 - exp(-2.0 * pi * 1900.0 / RATE)
    noise_state = [[0.0, 0.0], [0.0, 0.0]]
    for index in range(int(RATE * duration)):
        seconds = index / RATE
        progress = seconds / duration
        jitter = jitter * 0.985 + rng.uniform(-1.0, 1.0) * 0.015
        frequency = pitch * curve([(0, 0.92), (0.16, 1.1), (0.4, 0.96), (1, 0.62)], progress)
        frequency *= 1.0 + jitter * 0.12 + 0.012 * sin(2.0 * pi * 8.0 * seconds)
        phase += 2.0 * pi * frequency / RATE
        formants = (
            throat * curve([(0, 380), (0.18, 640), (0.35, 560), (1, 300)], progress),
            throat * curve([(0, 1050), (0.2, 1350), (0.45, 1120), (1, 650)], progress),
        )
        voice = 0.0
        for harmonic in range(1, 33):
            hz = harmonic * frequency
            if hz >= RATE * 0.45:
                break
            resonance = (
                0.12
                + 1.8 * exp(-0.5 * ((hz - formants[0]) / 240.0) ** 2)
                + 0.8 * exp(-0.5 * ((hz - formants[1]) / 370.0) ** 2)
            )
            voice += (sin(harmonic * phase + harmonic * 0.19) * resonance
                      * exp(-(hz / 2400.0) ** 2) / harmonic ** 1.55)
        # Тихий грудной призвук сохраняет «гав», не превращая его в рычание.
        voice += 0.14 * sin(phase * 0.5)
        noise = rng.uniform(-1.0, 1.0)
        low_noise = 0.55 * low_noise + 0.45 * noise
        breath = 0.0
        for band, (center, width) in enumerate(zip(formants, (500.0, 800.0))):
            radius = exp(-pi * width / RATE)
            previous, older = noise_state[band]
            filtered = (
                (1.0 - radius) * noise
                + 2.0 * radius * cos(2.0 * pi * center / RATE) * previous
                - radius * radius * older
            )
            noise_state[band] = [filtered, previous]
            breath += filtered
        breath_mix = curve([(0, 0.3), (0.18, 0.12), (0.65, 0.2), (1, 0.45)], progress)
        sound = voice + breath * breath_mix + low_noise * 0.035
        filtered_voice += filter_blend * (sound - filtered_voice)
        softened += filter_blend * (filtered_voice - softened)
        # Плавный вдох, короткая гласная и выдох вместо резкого щелчка.
        envelope = curve([(0, 0), (0.12, 1), (0.3, 0.88), (0.65, 0.35), (1, 0)], progress)
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
    path = OUTPUT / f"bark_{name}.wav"
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(pcm.tobytes())
    rms = sqrt(sum(value * value for value in samples) / len(samples))
    print(f"{path.name}: {duration:.2f}s, PCM16 mono {RATE}Hz, peak=0.70, RMS={rms:.3f}")


if __name__ == "__main__":
    OUTPUT.mkdir(parents=True, exist_ok=True)
    make_bark("scout", 205.0, 1.0, 0.34, 110)
    make_bark("armored", 130.0, 0.77, 0.42, 120)
    make_bark("jumper", 295.0, 1.23, 0.23, 130)
