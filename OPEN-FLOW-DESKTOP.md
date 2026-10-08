# The project's own desktop core, through the open tools

`FINDINGS.md` ended with the honest note that everything proven on the board was
Apicula's own example, and that the project's own core was untested. This
chapter is the first step of closing that: getting TinyTang's `fpga/desktop`
core — top module `nestang_top`, for `GW5AST-LV138PG484AC1/I0` revision C —
through **synthesis** with the open toolchain, and out the other side as a
netlist `nextpnr-himbaechel` can consume.

Status: **synthesis works and is checked. Place and route is the next step.**

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

## What is next

1. `nextpnr-himbaechel` on this netlist with the design's own `desktop.cst`
   (pin constraints) and `desktop.sdc` (timing), for
   `--device GW5AST-LV138PG484AC1/I0`.
2. `gowin_pack` with the same `*_as_gpio` options `build.tcl` sets.
3. Load it (`openFPGALoader -b tangconsole`) and see the desktop on HDMI. Same
   source as the vendor bitstream, so any difference is the toolchain.

Open questions carried forward: whether the pre-P&R resource gap closes during
placement; whether `nextpnr`'s GW5A PLL/HCLK and IOLOGIC support covers three
PLLs, a CLKDIV and three OSER10s in one design; and the `.fs` → `.bin` question
for card-based loading.
