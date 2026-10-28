"""Exact BF16 exponent-window codec: unchanged sign/fraction plus exact escapes."""

import numpy as np
from numba import njit


@njit
def _pack(bits, base):
    if len(bits) % 32 or base < 0 or base > 241:
        raise ValueError("Unsupported BF16 row")
    # Leave room for escapes before we know how much the row will shrink.
    out = np.empty(len(bits) * 3 + 2, dtype=np.uint8)
    out[0] = 2
    out[1] = base
    pos = 2
    codes = np.empty(32, dtype=np.uint8)
    esc = np.empty(32, dtype=np.uint8)
    for off in range(0, len(bits), 32):
        nesc = 0
        for j in range(32):
            v = int(bits[off + j])
            e = (v >> 7) & 255
            delta = e - base
            # Store the sign and fraction as one B; keep both fields intact.
            out[pos + j] = (v & 127) | ((v >> 8) & 128)
            if 0 <= delta < 15:
                codes[j] = delta
            else:
                codes[j] = 15
                esc[nesc] = e
                nesc += 1
        # Pair lane j with lane j+16 to match the native decoder and RTL.
        for j in range(16):
            out[pos + 32 + j] = codes[j] | (codes[j + 16] << 4)
        for j in range(nesc):
            out[pos + 48 + j] = esc[j]
        pos += 48 + nesc
    # Use a raw row when packing would take more space.
    if pos >= len(bits) * 2:
        raw = np.empty(len(bits) * 2 + 1, dtype=np.uint8)
        raw[0] = 0
        for j in range(len(bits)):
            raw[1 + 2 * j] = bits[j] & 255
            raw[2 + 2 * j] = bits[j] >> 8
        return raw
    return out[:pos]


def pack_row(bits, base):
    return _pack(np.asarray(bits, dtype=np.uint16), base).tobytes()


def unpack_row(data, count):
    if not data or count % 32:
        raise ValueError("Unsupported BF16 row")
    if data[0] == 0:
        if len(data) != count * 2 + 1:
            raise ValueError("Raw row size mismatch")
        return np.frombuffer(data, dtype="<u2", offset=1).copy()
    if data[0] != 2 or len(data) < 2:
        raise ValueError("Unknown BF16 row")
    base = data[1]
    if base > 241:
        raise ValueError("Invalid exponent base")
    out = np.empty(count, dtype=np.uint16)
    pos = 2
    for off in range(0, count, 32):
        if pos + 48 > len(data):
            raise ValueError("Truncated block")
        payload = np.frombuffer(data, dtype=np.uint8, count=32, offset=pos).astype(
            np.uint16
        )
        packed = np.frombuffer(data, dtype=np.uint8, count=16, offset=pos + 32)
        codes = np.concatenate((packed & 15, packed >> 4)).astype(np.uint16)
        pos += 48
        e = codes + base
        # Code 15 means the full exponent follows the fixed part of the block.
        for j in np.flatnonzero(codes == 15):
            if pos >= len(data):
                raise ValueError("Truncated escape")
            e[j] = data[pos]
            pos += 1
        out[off : off + 32] = ((payload & 128) << 8) | (e << 7) | (payload & 127)
    # Reject unused trailing data instead of accepting a malformed row.
    if pos != len(data):
        raise ValueError("Trailing row data")
    return out
