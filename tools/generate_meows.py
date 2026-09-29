"""Create original cartoon meows with a voiced source and moving vowel formants.

Standard library only. Run from any directory; assets are committed, so Python
is not required to run the game. No recordings or external samples are used.
"""

from array import array
from math import cos, exp, pi, sin, sqrt, tanh
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
    phase = 0.0
    previous_noise = 0.0
    for index in range(int(RATE * duration)):
        seconds = index / RATE
        progress = seconds / duration
        frequency = pitch * curve(
            [(0, 470), (0.16, 710), (0.36, 735), (0.72, 510), (1, 340)], progress
        )
        frequency *= 1.0 + 0.012 * sin(2.0 * pi * 19.0 * seconds)
        phase += 2.0 * pi * frequency / RATE
        formant_one = curve([(0, 360), (0.18, 650), (0.46, 1000), (0.8, 610), (1, 420)], progress)
        formant_two = curve([(0, 1900), (0.2, 2300), (0.50, 1500), (1, 900)], progress)
        voice = 0.0
        for harmonic in range(1, 15):
            hz = harmonic * frequency
            resonance = (
                0.12
                + 1.8 * exp(-0.5 * ((hz - formant_one) / 290.0) ** 2)
                + 0.85 * exp(-0.5 * ((hz - formant_two) / 450.0) ** 2)
            )
            voice += sin(harmonic * phase + 0.13 * harmonic) * resonance / harmonic ** 1.3
        # Soft nasal onset and a little breath avoid a pure electronic whistle.
        nasal = sin(phase * 0.5) * 0.12 * exp(-progress * 8.0)
        noise = rng.uniform(-1.0, 1.0)
        breath = (noise - previous_noise) * 0.025
        previous_noise = noise
        envelope = min(1.0, seconds / 0.024) * min(1.0, (duration - seconds) / 0.1)
        envelope *= sin(pi * progress) ** 0.38
        samples.append(tanh((voice + nasal + breath) * 0.9) * envelope)
    peak = max(abs(value) for value in samples)
    samples = [value * 0.82 / peak for value in samples]
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
    print(f"{path.name}: {duration:.2f}s, PCM16 mono {RATE}Hz, peak=0.82, RMS={rms:.3f}")


if __name__ == "__main__":
    OUTPUT.mkdir(parents=True, exist_ok=True)
    make_meow("classic", 1.0, 0.46, 10)
    make_meow("bomb", 0.86, 0.50, 20)
    make_meow("zigzag", 1.13, 0.43, 30)
