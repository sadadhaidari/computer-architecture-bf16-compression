import unittest
import numpy as np

try:
    from exponent_codec import pack_row, unpack_row
except ImportError:
    pack_row = unpack_row = None


class CodecTests(unittest.TestCase):
    def test_all_bit_patterns(self):
        self.assertIsNotNone(pack_row, "BF16 codec is not implemented")
        # Sweep the complete 16-bit space across several exponent bases.
        bits = np.arange(65536, dtype=np.uint16)
        for base in [0, 112, 120, 240]:
            for i in range(0, len(bits), 2048):
                chunk = bits[i : i + 2048]
                packed = pack_row(chunk, base)
                self.assertTrue(np.array_equal(unpack_row(packed, len(chunk)), chunk))

    def test_compression_and_raw_fallback(self):
        self.assertIsNotNone(pack_row, "BF16 codec is not implemented")
        common = ((np.arange(2048, dtype=np.uint16) % 15 + 112) << 7) | 37
        packed = pack_row(common, 112)
        self.assertLess(len(packed), common.nbytes * 0.8)
        # Random exponents should trigger raw fallback instead of a larger packed row.
        rng = np.random.default_rng(6005)
        raw = rng.integers(0, 65536, 2048, dtype=np.uint16)
        packed = pack_row(raw, 112)
        self.assertEqual(packed[0], 0)
        self.assertEqual(len(packed), raw.nbytes + 1)
        self.assertTrue(np.array_equal(unpack_row(packed, len(raw)), raw))

    def test_truncated_stream(self):
        self.assertIsNotNone(pack_row, "BF16 codec is not implemented")
        bits = np.full(64, 112 << 7, dtype=np.uint16)
        packed = pack_row(bits, 112)
        with self.assertRaises(ValueError):
            unpack_row(packed[:-1], len(bits))

    def test_bad_base(self):
        packed = bytes([2, 242]) + bytes(48)
        with self.assertRaises(ValueError):
            unpack_row(packed, 32)


if __name__ == "__main__":
    unittest.main()
