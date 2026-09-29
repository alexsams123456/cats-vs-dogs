"""Собственная спокойная музыкальная петля; только стандартная библиотека Python."""

from array import array
from math import cos, exp, log10, pi, sin, sqrt
from pathlib import Path
import sys
import wave

RATE = 24000
DURATION = 64.0
FRAMES = int(RATE * DURATION)
OUTPUT = Path(__file__).resolve().parents[1] / "assets" / "audio" / "music_meadow.wav"

# Восемь мягких созвучий ре мажора, по восемь секунд; без ударных.
CHORDS = (
    (50, 57, 64, 66),  # D add9
    (43, 55, 59, 66),  # G maj7
    (47, 57, 62, 66),  # B m7
    (45, 57, 59, 64),  # A sus2
    (42, 57, 61, 64),  # D maj9 / F#
    (43, 55, 59, 64),  # G 6
    (40, 55, 59, 62),  # E m7
    (45, 57, 59, 64),  # A sus2
)
MELODY = (
    (2.4, 69), (6.1, 66),
    (11.0, 67), (14.2, 66),
    (18.5, 66), (22.0, 62),
    (27.0, 64),
    (34.3, 66), (38.1, 69),
    (43.0, 71), (46.0, 67),
    (51.0, 66), (54.0, 64),
    (59.0, 64), (62.0, 69),
)


def smooth_rise(progress: float) -> float:
    return 0.5 - 0.5 * cos(pi * min(1.0, max(0.0, progress)))


def add_note(channels: tuple[array, array], start: float, midi: int,
             duration: float, gain: float, pan: float, is_pad: bool) -> None:
    frequency = 440.0 * 2.0 ** ((midi - 69) / 12.0)
    start_frame = round(start * RATE)
    left_gain = gain * sqrt((1.0 - pan) * 0.5)
    right_gain = gain * sqrt((1.0 + pan) * 0.5)
    left, right = channels
    for index in range(round(duration * RATE)):
        time = index / RATE
        phase = 2.0 * pi * frequency * time
        if is_pad:
            envelope = smooth_rise(time / 2.4) * smooth_rise((duration - time) / 3.1)
            breath = 0.94 + 0.06 * sin(2.0 * pi * time / 7.7 + midi)
            tone = (sin(phase) + 0.14 * sin(2.0 * phase + 0.3)
                    + 0.035 * sin(3.0 * phase + 0.6)
                    + 0.16 * sin(phase * 1.0008 + 0.7))
            value = tone * envelope * breath
        else:
            # Мягкая атака и затухающие обертоны, без звона и щелчка молоточка.
            envelope = smooth_rise(time / 0.28) * exp(-time / 1.85)
            envelope *= smooth_rise((duration - time) / 1.8)
            tone = (sin(phase) + 0.12 * sin(2.0 * phase) * exp(-time / 0.9)
                    + 0.025 * sin(3.0 * phase) * exp(-time / 0.4))
            value = tone * envelope
        # Хвосты последнего такта продолжаются в начале той же петли.
        frame = (start_frame + index) % FRAMES
        left[frame] += value * left_gain
        right[frame] += value * right_gain


def add_room(channels: tuple[array, array]) -> tuple[array, array]:
    # Короткие негромкие отражения тоже замыкаются по кругу, включая стык WAV.
    wet = (array("d", channels[0]), array("d", channels[1]))
    reflections = ((0.173, 0.12), (0.317, 0.10), (0.479, 0.08),
                   (0.731, 0.06), (1.093, 0.04))
    for tap, (delay, gain) in enumerate(reflections):
        offset = round(delay * RATE)
        for channel in range(2):
            source = channels[(channel + tap) % 2]
            target = wet[channel]
            for index in range(FRAMES):
                target[index] += source[(index - offset) % FRAMES] * gain
    return wet


def save(channels: tuple[array, array]) -> None:
    # Удаление DC не меняет непрерывность; пик оставляет запас под микшер игры.
    means = tuple(sum(channel) / FRAMES for channel in channels)
    peak = max(abs(value - mean) for channel, mean in zip(channels, means) for value in channel)
    scale = 0.5 / peak
    pcm = array("h")
    energy = 0.0
    for index in range(FRAMES):
        for channel, mean in zip(channels, means):
            value = (channel[index] - mean) * scale
            energy += value * value
            pcm.append(round(value * 32767))
    seam = max(abs(pcm[channel] - pcm[-2 + channel]) for channel in range(2))
    if sys.byteorder != "little":
        pcm.byteswap()
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUTPUT), "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(pcm.tobytes())
    rms = sqrt(energy / (FRAMES * 2))
    print(f"{OUTPUT.name}: {DURATION:.1f}s, PCM16 stereo {RATE}Hz, "
          f"peak=-6.02dBFS, RMS={20.0 * log10(rms):.2f}dBFS, "
          f"loop seam step={seam}/32767")


def main() -> None:
    channels = (array("d", [0.0]) * FRAMES, array("d", [0.0]) * FRAMES)
    for chord_index, chord in enumerate(CHORDS):
        for voice, midi in enumerate(chord):
            # Переходы перекрываются, вступление каждого голоса чуть разнесено.
            start = chord_index * 8.0 - 1.4 + voice * 0.11
            gain = 0.33 if voice == 0 else 0.25
            pan = (-0.08, -0.24, 0.22, 0.10)[voice]
            add_note(channels, start, midi, 11.6, gain, pan, True)
    for note_index, (start, midi) in enumerate(MELODY):
        add_note(channels, start, midi, 6.8, 0.19, (-0.12, 0.12)[note_index % 2], False)
    save(add_room(channels))


if __name__ == "__main__":
    main()
