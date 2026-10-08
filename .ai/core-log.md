## 1 COMMIT Unreleased 2026-10-08T15:09:07-07:00

#### Coming From:

Unreleased 3067943

#### Purpose:

Establish whether TinyTang's desktop core can be built for the GW5AST-138C with the user's open-source apicula and nextpnr forks, and record precisely where that build stops.

#### Outcome:

The user's `apicula-mathieufro` and `nextpnr-mathieufro` forks on branch `epic/gw5ast138c` were built and exercised on the Linux workstation and required three environment fixes worth carrying forward: `PYTHONHOME=/home/vash/oss-cad-suite` for nextpnr's embedded interpreter, which otherwise aborts with "failed to get the Python codec of the filesystem encoding" because the suite was built with prefix `/yosyshq`; `PYTHONPATH` pointing at the fork's apycula so nextpnr's build-time architecture generator reads it rather than the bundled 0.34; and a locally injected `msgspec` because `save_chipdb` requires it and the suite does not ship it. A `GW5AST-138C` chipdb generated from the local Gowin 1.9.11.03 install carries the data the published one lacks, namely twelve PLL sites, 171 HCLK pips, six `io2hclk` and six `hclk_div2` entries, and the `HAS_5A_HCLK` flag, where the published database has zero of each. The fork's nextpnr placed and routed its own `ae350-emb-tcm` example and the fork's `gowin_pack` produced a 34,668,145-byte bitstream, which was not loaded. TinyTang's own 8,585-cell netlist, carrying three PLL, one CLKDIV and three OSER10, then placed and routed with zero errors and every clock passing, `clk` at 84.48 MHz against a 21.49 MHz requirement, after the unused and unconstrained `reset2` port and its buffer were dropped. Packing that netlist was refused at the PLL's VCO band check because the design's own parameters compute to 1350, 1485 and 2000 MHz against a permitted range of 650 to 1300 MHz; the design's intent is confirmed rather than misread, since 2000 divided by 93 is the 21.5 MHz NES clock and 2000 divided by 31 is three times it. Two further integration findings were recorded: string-typed PLL parameters arrive from `read_slang` as ASCII bit vectors that the packer reads as numbers, so they require decoding before packing, and `i2c_as_gpio` cannot be passed at all because this die has no I2CCFG block, which makes the design's own `build.tcl` request for it inert under the vendor flow. Artifacts are the built nextpnr in `/tmp/tb/npnr-build`, the generated database in the fork's `apycula` directory where it is gitignored, the routed netlist in `/tmp/tb/join`, and the example bitstream at `/tmp/tb/ae350-emb-tcm.fs`; none of them is committed and all are outside this repository. In the same cycle `.ai/core-reference.md` gained twelve records for this work: TOOL-017 to TOOL-025 covering the open toolchain's own documented behaviour, including the `-v` libfile semantic that drops a design-instantiated primitive, the implicit `SYNTHESIS` define, string parameters arriving as ASCII bytes, the `*_as_gpio` flags this device honours, the database being generated when nextpnr is built, the IDE-version dependence of the vendor device files, the embedded-interpreter prefix trap, the published database's missing clock data, and the bench generator's timebase; DEV-008 and DEV-009 covering the device's twelve PLL sites and the measured pump model, with its region recorded as a measurement rather than a device limit; and PROV-006 covering the licence direction, marking the MIT records as accurate until the change is implemented rather than superseded by it. Each carries a routing row and an index line, and the file's review date moved to 2026-10-08. The required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff and confirmed that `core-log.md` and `core-reference.md` changed and that `.ai/core.md` did not, validated this entry as number 1 of the active log with a conforming header, six sections in canonical order, prose in Outcome and Next Steps and allowed Status values, validated all 158 records for unique identifiers, sequential numbering, the full key set, allowed kinds and statuses, at least one cited source each and index coverage, and confirmed that no settled history was rewritten; no conformance failure needed correction. No part of this repository, TinyTang or Tang-Phosphor was found to use intellectual property beyond what `THIRD_PARTY.md` already records.

#### Next Steps:

Check the vendor placement report for the three PLL frequencies, since that settles whether 2000 MHz is intended or an artifact of how the parameters are read, then either extend the fork's measured VCO model to the region this design uses, including the charge-pump and loop-filter constants that were measured only over 650 to 1300 MHz, or change the design's divider selection so its VCO lands inside the measured band, and only then pack and load the core. The example bitstream at `/tmp/tb/ae350-emb-tcm.fs` remains available for a hardware check of the whole toolchain path once the board is placed in one-wire mode.

#### Files Modified:

None.

#### Status:

- Build: FAIL
- Deployment: NOT RUN
- User Test: NOT RUN

---
