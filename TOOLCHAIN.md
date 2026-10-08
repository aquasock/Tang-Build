# Toolchain

Everything here was run on Linux (x86-64). No root was required: the whole
chain is a single self-contained bundle plus one git clone.

## The bundle: oss-cad-suite

Download (712 MB) and extract; nothing to install:

```bash
curl -fL -o oss-cad-suite.tgz \
  "$(gh api 'repos/YosysHQ/oss-cad-suite-build/releases?per_page=1' \
      --jq '.[0].assets[] | select(.name|test("linux-x64")) | .browser_download_url')"
tar xzf oss-cad-suite.tgz
source ~/oss-cad-suite/environment      # puts everything on PATH
```

What it provides, as measured on 2026-10-08:

| tool | version | note |
|---|---|---|
| `yosys` | 0.69+260 | `synth_gowin -family gw5a` |
| `nextpnr-himbaechel` | 0.11.1-54-g861c57be | built with `-DHIMBAECHEL_GOWIN_DEVICES=all` |
| `openFPGALoader` | v1.1.1 | knows `-b tangconsole` and `-b tangmega138k` |
| `gowin_pack` / `gowin_unpack` | apycula 0.34 | bitstream pack/unpack |
| `apycula` (Python) | 0.34 | device databases live here |

The device database for this part is inside the bundle:

```
lib/python3.11/site-packages/apycula/GW5AST-138C.msgpack.xz     1.16 MB xz → 24 MB
```

That file is the whole reason the flow works without vendor tools: `nextpnr`'s
Gowin architecture is generated from it, and `gowin_pack` needs it to emit a
bitstream.

## The examples: upstream apicula

```bash
git clone --depth 1 https://github.com/YosysHQ/apicula.git
cd apicula/examples/gw5a
make tangconsole138k      # → uart-message-tangmega138k.fs
make tangmega138k         # → big-shift-…, attosoc-…, uart-message-…
```

`examples/gw5a/Makefile` and `examples/gw5a/tangconsole138k.cst` are the
authoritative source for the exact device strings and pin constraints; the
script in `scripts/` wraps them.

`make` deletes the intermediate `*-…json` after packing. `nextpnr` can be re-run
alone when a variant is wanted (for example to re-pack compressed with
`gowin_pack -c`).

## Building a device database yourself (not needed)

The chipdb is built from Gowin's own `.dat` files, which live in a vendor IDE
install. Apicula's CI does it inside a Docker image (`pepijndevos/apicula:1.9.10.03`)
and publishes the result in its PyPI package, so this path is only for someone
who wants to regenerate the database — set `GOWINHOME` to a Gowin install and
run Apicula's build. The published database is what was used here.

## Board side

- **FPGA**: `GW5AST-LV138PG484AC1/I0`, device revision C, on the Tang Console
  dock (PCB revision 32001C). JTAG readback of the IDCODE returns
  `0001081b`, matching Apicula's `GW5AST-138C` entry.
- **Loading needs the MCU port.** The USB-C port labelled `MCU` is a Sipeed
  FT2232 bridge (`0403:6010`): one channel is JTAG, the other a USB-UART. This is
  the "one-wire" arrangement — the board is powered from that cable alone and
  TinyTang does not run in it. `openFPGALoader` talks to that bridge at 6 MHz:

  ```bash
  openFPGALoader -b tangconsole <design>.fs       # SRAM load, volatile
  ```

  The two cables cannot be combined (the board's modules are powered from one
  input or the other), so programming the FPGA from a host and running TinyTang
  are mutually exclusive arrangements.
- **Recovery** is free: a reconfig-button press or a power cycle, and the FPGA
  is back to whatever its flash holds.
- **The project's own loader** (`tangload`, inside TinyTang) is a Gowin GPIO
  JTAG programmer on BL616 GPIO 0–3 and speaks the vendor's *binary* format, so
  it does not accept these `.fs` images. See `FINDINGS.md` §4.
