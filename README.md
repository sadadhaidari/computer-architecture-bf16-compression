# BF16 compression

Sadad Haidari and Rommel Mendez-Lopez

Computer Architecture, Fall 2026

The goal is to run large language models on less hardware. This project tests
whether weights can take less RAM while keeping their original BF16 bits.

For a block of 32 weights, the format takes 48 B instead of 64 B when the
exponents fit a small range. It keeps the sign and fraction bits and stores
four-bit exponent offsets. Code 15 marks an escape; the full exponent follows
for a value outside the range. The CPU reference keeps a row raw if packing
would enlarge it.

The FPGA circuit models a compression unit between a processor and RAM:

```text
Write: processor -> encoder -> packed blocks in RAM
Read:  packed blocks in RAM -> decoder -> processor
```

The FPGA does not run the model. The circuit has passed simulation; it still
needs a RAM interface and a test on the Zybo Z7-20.

## Files

- `exponent_codec.py`: reference encoder and decoder.
- `test_exponent_codec.py`: exact-bit and bad-input tests.
- `rtl/`: circuit and testbench.
- `vectors.txt.gz`: test inputs and expected packed blocks.
- [Results](RESULTS.md): CPU measurements and circuit results.
- [Report](report/project-review.pdf): project review, with LaTeX source in `report/`.

## Run the reference test

```console
python -m pip install -r requirements.txt
python test_exponent_codec.py
```

The four tests should end with `OK`. No model download is needed.

## Run the circuit test

Install Icarus Verilog, then run from this folder:

```console
python -c "import gzip,pathlib; pathlib.Path('vectors.txt').write_bytes(gzip.open('vectors.txt.gz','rb').read())"
iverilog -g2012 -s tb_bf16_codec -o test.vvp rtl/bf16_codec.sv rtl/tb_bf16_codec.sv
vvp test.vvp
```

The bench should print `PASS cases=68056`, with all named checks set to 1.
It checks restored bits, stalls, reset, and invalid frames.

## Sources

The CPU experiment used [llama.cpp](https://github.com/ggml-org/llama.cpp) and
[Qwen3.5-2B](https://huggingface.co/Qwen/Qwen3.5-2B) weights. The sample weight
blocks in the test vectors use the [model license](LICENSES/Qwen3.5-2B.txt).
The block codec and RTL are project code. [Huff-LLM](https://arxiv.org/abs/2502.00922)
and [ZipServ](https://arxiv.org/abs/2603.17435) are background papers on lossless
model compression; their HDL is not included.
