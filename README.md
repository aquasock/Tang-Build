# Tang-Build

Building FPGA bitstreams for the Sipeed **Tang Console 138K** with an
**entirely open-source toolchain** — no Gowin EDA anywhere in the chain.

This repository records the work, the exact commands, and the raw evidence.
The short version: on 2026-10-08 a bitstream produced by `yosys` →
`nextpnr-himbaechel` → `gowin_pack`, loaded by `openFPGALoader`, ran on a real
Tang Console 138K and talked over its UART; and the project's own desktop core
now synthesises with the same tools, down to a netlist with every clock
primitive the vendor build has.

## Why this matters

The Tang Console's FPGA is a Gowin **GW5AST-LV138PG484AC1/I0**. Until now,
building anything for it meant the vendor IDE: Gowin EDA, a licence, and a
Windows-first workflow. [Project Apicula](https://github.com/YosysHQ/apicula)
reverse-engineers Gowin's bitstream format and publishes a device database for
this exact part, and `nextpnr-himbaechel` generates its Gowin architecture from
that database. Together they close the chain:

```
Verilog  --yosys-->  JSON  --nextpnr-himbaechel-->  routed JSON  --gowin_pack-->  .fs  --openFPGALoader-->  FPGA
```

## Status

- [x] Open toolchain installed and self-contained (oss-cad-suite, no root)
- [x] Bitstreams built for `GW5AST-LV138PG484AC1/I0` (incl. a picorv32 SoC that
      timing-closes at 142 MHz)
- [x] **A bitstream built this way runs on the real board** and transmits over UART
- [x] The project's own `fpga/desktop/` core **synthesises** with the open flow —
      8,585 cells, and the three PLLs, one CLKDIV and three OSER10s the vendor
      build has ([`OPEN-FLOW-DESKTOP.md`](OPEN-FLOW-DESKTOP.md))
- [ ] …placed, routed, packed and running on the board
- [ ] `.fs` → `.bin` conversion, so open-built cores can load from the SD card
      through TinyTang's existing `tangload`

## Reproduce it

`oss-cad-suite` carries everything, including apicula 0.34 and the
`GW5AST-138C.msgpack.xz` device database. See [`TOOLCHAIN.md`](TOOLCHAIN.md) for
versions and paths; then:

```bash
scripts/build-open-bitstream.sh          # builds + packs, leaves .fs files in build/
scripts/build-open-bitstream.sh --load   # ...and loads one onto the board
```

The load needs the board's **MCU** USB-C port (the FT2232 bridge), i.e. the
one-wire arrangement where the board appears as `0403:6010` and TinyTang is not
running. SRAM loads are volatile — a power cycle or the reconfig button erases
them.

## What was verified, and what wasn't

Verified on hardware, with the raw bytes kept under `evidence/`:

- the JTAG readback reports **device ID `0001081b`**, which is
  `GW5AST-138C`'s ID in apicula's table (`06 00 00 00 00 01 08 1b`)
- `openFPGALoader -b tangconsole` erases and loads the SRAM to 100% and reports
  `Done`
- the loaded design's UART output was captured off the board at 115200 on
  `/dev/ttyUSB1`: `evidence/uart-live-capture.bin` (17,096 bytes), decoded to
  `evidence/apicula-message.txt`

Not verified, and stated plainly in [`FINDINGS.md`](FINDINGS.md):

- **no project core has been built this way yet** — the bitstreams proven on
  hardware are Apicula's own examples
- the **binary format gap**: Apicula emits Gowin's text `.fs`, while TinyTang's
  in-firmware programmer (`tangload`) writes the vendor **binary** `.bin`, so
  `tangload` rejects these images as-is
- the UART capture **drops bytes occasionally** (USB-serial), so it is evidence
  of content, not a byte-exact image; the `.fs` file is the exact artifact
- the risky primitives for a real core — the GW5A clock tree/PLL, the
  IOLOGIC/TMDS path, BSRAM/DSP packing — are untested here beyond Apicula's own
  example coverage

## Layout

```
README.md                     this file
OPEN-FLOW-DESKTOP.md          the project's own core through the open tools
FINDINGS.md                   detailed results, transcripts, open questions
TOOLCHAIN.md                  what is installed, versions, paths, licences
THIRD_PARTY.md                upstream projects and their licences
scripts/build-open-bitstream.sh   the whole recipe, one command
scripts/synth-desktop.sh      synthesise fpga/desktop to a netlist
scripts/synth-desktop.ys      the yosys script it runs
patches/                      source edits the design genuinely needs
 0001-open-toolchain-portability.patch
tools/capture-uart.py         read the FPGA's UART and hexdump it
tools/decode-message.py       decode the demo payload (bytes / text / hexdump)
evidence/                     raw captures, logs and built bitstreams
```

## Licence

None chosen yet — this is a record of a session's work, and the interesting
parts are the commands and the findings. Upstream components carry their own
licences (Apicula MIT, nextpnr ISC, yosys ISC); see `THIRD_PARTY.md`. Nothing
from Sipeed's or Gowin's downloads is redistributed here.
