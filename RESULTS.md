# Results

The full-model CPU test used the converted Qwen3.5-2B text model: 320 tensors,
with vision and MTP components excluded from both modes. Both modes used the
same llama.cpp CPU build on an AMD Ryzen 9 7900X with 32 GB RAM and no GPU work.

| Measure | Raw BF16 | Packed BF16 |
| --- | ---: | ---: |
| Weight data, including the row index | 3.765 GB | 2.829 GB |
| Peak process RAM | 3.99 GB | 3.06 GB |
| Generation at 12 CPU threads | 15.95 tokens/s | 19.92 tokens/s |
| Under a 4.5 GB process allocation cap | Load failed | Ran |

RAM and generation are medians of three fresh-process pairs, with 512 context
slots and batches of 32. GB means 1,000,000,000 B. Generation excludes model load,
prompt processing, and score export. The 4.5 GB cap limits private committed
allocations on this PC; it is not a test on a smaller device.

All restored tensor bits matched. Model output scores matched on the test
inputs. The report gives the full counts. This repo contains a block demo;
it does not include the full model or the inference build.

## Limits

At two threads, generation fell from 14.69 to 6.13 tokens/s. At six threads,
the short test gave 15.65 versus 15.91 tokens/s. Restoring weights costs CPU
work. The hardware decoder is intended to replace that work, but its effect
on model speed still needs a board test.

The format approaches a 25% weight reduction when most exponents fit its range.
It cannot give a tenfold reduction. An eight-bit model remains smaller. We have
not run a frontier model on a small device.

## Circuit test

The bench passes 68,056 frames, including all 65,536 BF16 bit patterns, 1,024
random blocks, and 1,496 blocks from 187 model matrices. It also checks 16
consecutive accepted frames, stalls, reset, and malformed input.

Yosys maps the encoder and decoder to 7,537 LUT cells and 1,170 flip-flops,
with no DSP or block RAM. Those counts exclude the RAM interface and test
frame buffer. There is no measured board clock, power, or RAM bandwidth.

Next, connect the block store to RAM, overlap reads with decoding, and count
stalled clocks at each interface. That will show whether RAM or restoration
limits the read rate.
