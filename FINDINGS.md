# Findings

Detailed record of 2026-10-08. Everything below was run on the machine and the
board described; transcripts are quoted as they appeared.

## 1. The toolchain is complete and self-contained

`oss-cad-suite` (nightly, 2026-10-08) ships every piece, including the device
database, so nothing has to be compiled and no root is needed:

```
yosys                 0.69+260
nextpnr-himbaechel    nextpnr-0.11.1-54-g861c57be   (built with -DHIMBAECHEL_GOWIN_DEVICES=all)
openFPGALoader        v1.1.1
gowin_pack, gowin_unpack
apycula               0.34, with apycula/GW5AST-138C.msgpack.xz (1.16 MB xz → 24 MB unpacked)
```

Upstream `YosysHQ/apicula` carries the board's own example target and pin
constraints, which is what made this a one-command experiment:

```
examples/gw5a/Makefile:
    tangconsole138k:  uart-message-tangmega138k.fs
    tangmega138k:     big-shift-…  attosoc-…  uart-message-…
examples/gw5a/tangconsole138k.cst      ← pin constraints for this board
```

The device invocation the Makefile uses, for the record:

```
yosys … "read_verilog <top>.v; synth_gowin -json out.json -family gw5a"
nextpnr-himbaechel --json out.json --write pnr.json \
    --device GW5AST-LV138PG484AC1/I0 --vopt cst=tangconsole138k.cst
gowin_pack --cpu_as_gpio -d GW5AST-138C -o out.fs pnr.json
```

Note the full part number at `--device` (that is how Apicula handles the `C`
device revision) versus the family name at `gowin_pack -d`.

## 2. Bitstreams built

| design | size (raw .fs) | size (compressed) | notes |
|---|---|---|---|
| `uart-message` | 35,199,205 | 7,042,517 | prints the Apicula README over UART |
| `attosoc` | 34,668,145 | — | picorv32 RISC-V SoC, **timing-closed** |
| `big-shift` | 34,668,145 | — | large shift-register stress test |

`attosoc`'s timing report, quoted:

```
Info: Max frequency for clock 'cpu.clk': 142.01 MHz (PASS at 12.00 MHz)
Info: Program finished normally.
```

So a real SoC — CPU, memory, peripherals — places, routes and closes timing on
this part with open tools.

`gowin_pack -c` compresses: 35.2 MB → 7.0 MB. That also explains the size
difference against the vendor-built cores, which are ~4.5 MB for a much smaller
design.

## 3. It runs on the real board

Loaded over the MCU port's FT2232 bridge:

```
$ openFPGALoader -b tangconsole uart-message-tangmega138k.fs
Jtag frequency : requested 6.00MHz    -> real 6.00MHz
Parse file uart-message-tangmega138k.fs: Done
DONE
Erase SRAM Load SRAM [=====…] 8.94% … 100.00%
Done
DONE
```

The design transmits the Apicula README at 115200 on the FPGA's `UART_TX`
(ball U15). Captured on the host at `/dev/ttyUSB1`:

```
evidence/uart-live-capture.bin   17,096 bytes
evidence/apicula-message.txt      7,219 bytes decoded
```

The payload is Apicula's own README (its opening, the Getting Started section
and the supported-board list) followed by nextpnr's README build instructions.
It loops continuously. Two details in the payload worth noting:

- the supported-board list in the text **does not mention the Tang Console or
  the Tang Mega 138K** — the payload is a frozen copy of the README from before
  the GW5AST support landed, so the demo's own documentation is older than the
  device it is running on
- the UART module is from the **icebreaker** examples (© 2018 Piotr
  Esden-Tempski), whose copyright header is still in the Verilog

## 4. The binary format gap (the main obstacle to a card-based flow)

TinyTang's in-firmware loader failed on the same bitstream, and the reason is
mundane — two different Gowin bitstream encodings:

```
$ tangload /open-flow-test.fs            # TinyTang, over the BL616's GPIO JTAG
Writing 7042517 bytes...ID=0001081b, status=00026220
Erase: pollFlag...Erase: OKErase: disableCfg...Erase: done...Erase: status=0x00000220
Erasing again...ID=0001081b, status=00020638
Load SRAM
Usercode=0x00000000, status=0x00020230
Failed to program SRAM
tangload: failed
```

Two useful facts came out of that failure anyway: the JTAG link works, and the
FPGA reports **`ID=0001081b`**, which is `GW5AST-138C` in Apicula's device table.

The cause:

```
vendor core (build/desktop/place2/desktop.bin, 4.5 MB):
  00000000: ffff ffff … dede dede … a5c3 0600 0000 0001 081b 1000 0000   ← binary, has a header

apicula output:
  00000000: 3131 3131 3131 3131 …   ← ASCII "11111111…", Gowin's text .fs
```

`gowin_unpack` fails on the vendor file the other way round (`UnicodeDecodeError`
opening it as text), which confirms the two are distinct encodings. So:

- **Open-built cores load today** from a host, over the MCU port, with
  `openFPGALoader`
- **`tangload` needs a converter** — an `.fs` → `.bin` step, on the host in
  `tools/` or inside the firmware's existing Gowin programmer — to keep
  TinyTang's "cores live on the SD card" ergonomics

## 5. Capture fidelity — a caveat about the evidence

The live capture is **not** a byte-exact image of one loop. Two measurements
show bytes being dropped by the USB-serial path, not by the FPGA:

- the unique loop-start marker `Project Apicula\r\n\r\nOpen` appears at capture
  offsets 426 and 14,426 — 14,000 bytes apart, where a fixed loop is 8,192 bytes
- but probing the source at several depths shows a **constant** offset over a
  ~4 KB run: `src[0x800]` at `0x7ac`, `src[0x1000]` at `0xfac`, `src[0x1a00]` at
  `0x19ac` — i.e. one contiguous, faithful stretch of the source

So: the FPGA transmits the payload correctly, and an occasional dropped chunk in
the capture produces the apparent jumps. The exact artifact is the `.fs` file,
not the capture. Re-capturing with flow control or at a lower read rate would
settle it outright.

## 6. What is still unproven

- **Our own cores.** Everything proven on hardware is Apicula's own example.
- **The clock tree.** GW5A PLL/HCLK support is conditional in nextpnr's
  architecture generator (`CHIP_HAS_PLL_HCLK`, `CHIP_HAS_CLKDIV_HCLK`). A real
  core with several clock domains is the open question.
- **TMDS/IOLOGIC.** The HDMI output path needs SERDES/OSER/ODDR primitives.
  Apicula has examples for them on GW5A-25A; untested on the 138C here.
- **BSRAM/DSP packing**, and timing closure at pixel rates (~93 MHz for the
  project's desktop core).

## 7. Next steps

1. Pre-flight the three risky primitives against this board using Apicula's own
   examples (`pll7`, `oser10`/`oddr-tlvds`, the DPB/SDP BSRAM family), rather
   than discovering gaps inside a full core.
2. Build `fpga/desktop/` from TinyTang with its existing `desktop.cst`, load it,
   and compare against the vendor-built bitstream for the same source
   (3,780 LUTs / 2,313 FFs / 14 BSRAMs / 1.5 DSPs; vendor timing closed at
   93.174 MHz pixel). Same source, so any difference is the toolchain.
3. Decide the `.fs` → `.bin` question, since it decides whether open-built cores
   can be dropped on the SD card like every other core.

## 8. Provenance note

Nothing from Sipeed's or Gowin's download bundles is redistributed here. The
device database used is Apicula's, published in its PyPI package; Apicula builds
it from vendor data files inside a Docker image (`pepijndevos/apicula:1.9.10.03`)
at *their* end, and ships the result. Building a chipdb locally would need a
Gowin install (`GOWINHOME`); using the published one needs nothing.
