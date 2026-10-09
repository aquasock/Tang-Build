# Tang-Build

Building FPGA bitstreams for the Sipeed **Tang Console 138K** with an
**entirely open-source toolchain** — no Gowin EDA anywhere in the chain.

This repository records the work, the exact commands, and the raw evidence.
The short version: on 2026-10-08 a bitstream produced by `yosys` →
`nextpnr-himbaechel` → `gowin_pack`, loaded by `openFPGALoader`, ran on a real
Tang Console 138K and talked over its UART.  The project's own desktop core now
goes through the whole flow with the same tools — it places, routes, packs,
loads over both JTAG and `tangload`, and runs on the board, answering on UART1
at 2 Mbaud.  Its HDMI output is the one thing that does not yet work, and the
reason is located rather than guessed: the route that carries the TMDS bit
clock to the serialisers is missing inside nextpnr.

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
- [x] The project's own desktop core **synthesises** with the open flow —
      8,585 cells, and the three PLLs, one CLKDIV and three OSER10s the vendor
      build has ([`OPEN-FLOW-DESKTOP.md`](OPEN-FLOW-DESKTOP.md)).  The core
      lives at `fpga/desktop` in the TinyTang tree; this repository's `fpga/`
      holds the `clock-smoke` bring-up design
- [x] …**places, routes, packs and loads.**  The no-PLL wall is gone: the
      database regenerated from the local Gowin install carries `hclk_pips`
      171, `io2hclk` 6, `hclk_div2` 6 and `HAS_5A_HCLK`, where the published
      one has zero of each, so the PLLs place and the whole design routes.
- [ ] …**and runs with a display.**  The core runs — loaded over two-wire
      `tangload`, it answers on UART1 at 2 Mbaud after a full SRAM erase, and
      the console returns to its prompt — but its HDMI output produces no
      signal.  What is *not* the cause is now established: the build's clock
      and pad configuration at the three TMDS serialisers matches the vendor's
      (`FCLK` present and sourced from `HCLK0` at all three, `PCLK` likewise),
      the PLL frequencies are right, and the bitstream is byte-reproducible.
      The difference from the vendor's build is somewhere else, and is open —
      [`evidence/desktop-clock-routing.txt`](evidence/desktop-clock-routing.txt)
- [x] `.fs` → `.bin` conversion, so open-built cores load from the SD card
      through TinyTang's existing `tangload` —
      [`tools/fs-to-bin.py`](tools/fs-to-bin.py), validated by reproducing
      Gowin's own `.bin` from Gowin's own `.fs` byte for byte, and exercised on
      the board

## Reproduce it

`oss-cad-suite` carries the tools, including apicula 0.34.  It does **not**
carry a usable `GW5AST-138C.msgpack.xz`: that database is *built* from Gowin's
`.dat` files, so it is regenerated locally from a vendor install —
[`TOOLCHAIN.md`](TOOLCHAIN.md) has the command, the paths and the expected hash
to check the result against.  Then:

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
- the **project's own desktop core** was built this way and loaded onto the
  board **twice over**: as a `.bin` through TinyTang's `tangload` in two-wire
  mode, and earlier as a `.fs` over JTAG.  It runs — the console reports
  `core 84 answering on UART1 at 2000000 baud` and returns to its prompt with
  no hang (`evidence/desktop-2wire-cycle.txt`)
- the **`.fs` → `.bin` path is exercised, not merely written**:
  `tools/fs-to-bin.py` reproduces Gowin's own `.bin` from Gowin's own `.fs`
  byte for byte (`sha256 c8406c7f…`, `cmp` clean), and the file it produces
  loads on the board
- **the bitstream is byte-reproducible from this repository's own tools.**
  `nextpnr` built from the fork's `epic/gw5ast138c` tip, `gowin_pack` from the
  fork's apicula, and the database regenerated from the local Gowin install
  rebuild the core's bitstream exactly — `.fs`
  `ec6baf2a894a8b6c3f991874d969b27ff5bab391a26d8440d85efe39dc80b6f1`, `.bin`
  `9b70a448…` — matching the file that ran on the board

Not verified, and stated plainly in [`FINDINGS.md`](FINDINGS.md):

- **the display.**  The desktop core runs, but its HDMI output produces no
  signal, and the reason is no longer thought to be at the serialisers: the
  clock and pad configuration there matches the vendor's, `FCLK` included.  What
  differs from the vendor's build is elsewhere and is not yet located — see
  [`evidence/desktop-clock-routing.txt`](evidence/desktop-clock-routing.txt),
  sections 11 onwards, which supersede the earlier reading in that file
- the core's **OLED and audio** paths, which are built but unexercised
- the UART capture **drops bytes occasionally** (USB-serial), so it is evidence
  of content, not a byte-exact image; the `.fs` file is the exact artifact

## Layout

```
README.md                     this file
OPEN-FLOW-DESKTOP.md          the project's own core through the open tools
FINDINGS.md                   detailed results, transcripts, open questions
TOOLCHAIN.md                  what is installed, versions, paths, licences
THIRD_PARTY.md                upstream projects and their licences
scripts/build-open-bitstream.sh   the whole recipe, one command
scripts/build-clock-smoke.sh  build the fpga/clock-smoke bring-up design
scripts/synth-desktop.sh      synthesise fpga/desktop to a netlist
scripts/synth-desktop.ys      the yosys script it runs
scripts/pnr-desktop.sh        take that netlist into nextpnr — needs the fork's
                              nextpnr on PATH, not oss-cad-suite's
scripts/nopll-variant.sh      build the no-PLL bring-up variant (experiment)
patches/                      source edits the design genuinely needs
 0001-open-toolchain-portability.patch
tools/capture-uart.py         read the FPGA's UART and hexdump it
tools/decode-message.py       decode the demo payload (bytes / text / hexdump)
tools/decode-clock-smoke.py   decode clock-smoke's readout lines
tools/fs-to-bin.py            Gowin text .fs → vendor binary .bin, for tangload
evidence/                     raw captures, logs and built bitstreams
```

## Licence

None chosen yet — this is a record of a session's work, and the interesting
parts are the commands and the findings. Upstream components carry their own
licences (Apicula MIT, nextpnr ISC, yosys ISC); see `THIRD_PARTY.md`. Nothing
from Sipeed's or Gowin's downloads is redistributed here.
