"""Регрессия мягкости исходных WAV; слуховую оценку эти проверки не заменяют."""

from array import array
from math import sqrt
from pathlib import Path
import sys
import unittest
import wave


AUDIO = Path(__file__).resolve().parents[1] / "assets" / "audio"
NAMES = ("meow_classic", "meow_bomb", "meow_zigzag",
         "bark_scout", "bark_armored", "bark_jumper")


class AnimalVoiceAssetsTest(unittest.TestCase):
    def test_soft_one_shot_voices(self):
        for name in NAMES:
            with self.subTest(voice=name), wave.open(str(AUDIO / f"{name}.wav"), "rb") as stream:
                self.assertEqual(stream.getnchannels(), 1)
                self.assertEqual(stream.getsampwidth(), 2)
                self.assertEqual(stream.getframerate(), 24000)
                duration = stream.getnframes() / stream.getframerate()
                self.assertGreaterEqual(duration, 0.18)
                self.assertLessEqual(duration, 0.6)
                pcm = array("h", stream.readframes(stream.getnframes()))
                if sys.byteorder != "little":
                    pcm.byteswap()
                samples = [value / 32768.0 for value in pcm]
                rms = sqrt(sum(value * value for value in samples) / len(samples))
                peak = max(abs(value) for value in samples)
                self.assertGreater(peak, 0.5, "Голос должен оставаться слышимым")
                self.assertLessEqual(peak, 0.71, "Запас громкости для одновременных голосов")
                self.assertGreater(rms, 0.08)
                self.assertLess(rms, 0.4, "Без прежнего плотного насыщения")
                self.assertLess(abs(sum(samples) / len(samples)), 0.002, "Нет смещения постоянного тока")
                self.assertEqual(pcm[0], 0)
                self.assertEqual(pcm[-1], 0)
                edge_samples = samples[:120] + samples[-120:]
                self.assertLess(max(abs(value) for value in edge_samples), 0.08, "Плавные первые/последние 5 ms")
                differences = [second - first for first, second in zip(samples, samples[1:])]
                brightness = sqrt(sum(value * value for value in differences) / len(differences)) / rms
                self.assertLess(brightness, 0.22, "Не возвращать резкие высокочастотные обертоны")

    def test_variants_keep_distinct_voices(self):
        self.assertEqual(len({(AUDIO / f"{name}.wav").read_bytes() for name in NAMES}), len(NAMES))


if __name__ == "__main__":
    unittest.main()
