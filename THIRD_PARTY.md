# Third-party components

What this repository uses, who owns it, and under what terms. Nothing here is
vendored: the code comes from upstream at the paths below, and only our own
record, scripts and captured evidence are committed.

## Project Apicula — MIT

Bitstream documentation and tooling for Gowin FPGAs. The device databases this
whole flow rests on — including `GW5AST-138C.msgpack.xz` — are theirs.

- https://github.com/YosysHQ/apicula
- Licence: MIT
- Used as: the `apycula` Python package (0.34) inside oss-cad-suite, and the
  `examples/gw5a/` target and pin constraints this repository's script builds
- The example design `uart-message-tangconsole138k.v`, whose payload is captured
  under `evidence/`, is theirs

## nextpnr — ISC

Place and route. Gowin support lives in the `himbaechel` architecture and is
generated at build time from Apicula's device database.

- https://github.com/YosysHQ/nextpnr
- Licence: ISC
- Built in oss-cad-suite with `-DARCH=himbaechel -DHIMBAECHEL_UARCH=gowin -DHIMBAECHEL_GOWIN_DEVICES=all`

## yosys — ISC

Synthesis. `synth_gowin -family gw5a` is the entry point.

- https://github.com/YosysHQ/yosys
- Licence: ISC

## oss-cad-suite — aggregation by YosysHQ

A prebuilt bundle of the above plus openFPGALoader and many other tools. Not
redistributed here; `TOOLCHAIN.md` says where to get it.

- https://github.com/YosysHQ/oss-cad-suite-build

## openFPGALoader — Apache-2.0

Programs the FPGA over the board's FT2232. Knows this board natively
(`-b tangconsole`).

- https://github.com/trabucayre/openFPGALoader
- Licence: Apache-2.0

## icebreaker UART (inside the example design) — ISC-style

The demo's UART transmitter is taken from the **icebreaker** examples, whose
header is preserved in the Verilog:

```
Copyright (C) 2018 Piotr Esden-Tempski <piotr@esden.net>
Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.
```

## Not redistributed

Nothing from Sipeed's or Gowin's download bundles — no schematics, no vendor
datasheets, no toolchain installers, no example bitstreams. Where a board fact
came from a vendor document (the MCU-port bridge, the device revision, the
one-wire/two-wire behaviour), it is stated as a finding in `FINDINGS.md` and
`TOOLCHAIN.md` rather than copied.

The vendor-produced core images and the Sipeed schematic PDFs live in the
TinyTang repository, which documents their terms separately.
