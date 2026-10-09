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

## 4. The binary format gap (closed)

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

### Resolved

The converter is [`tools/fs-to-bin.py`](tools/fs-to-bin.py), and the gap is
closed. Gowin ships the same configuration data in both encodings and the
difference is only the encoding, so the step is a repack with no framing added
or removed. It was validated against a design for which the vendor's *own* pair
exists, `TinyTang/build/desktop/source/impl/pnr/desktop.{fs,bin}`: packing the
vendor's `.fs` reproduces the vendor's `.bin` byte for byte
(`sha256 c8406c7f8573097b98de3923def1693ffdd9f8fe304e224775249fc5f0e9c592`,
`cmp` clean), and the `.fs` header says `//Compress: OFF`, so the 1:8 mapping
holds. The desktop core's own `.bin` was then placed on the card and loaded
through `tangload` on the board, which reported `core loaded` and answered on
UART1 at 2 Mbaud — see [`evidence/desktop-2wire-cycle.txt`](evidence/desktop-2wire-cycle.txt).
`tangload` never parses the framing: `fpga_program` in
`ports/bl616/tang_jtag_programmer.c` reads the file in blocks and shifts them
straight to TDI.

One encoding difference is real and harmless, recorded so it is not chased
again: the vendor's bitstream carries a 96-bit prologue — `0xff` padding, the
`dede dede` marker, then more padding — before the first `a5c3`, and apicula's
omits it. clock-smoke, which ran on this board, carries apicula's framing
exactly, so the FPGA's configuration engine accepts it either way.

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

- **The display.**  The desktop core runs on the board and answers on UART1 at
  2 Mbaud, but its HDMI output has not yet produced a signal.  The cause is now
  located and fixed in the flow rather than guessed: an IOLOGIC's fast clock
  can only be selected from lanes 0 and 2 on this die, the three TMDS
  serialisers were served by lanes 1 and 3, and the packer dropped the
  unencodable lane silently, leaving the clock mux unselected.  The flow now
  constrains the lane and the bitstream carries the selection where the
  previous one carried none.  What has been ruled out by measurement: the
  bitstream's `FCLK` and `PCLK` at the three TMDS serialisers match the
  vendor's, the PLL frequencies are right, the pad and serialiser
  configuration matches, and the bitstream is byte-reproducible.  An earlier
  reading of section 8 that the `FCLK` was absent was wrong — see section 11 of
  [`evidence/desktop-clock-routing.txt`](evidence/desktop-clock-routing.txt),
  and section 19 for this cycle.  What has NOT been settled is whether the
  remaining attribute difference at the serialisers is a difference in fuses at
  all; see section 7 item 1.
- **The core's OLED and audio paths**, which are built but unexercised.
- **Timing at pixel rates**, which the open flow reports but which has not been
  checked against the vendor's own numbers for this design.
- The UART capture fidelity caveat in section 5 still stands.

## 7. Next steps

1. **First revert the desktop core's `ODIV0_SEL` from 100 to 50.**  With the
   decoder's 2x factor removed, that value is *measured* to halve `pll_27`,
   and therefore `pll_hdmi`'s VCO and `hclk5` with it — to 185.625 MHz instead
   of 371.25, half the TMDS bit clock.  The workaround landed in entries 10-11
   rested on the decoder error, and a core carrying a known 2x defect should not
   be used to test an unknown one.
2. Confirm the display on the board.  The lane constraint is in the flow and
   the bitstream now carries `FCLKSEL1`/`FCLKSEL2` at all three serialisers
   where it previously carried no lane selection at all, but nothing has yet
   been loaded since.  One offline question is still open beside it, and it is
   deliberately NOT treated as a cause: the vendor's serialisers decode with
   four `FCLKSEL` values plus `HWL` and ours with two, but the decoder aliases
   `FCLKSEL` values onto the same fuses, so an attribute-list difference is not
   evidence of a fuse difference.  If the display is still dark, compare the
   fuses at the three TMDS tiles before changing what the packer emits.
3. `scripts/build-clock-smoke.sh`'s `/tmp` defaults are repaired — its output
   directory, its nextpnr directory and its Python dependency directory now
   point at durable paths under `/home/vash/tools`, and it refuses
   oss-cad-suite's nextpnr by path with the reason spelled out.  The caution
   that remains is the revision coupling: `gowin_pack` loads the chipdb at pack
   time, so the nextpnr binary and the device database must be regenerated
   together, and a routed netlist from an older architecture does not pack
   against a newer database.
4. The core itself needs no change for any of the above, and should not be
   rebuilt until the route works.

## 8. Provenance note

Nothing from Sipeed's or Gowin's download bundles is redistributed here. The
device database in use is **generated locally from the vendor install** at
`/home/vash/tools/gowin-1.9.11.03`, not the one published in Apicula's PyPI
package. It has to be: the published database is built by Apicula's CI from
vendor `.dat` files and, for `GW5AST-138C`, carries none of the clock data —
`hclk_pips` 0, `io2hclk` 0, `hclk_div2` 0 and no `HAS_5A_HCLK` — which nextpnr
needs to place a PLL. The locally built one carries `hclk_pips` 171, `io2hclk`
6, `hclk_div2` 6 and the flag, and its hash matches the one
[`TOOLCHAIN.md`](TOOLCHAIN.md) records, so a successor can check they have
the same database before trusting any result. Building it needs a Gowin
install (`GOWINHOME`); the toolchain bundle does not ship one and does not ship
a usable database either.

## 9. The project's own core (added later the same day)

Step 2 above has a first half done: `fpga/desktop` now goes through synthesis
with the open tools, and the netlist carries the same 3 PLLs, 1 CLKDIV and
3 OSER10s as the vendor build. That is [OPEN-FLOW-DESKTOP.md](OPEN-FLOW-DESKTOP.md),
and it is worth reading for the failure mode rather than the result: the first
version of it produced a netlist with **no clock primitives in it at all** that
passed every check available, because `read_slang`'s `-v` flag means "modules
are not automatically instantiated".

The numbers in step 2 above are also corrected there. They come from the
OLED-terminal sweep build (`build/oled-terminal/sweep-blockfix`); the build
TinyTang ships as `desktop.bin` (`build/desktop/place2`) uses **2641 LUT + 301
ALU, 1774 FF, 12 BSRAM, 1 DSP**.

Place and route is a second half, and it now completes.  This was the wall for
a while — `nextpnr-himbaechel` packed the whole design and then could not place
a PLL, because the *published* `GW5AST-138C` database carries no PLL site and no
clock pips.  Regenerating that database from the local Gowin install removes
the wall entirely: it carries twelve PLL sites, `hclk_pips` 171, `io2hclk` 6,
`hclk_div2` 6 and `HAS_5A_HCLK` where the published one has zero of each, so
the three PLLs place and the whole design routes.  Evidence in
[`evidence/desktop-core-pnr.txt`](evidence/desktop-core-pnr.txt), and the
earlier no-PLL experiment that first exposed a clock-routing gap in
[`evidence/desktop-core-nopll.txt`](evidence/desktop-core-nopll.txt).

The core then packs, loads and **runs**, and the display is the one thing left
broken — for a reason that is no longer thought to be at the serialisers.  The
bitstream's `FCLK` and `PCLK` at all three TMDS serialisers match the vendor's
exactly, the PLL frequencies are right, and packing the routed netlist
reproduces the loaded bitstream byte for byte.  An earlier reading that the
`FCLK` was missing was wrong.  `evidence/desktop-clock-routing.txt` records
where the search has been — including the readings later refuted, and the
correction — and reasoning is in [OPEN-FLOW-DESKTOP.md](OPEN-FLOW-DESKTOP.md).
