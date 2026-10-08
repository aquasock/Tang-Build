# The project's own desktop core, through the open tools

`FINDINGS.md` ended with the honest note that everything proven on the board was
Apicula's own example, and that the project's own core was untested. This
chapter is the first step of closing that: getting TinyTang's `fpga/desktop`
core — top module `nestang_top`, for `GW5AST-LV138PG484AC1/I0` revision C —
through **synthesis** with the open toolchain, and out the other side as a
netlist `nextpnr-himbaechel` can consume.

Status: **synthesis works and is checked; place and route runs and stops at the
PLL, for reasons that are upstream's and are current.**

There is one substantial mistake recorded here on the way to that result. It is
kept, with its retraction, because the mistake is the more useful half of the
chapter: a netlist that was missing every clock primitive passed every check we
had, including a plausible resource histogram and a clean exit code.

## The rule for this exercise

The design is the vendor's, and it is the *design* we want to prove the
toolchain against. So the toolchain gets adapted to the HDL, not the other way
round: nothing was restructured, and the four source edits that were unavoidable
(below) are all cases where the SystemVerilog as written is *not legal SV* and
the vendor tool was being lenient. Three of them are one defect repeated.

## Getting a design tree

TinyTang already reconstructs the vendor project into a flat tree — it does this
to feed its own build. That command, and nothing else, produces the tree:

```bash
tools/build_desktop_core.sh --prepare-only
```

It reads the project file (`src/desktop/build.tcl`) and lays the sources out in
`build/desktop/reconstruct.<random>/`. The file list and options in that
`build.tcl` are what this recipe follows:

```
set_device GW5AST-LV138PG484AC1/I0 -device_version C
add_file src/desktop/board.v          # first: it carries the `define`s
25 files total, top module nestang_top, -verilog_std sysv2017
set_option -use_mspi_as_gpio 1 … -use_sspi_as_gpio 1
```

`src/desktop/board.v` defines the nine macros the design is built with
(`RES_720P`, `GW_IDE`, `MEGA138K`, `PRIMER`, `CONSOLE`, `USB1`, `USB2`,
`MENU_CORE`, `DESKTOP_CORE`), and because it is read first it is the single
source of truth for them — the vendor build and this one see the same defines.

## Running it

```bash
scripts/synth-desktop.sh /path/to/reconstruct.XXXXXX
```

From a fresh `--prepare-only` tree the whole sequence is:

```bash
tools/build_desktop_core.sh --prepare-only
cd build/desktop/reconstruct.XXXXXX
patch -p1 < …/Tang-Build/patches/0001-open-toolchain-portability.patch
…/Tang-Build/scripts/synth-desktop.sh .
```

The script checks that the four edits are in place, links `background.txt` where
`$readmemb` looks for it, stages the cell-library shim, injects the blackbox
list (see below), runs `scripts/synth-desktop.ys`, and then verifies the result
before claiming success. It writes `nestang-top-open.json` — the same file kept
here as `evidence/desktop-core-netlist.json.gz` — and prints a `stat`.

## Four edits, and why each is legitimate

`patches/0001-open-toolchain-portability.patch`, 53 lines, four files:

- `src/iosys/iosys_bl616.v` — `input reg [7:0] kbd_data` → `output reg`. The
  port is *driven* inside the module and the caller never connects it
  (`nestang_top.sv:505`; the elaborator says so: *output port 'kbd_data' has no
  connection*). Declaring it an output is what the code already means.
- `src/hdmi2/hdmi.sv` — `control_data = 6'd0` → `<=`.
- `src/hdmi2/packet_picker.sv` — two blocking `frame_counter` updates → one
  non-blocking ternary.
- `src/nes2hdmi.sv` — `audio_divider++` → `audio_divider <= audio_divider + 1`.

The last three are one class of defect: a **blocking assignment inside an
`always_ff` that also assigns the same variable non-blocking**. SystemVerilog
does not permit this, which is why `read_slang` rejects it; Gowin's synthesizer
evidently accepts it and infers a register. Each rewrite is exactly equivalent —
the `packet_picker` comparison tests the value *before* the increment in both
forms, and an 8-bit add wraps identically either way. Worth reporting upstream:
the design is legal-by-luck today.

## What the open front-end needed

**1. Use the `slang` front-end.** `read_verilog` rejects `input reg` ports and
unpacked-array ports (`pmod0_io`). `read_slang` takes the sources as they are.

**2. `-U SYNTHESIS`.** `src/hdmi2/serializer.sv` picks its output primitive by
preprocessor branch, with Gowin's `OSER10` on the `` `elsif GW_IDE `` path — so
what selects it is `SYNTHESIS` being *undefined*. The front-end defines it
implicitly (`--no-synthesis-define` is the documented switch for that), hence
the explicit `-U SYNTHESIS`. Without it the netlist asks for a Xilinx
`OSERDESE2` that does not exist on this chip.

**3. The library needs `specify` blocks stripped.** `cells_sim.v` carries 44
timing `specify` blocks that slang's elaboration refuses.
`synth-desktop.sh` writes `.open-shim/cells_sim_nospecify.v` with those regions
removed.

**4. `background.txt` must be reachable.** `src/nes2hdmi.sv` does
`$readmemb("background.txt", mem)`, which slang resolves next to the *reading
file*, not along `-I`. The data lives at `src/assets/background.txt`, so the
recipe links `src/background.txt` to it.

## The finding: `-v` means *not instantiated*, and that is silent

This is the one that cost the most.

The cell libraries cannot be design sources: `synth_gowin` runs its own
`read_verilog -lib` over the same files and aborts with
`Re-definition of module \LUT1!`. So they are passed to `read_slang` with `-v`.
What `-v` actually means, from the tool's own help:

```
-v,--libfile <file-pattern>[,...]
    One or more library files, which are separate compilation units where
    modules are not automatically instantiated
```

**Not automatically instantiated.** So `-v` makes the library *visible* — the
design elaborates cleanly, `defparam PLL_inst.CLKOUT0_EN = "TRUE"` resolves, no
errors, no warnings about it — and then drops every primitive the design
instantiates. `--blackboxed-module` is what puts them back: *"the instance will
be imported as a black box."* Both flags are required.

The scale of the silence:

| variant | cells | PLL | CLKDIV | OSER10 | check |
|---|---|---|---|---|---|
| primitives blackboxed, stock `synth_gowin` | **8,585** | 3 | 1 | 3 | PASS |
| primitives dropped, stock `synth_gowin` | 36 | 0 | 0 | 0 | FAIL |
| primitives dropped, no `-undriven` | **7,147** | 0 | 0 | 0 | FAIL |

The middle row is an obvious failure. The **third row is not**: 7,147 cells, a
resource histogram full of `LUT4`/`DFFRE`/`ALU`, a netlist written, a clean exit.
It was read as the success for a while. It has no PLL, no CLKDIV and no OSER10
in it — no clocks and no HDMI — and there is nothing in the log that says so.

## The check that now catches it

A blackbox instance drives the nets its output ports touch. Drop the instance
and the nets remain, driver-less, and yosys's `check` pass says so. So
`scripts/synth-desktop.sh` looks for driver-less wires whose name ends in an
output pin of one of the blackboxed primitives, and on a hit it names what went
missing, deletes the netlist and fails:

```
ERROR: 31 output(s) of instantiated cell-library primitives are driver-less --
the instance was dropped:
    div5.CLKOUT
    pll_27.PLL_inst.CLKOUT0
    pll_hdmi.PLL_inst.CLKFBOUT
    u_hdmi.hdmi.serializer.gwSer0.Q
    …
```

The design has dangling wires of its own — `joypad_out`, `rv_dout`,
`sys_inst.mgmt_readdata` (an unconnected iosys input) — which is why the check
keys on the primitives' *output pin names*, read out of the library, rather than
on "a wire with a dot in it". Verified in both directions: it passes the real
netlist and fails a netlist built with the blackboxing removed.

The blackbox list is not maintained by hand. The script derives it at build time
from the design sources — every cell-library module whose name begins a line —
and injects it. The derivation deliberately over-collects (it picks up names
that are only local signals, such as the 6502 core's `DL`); blackboxing a module
the design never instantiates is a no-op, while *under*-collecting is the bug.
A list that cannot go stale is the point.

## The false start, and its retraction

Kept because it is the instructive part, and because it was committed to in
prose before it was disproved.

Before the `-v` behaviour was understood, row 3 above looked like the answer and
row 2 looked like the bug. The diagnosis built on that: *`opt -undriven` in
`synth_gowin`'s `map_ffram` section deletes the design, because the PLL outputs
are legitimately driver-less at synthesis time; run the tool's pass chain with
`-undriven` omitted.* The bisect that supported it, stopping the flow just
before each pass:

```
just before this pass    cells left
coarse                     6,928
map_ram                    1,869     <- memories became BSRAM: expected
map_ffram                  1,931
map_gates                     17     <- the collapse
map_ffs                       50
map_luts                      34
check                         36
vout                          36
```

That reading of the evidence was wrong. With the primitives present,
`opt -undriven` has nothing to remove — their outputs have a driver — and the
**stock** pass chain runs to completion unmodified. The flags were never the
problem; the netlist they were deleting was a netlist with no PLLs in it, which
is a netlist that *should* be deleted. The hand-rolled pass chain was treating a
symptom by stopping the tool from noticing it, and in doing so it produced a
larger, more convincing-looking wrong answer.

The recipe now uses `synth_gowin` exactly as shipped, with no private pass chain.

## The result

```
=== nestang_top ===
     8585 cells
        1   $scopeinfo
     1096   ALU
        1   CLKDIV
      185   DFF
     1987   DFFRE
      112   DFFSE
       10   DPB
        1   DPX9B
        4   ELVDS_OBUF
        1   GND
        8   IBUF
       16   IOBUF
      384   LUT1
      828   LUT2
      974   LUT3
     2235   LUT4
      589   MUX2_LUT5
       88   MUX2_LUT6
       28   MUX2_LUT7
        8   MUX2_LUT8
        9   OBUF
        3   OSER10
        3   PLL
       12   RAM16SDP4
        1   SDPX9B
        1   VCC
```

All 15 top-level ports are present — `sys_clk`, `tmds_clk_p/n`, `tmds_d_p/n`,
`pmod0_io`, `pmod1_io`, `UART_TXD/RXD`, `usb1_dp/dn`, `usb2_dp/dn`, `s1`,
`reset2`.

Against the vendor Gowin build of the same source
(`build/desktop/place2/desktop.rpt.txt`, the build TinyTang ships as
`desktop.bin`):

- vendor: **3 PLL, 1 CLKDIV, 3 OSER10**; 2641 LUT + 301 ALU, 1774 FF, 12 BSRAM, 1 DSP
- here: **3 PLL, 1 CLKDIV, 3 OSER10**; 4421 `LUT1..4` + 713 `MUX2_LUT*`, 1096 ALU, 2284 FF, 10 `DPB` + 12 `RAM16SDP4` + `DPX9B` + `SDPX9B`

The primitive counts matching exactly is the meaningful part — those are fixed
by the design, not by the toolchain, so they are the check that the right design
is in there. The LUT/ALU/FF counts differ substantially and are **not yet
comparable**: they are pre-place-and-route, and nextpnr packs LUTs, ALUs and
registers itself. That comparison has to wait for step 3.

## Where the open flow stops

`scripts/pnr-desktop.sh` takes the netlist into `nextpnr-himbaechel` and gets
through packing, the resource report and the start of placement:

```
Info: Pack PLL...
Info: Pack BSRAMs...
Info: Pack DSP...
Info: Device utilisation:
Info:                    IOB:      16/    324     4%
Info:                   LUT4:    5707/ 138240     4%
Info:               IOLOGICO:       3/    326     0%
Info:                    ALU:    1190/ 103680     1%
Info:                    DFF:    2380/ 138240     1%
Info:              RAM16SDP4:      12/  17280     0%
Info:                  BSRAM:      12/    340     3%
Info:                   BUFG:       1/      1   100%

Info: Running custom HCLK placer...
ERROR: Unable to place cell 'pll_nes.PLL_inst', no BELs remaining to implement cell type 'PLL'
```

Everything except the clock primitives is accounted for — BSRAM, DSP, the
IOLOGIC path (3 `IOLOGICO`, which are the OSER10s), 16 IOs. The wall is the PLL,
and with 3 PLLs and 1 CLKDIV in the design it is not a wall we can walk around.

Two small translations are needed to get this far, and both are in
`scripts/pnr-desktop.sh` rather than in the design:

- nextpnr's SDC reader rejects `//` comments and `desktop.sdc` opens with one.
- nextpnr requires **every** IO to have a location. `reset2` is declared in
  `nestang_top.sv` ("button S1 and pin 48 are both resets") and used nowhere,
  and the vendor build assigns it no pin either, so it cannot be placed. The
  script drops it — after first checking that nothing consumes it, and
  refusing if anything does, because quietly deleting a live port would be
  worse than the error it avoids.

### It is the toolchain, and it is current

The netlist carries the primitives the vendor build has, so the question is
whether the tools can place them. They cannot, for `GW5AST-138C`, and this is
what the check turned up:

- **The device database has no PLL data for this chip.** The published
  databases, `pad_pll` / `hclk_pips` / `io2hclk` / `hclk_div2` entries:
  `GW5A-25A` 25 / 247 / 4 / 4; **`GW5AST-138C` 0 / 0 / 0 / 0**. The clock *net*
  names are there (`TLPLL0CLK0`, `BLPLL0CLK1`, …) but nothing that tells a
  placer where a PLL sits.
- **apicula's generator has no table for it.** `_pll_pads` in `chipdb.py` has
  entries for `GW1N-1/-4/-9/-9C`, `GW1NS-4`, `GW1NZ-1`, `GW2A-18/-18C` and
  **`GW5A-25A`** — and none for `GW5AST-138C`, so `pll_pads()` returns without
  doing anything. Likewise `set_chip_flags` hands `HAS_5A_HCLK` to
  `GW5A-25A` alone, and nextpnr's generator builds its HCLK/PLL machinery only
  when the database carries those flags.
- **nextpnr says so itself.** PR #1557, "Gowin. GW5A series PLLs.": *"PLLA-type
  PLLs are implemented, which are used in GW5A-25A chips."* The 138K was added
  later (PR #1631, "Gowin. Add GW5AST-138C chip.") without PLL support.
- **Upstream's own examples agree.** `pll7` is a `primer25k` (GW5A-25A) make
  target only; the 138K targets build `big-shift`, `attosoc` and
  `uart-message`, none of which instantiate a PLL.

And nothing newer is available to try. Our `nextpnr-himbaechel` reports
`0.11.1-54-g861c57be`, and `861c57be` is **nextpnr master HEAD** as of
2026-10-07 — the revision this binary is built from. Our apicula clone is at
`b4e70dc` (2026-10-02), which is apicula **main**; PyPI's newest release, 0.34,
is from the same day. The most recent clock work upstream is *"GW5AT-60B.
Implement the clocks."* — being worked through device by device, with the 138K
not yet reached.

The good news, as far as it goes: nextpnr's Gowin architecture is *generated
from* those database tables rather than hardcoding devices, so this is a data
gap upstream rather than an architectural one.

**What was not verified:** the published 0.34 database is built by apicula's CI
from vendor `.dat` files, and regenerating one locally needs a Gowin install
(`GOWINHOME`), which is not here. So I cannot rule out that a from-source
build of the database differs from the published one for this device. That is
the one gap in the chain above.

## What is next

1. **Report it upstream.** An apicula issue for `GW5AST-138C` PLL/HCLK support
   is the thing that unblocks a bitstream for this board; nextpnr would follow.
   (Not filed from here — nothing has been sent to any third-party tracker.)
2. Watch for it, and re-run `scripts/pnr-desktop.sh` when it lands: the
   synthesis side and the netlist are done and checked, so the re-run is cheap.
3. `gowin_pack` with the same `*_as_gpio` options `build.tcl` sets, and then a
   load — both only reachable once a PLL can be placed.

Open questions carried forward: whether the pre-P&R resource gap closes during
placement (4,421 `LUT1..4` + 713 `MUX2_LUT*` and 1,096 ALU here against the
vendor's 2,641 LUT + 301 ALU); and the `.fs` → `.bin` question for card-based
loading.
