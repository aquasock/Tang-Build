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

## 2 COMMIT Unreleased 2026-10-08T19:00:06-07:00

#### Coming From:

Unreleased 973d80f

#### Purpose:

Make this project's own desktop core pack under the open toolchain and configure on the board, by settling the toolchain divergences that refused it.

#### Outcome:

TinyTang's desktop core -- `nestang_top`, `GW5AST-LV138PG484AC1/I0` revision C -- now packs with the open toolchain and configures on the board, which no project core had done before; everything proven on hardware until now was Apicula's own examples. Four faults stood in the way, all of them in the locally built `apicula` fork, and all settled by reading the vendor's own build of this same design (`TinyTang/build/desktop/source/impl/pnr/desktop.fs`) and then checking the result back against it. First, `gowin_unpack`'s `tile2verilog` BEL-name regex carried `PLLVR` and `RPLL[AB]` but no branch for this device's plain `PLL`, so `belre.match('PLL')` returned `None` and every GW5AST-138C bitstream died on `.groups()`; `PLLA|PLL` was added after `PLLVR`, and a name matching nothing now raises with its own name rather than an `AttributeError`. Second, the charge-pump fit covers `FVCO` 650..1300 MHz and the design's three PLLs run at 1350, 1485 and 2000 MHz; the four derived attributes read back out of the vendor's sites are `(FLDCOUNT 32, KVCO 7, A_ICP_SEL 190, A_LPF_RES_SEL R4)` at 1350 and 1485 and `(32, 7, 140, R4)` at 2000. `FLDCOUNT` and `KVCO` agree with the fitted ladder, which confirms the `FVCO > 1400` step the 138C override drops is really absent on this device; the charge pump does not agree, the vendor holding `R4` where the ladder would step to `R5` (140 against 80, and 190 against 110), so extrapolating from the algebra would have emitted the wrong loop filter. Those three points are now `MEASURED_ABOVE_BAND`, `pump()` refuses any other `FVCO` above the fitted ceiling instead of extrapolating, and `check_pll_fvco` takes the `fref` it needs to tell a measured point from an unmeasured one. Third, the four TMDS outputs sit on pins this chipdb marks `is_true_lvds` and `check_elvds_placement` refused the emulated LVDS the vendor ships there; lifting that refusal for this device exposed two further faults. The packer asked for `IO_TYPE` `LVCMOS_D`, whose generic code 34 this device's `.fse` does not carry (it has 33 and 35), so `add_attr_val` dropped the attribute in silence and the pins packed with no `IO_TYPE` at all, where the device's code is 236; and the emulated output was missing `DRIVE_LEVEL`, `PADDI` and attribute 51, all three of which the vendor programmes and the inherited `ELVDS_OBUF` set omits. `DRIVE=8` rather than `TLVDS_OBUF`'s 0 is what identifies the path as emulated rather than true LVDS. The packed result now matches the vendor tile for tile: the four PLL attributes are equal at all three PLLs, and the IOB fuse set at all four TMDS pins is `vendor_only=0 open_only=0` -- ten fuses, ten shared. `gowin_pack -d GW5AST-138C` then completes, giving a 35,730,232-byte bitstream with `sha256 b574930fbbc084e40a914b0e084a80ebef9e06084bd5ef4904d72210f0343164`. The chain behind it was shown reproducible rather than asserted: the device database regenerates from the Gowin 1.9.11.03 install to `sha256 3cfbe062684bbb807f7b17a0434211dbd0f7be895f16afc7055fd974fec2a9df`, and nextpnr's generated `chipdb-GW5AST-138C.bba` and `.bin` to `3aea299a2644...` and `27d66481762e...`, each byte-identical to what the build used; the full values are in `TOOLCHAIN.md`. On the board, `openFPGALoader -b tangconsole` read IDCODE `0x1081b`, erased the SRAM, loaded to 100% and reported `DONE`, so the open-built bitstream is accepted by the real part. The user's test could not run, and not because the design failed: this core has no observable without a host. The OLED's PMOD lanes are released by `active_word`, which only the BL616 writes, to register `0xc0` over the keylink (`desktop_pmod.sv:26,71,74,80`, `desktop_regs.sv:127`), so with TinyTang not running in the one-wire arrangement `personality` stays 0, `enables` stays `8'h00` and all eight lanes stay tri-stated; and the design's UART is that same keylink with no peer, which is why a capture on `/dev/ttyUSB1` returned 18-22 bytes of `0x8A` noise rather than a payload. The design is otherwise running: `sys_resetn <= ~(joy1_btns[5] && joy1_btns[2])` releases it with no gamepad attached. Two further things were recorded in this cycle. `TOOLCHAIN.md` was rewritten, because it described the device-database build as not needed and the published database as what had been used, whereas the suite's database carries no instance-level clock structures for this part at all -- `hclk_pips` 0 against 171, `io2hclk` 0 against 6, `hclk_div2` 0 against 6, PLL-carrying tiles 0 against 12 -- and following it leads straight into the wall this cycle was spent on. And the fork work was pushed to `aquasock/apicula` and `aquasock/nextpnr` on `epic/gw5ast138c`, since `core.md` permits a push only to an `aquasock` repository and the branch's parent lives at `mathieufro`. The required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed `core.md` was not changed and `core-log.md` was, and validated this entry as number 2 of the active log with a conforming header, six sections in canonical order, prose in Outcome and Next Steps, and an allowed Status set. One departure from the convention is recorded rather than hidden: `TOOLCHAIN.md` was committed as `f953ca4` before this entry was written, because at that moment the cycle's work stood unrecorded and unpushed, so the entry was committed after its tree change rather than with it. No part of this repository, TinyTang or Tang-Phosphor was found to use intellectual property beyond what `THIRD_PARTY.md` already records.

#### Next Steps:

Convert Gowin's text `.fs` into the vendor binary `.bin`, so that TinyTang's in-firmware `tangload` accepts it: the core's intended arrangement is the FPGA paired with TinyTang on the BL616 loading from the SD card, and that is the only arrangement in which the OLED lights and the gamepad works, because the PMOD lanes are released by a keylink register only the BL616 writes. Until that exists the core can be shown to configure and nothing more, so the next cycle is the `.bin` writer and its evidence, keeping the method that settled this one: where a structure is contested, read it out of `TinyTang/build/desktop/source/impl/pnr/desktop.fs` rather than reasoning about it, and validate the writer by re-reading what it produced. The known shape of the gap is in `FINDINGS.md` section 4.

#### Files Modified:

- TOOLCHAIN.md

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 3 COMMIT Unreleased 2026-10-08T20:02:52-07:00

#### Coming From:

Unreleased 9fee748

#### Purpose:

Close the binary format gap so that TinyTang's own loader can program this project's core from the SD card.

#### Outcome:

Gowin's text `.fs` and binary `.bin` turned out to be the same configuration data in two encodings, and the conversion is a bit-pack: the `.fs` carries one ASCII `0` or `1` per configuration bit, the `.bin` is those bits packed eight to a byte most significant bit first, and nothing is added, prepended or appended -- the device idcode, the user code and the CRC are fields inside the configuration data rather than around it. That was measured against a design for which both encodings exist rather than reasoned about: the vendor's own `TinyTang/build/desktop/source/impl/pnr/desktop.fs` carries 36,192,256 non-comment characters, every one of them `0` or `1`, and their `desktop.bin` is 4,524,032 bytes, exactly one eighth with no remainder, and packing the one reproduces the other byte for byte at `sha256 c8406c7f8573097b98de3923def1693ffdd9f8fe304e224775249fc5f0e9c592`. `tools/fs-to-bin.py` implements the conversion, refuses a non-binary or ragged input rather than half-converting, and prints the sha256 of what it wrote; it was verified while the `.fs` header read `//Compress: OFF`, which the docstring records as the condition the mapping was measured under. The desktop core's packed bitstream converts to 4,463,286 bytes at `sha256 fadd00bab669a4a1c3a5d2e9029fb48823cff50bc8adf38d032f4ff6caab069d`, and it was copied to the console's SD card as `evidence/desktop-open.bin` is the repository's copy. On the board, TinyTang's `tangload /cores/console138k/desktop-open.bin` accepted it -- `Writing 4463286 bytes...ID=0001081b`, erase, `Load SRAM`, `Usercode=0x00000000, status=0x00026230`, `tangload: core loaded` -- which is the first time a core built entirely with the open toolchain has been programmed by the project's own loader rather than by `openFPGALoader` over the MCU port. `tang.ini` was then set to declare the OLED on `pmod0`, and the shell's own `tangini` reported `pmod0 oledrgb, pmod1 none; word 0x0010` and later `core 0x54 (ABI 1.1) has 0xc0 = 0x0010, as declared`, so the keylink write and its read-back both work against the loaded core. `fpga` reports `core 84 answering on UART1 at 2000000 baud`, and 84 is `0x54`, `THIS_CORE_ID` from `nestang_top.sv`; that answer comes back over the link whose FPGA-side baud divisor is derived from the design's 21.492 MHz clock, so a coherent reply is evidence that the clocking settled earlier in these cycles is working on silicon. The user test did not reach a result and the cycle was closed on that. The display observable could not be obtained as expected: the OLED's cells are pushed to the core by TinyTang over the keylink (`ports/bl616/phosphor/oled_link.cpp` writes register `0x200+`, which `src/desktop/desktop_regs.sv` decodes as `oled_cell_index`), so a blank panel is not evidence about the bitstream, and the user had no PMOD seated for the first attempt; the board's BL616 also rebooted between the load and the check, its uptime reading `0 days 00:06:53`, so the SRAM load may have been lost and the `core 84` seen afterwards may have been the flash core, which carries the same identifier. Three further things were recorded rather than acted on. The loaded bitstream's preamble is shorter than the vendor's: ours reaches the `a5c3` marker at offset `0x16` and theirs at `0x22`, theirs carrying a `dede dede` field and the multiboot, security-bit and CRC options that `gowin_pack` is not given, which is a packer-option question and not a conversion one and is the first thing to suspect if TinyTang ever behaves oddly around this core. The user elected to defer, to a later cycle, the identification of a component that came off the console's dock near the antenna and the second USB-A port; the schematic (`TinyTang/docs/Tang_Mega_138K_Console_32001C__Schematics.pdf`, sheet 14) puts Murata `LXES15AAA1-153` ESD parts on `USB_A1`/`USB_A2` plus a `0402ESDA-05N` and an `RCLAMP0524P` array, with `15K/1%` host pull-downs (`R113`, `R114`) as the only parts there whose loss would have a symptom, and the board demonstrating a live BL616, mounted SD, `ble: radio up` and a loaded core is consistent with a protection part. And the fix for the missing `tang.ini` was made on the card, the previous contents kept as `/tang.ini.bak`. The required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed `core.md` was not changed and `core-log.md` was, and validated this entry as number 3 of the active log with a conforming header, six sections in canonical order, prose in Outcome and Next Steps, and an allowed Status set. No part of this repository, TinyTang or Tang-Phosphor was found to use intellectual property beyond what `THIRD_PARTY.md` already records.

#### Next Steps:

Obtain the display observable that this cycle could not: seat the PMOD OLED in the socket the card's `tang.ini` declares, re-run `tangload /cores/console138k/desktop-open.bin` so the load is certainly this build rather than whatever flash holds, and then either read the panel or drive the cells with TinyTang's own desktop layer, since it is TinyDesk that fills the core's OLED cells over the keylink and not the core itself. Two things are then owed. The component that came off the dock is to be identified properly by testing the USB-A port rather than by inference from the schematic, and the result recorded with the board. And if TinyTang ever treats this core oddly, the bitstream preamble is where to look first: `gowin_pack` is not being given the multiboot, security-bit and CRC options the vendor's own build enables, which is a difference in the packer's options and not in the converter, which is proven byte-for-byte against the vendor's own pair.

#### Files Modified:

- tools/fs-to-bin.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 4 COMMIT Unreleased 2026-10-08T20:28:46-07:00

#### Coming From:

Unreleased 32a7737

#### Purpose:

Record the observed hardware result of the core built in the previous cycle, and close the user test that cycle could not reach.

#### Outcome:

No new build was performed; the artefact under test is the one entry 3 recorded, `evidence/desktop-open.bin` at `sha256 fadd00bab669a4a1c3a5d2e9029fb48823cff50bc8adf38d032f4ff6caab069d`, and it was re-flashed to the board after a fresh BL616 boot so that the running core was certainly this build rather than whatever the flash holds. `tangload` accepted it again -- erase, `Usercode=0x00000000`, `status=0x00026230`, `core loaded` -- and the socket word was declared and read back as `0xc0 = 0x0010`. The user then observed, on hardware and unprompted, that HDMI outputs 720p, that TinyDesk is running, and that the pointer moves under the paired Bluetooth mouse. That is the whole stack in one loop: the BL616's radio, TinyDesk, keylink register writes, the core's register file, and the desktop, driven in both directions by a person. It exercises every layer these cycles touched, and it is the first time a core built entirely with the open toolchain has been observed working on this board with a display and live input. This supersedes entry 3 in two respects. Its User Test, recorded there as NOT RUN because no display observable was obtainable, is now PASS on the user's report. And its leading suspect is disproven: entry 3 attributed the OLED's unpowered panel to the video clock chain, on the reasoning that `desktop_pmod` latches its socket word only at `cx == 0 && cy == 720` and that the panel's power enable is a lane the design drives, so a dead `hclk5` would leave every lane released -- but HDMI working proves the chain from `pll_hdmi` through `hclk5` at 371.25 MHz and the CLKDIV to `hclk` at 74.25 MHz runs, so the raster counts and the latch is not clock-starved. The OLED remains dark and its remaining suspects are narrower and none of them bears on the core: the declared socket, since entry 3 set `pmod0 = oledrgb` on the strength of `docs/tang.ini` while the configuration actually on the card beforehand declared no OLED at all, the flip setting, or the panel's own power path. Two corrections of emphasis are recorded with it. `tangini` reads register `0xc0`, the `socket_word`, and not the latched `active_word`, so its line about the socket being "as declared" is weaker evidence than entry 3 implied; the frame counter at `0x108` would settle the question directly, but the firmware's `fpga_debug_request` read path is not exposed as a shell command. And `desktop` takes over the console, so the shell is unavailable while TinyDesk runs and the prompt returns only when it quits. One housekeeping change landed in this window and was committed separately as `32a7737` without an entry of its own: the harness's `.codewhale/` directory was added to `.gitignore`, because it is session state rather than project content. The required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed `core.md` was not changed and `core-log.md` was, and validated this entry as number 4 of the active log with a conforming header, six sections in canonical order, prose in Outcome and Next Steps, and an allowed Status set. No part of this repository, TinyTang or Tang-Phosphor was found to use intellectual property beyond what `THIRD_PARTY.md` already records.

#### Next Steps:

The core itself is no longer in question, so what remains is housekeeping around it. The OLED should be settled by declaring the socket the panel is actually seated in rather than the one guessed from the template, which is a one-line change to `tang.ini` on the card followed by `tangload` and a look at the panel; if it stays dark with the right socket declared and the right flip, the panel's power path is the thing to suspect and the dock component that came off earlier becomes relevant again, since the power enables are lanes the core drives. The bitstream preamble remains open: `gowin_pack` is not being given the multiboot, security-bit and CRC options the vendor's build enables, which is a difference in the packer's options rather than in the converter, which is proven against the vendor's own pair. And the campaign's evidence store should still be located, or its absence documented in the repository, because a large part of what these cycles rest on traces to measurements that are not present here.

#### Files Modified:

None.

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 5 COMMIT Unreleased 2026-10-08T20:53:06-07:00

#### Coming From:

Unreleased 30a7088

#### Purpose:

Record the controlled comparison that shows this project's bitstream does not drive the display, and correct the user test the previous entry recorded.

#### Outcome:

The previous entry's user test is superseded, and it recorded the wrong thing. A controlled comparison was run on the same board, monitor and `tang.ini`, with only the bitstream differing and each load followed by the same console output and a wait of at least thirty-five seconds: this project's build, `evidence/desktop-open.bin` at 4,463,286 bytes, produced no video on four loads, while the vendor's own desktop core from the card, `desktop.bin` at 4,463,306 bytes, produced video every time, showing TinyDesk's console with the commands just typed. The monitor was ruled out before the comparison rather than after it: it re-locks within seconds, the user waits at least thirty seconds before calling a mode absent, and the control was loaded following the fourth failure of ours, so both sides were measured under the same conditions. What the failure is not matters as much as what it is. It is not the keylink, because the core answers `core 84` on UART1 at 2000000 baud under both bitstreams, so the 21.5 MHz `clk` domain and the register file are working. It is not the TMDS IO configuration, because the IOB fuse set at all four TMDS pins was measured equal to the vendor's when this bitstream was built, ten fuses and ten shared. And it is not the OLED, which is dark under the vendor's core as well and which the user reports is unfinished in this project's own design, the desktop's 2x2 graphics mode having only worked since the previous day and the Tang-Phosphor core only ever having shown a colour screen; it cannot serve as an observable for a toolchain change and was carried as one for far too long. Two candidates remain. The first is timing on `hclk5` at 371.25 MHz, the clock this design feeds to the OSER10 serialisers and the only constrained clock nextpnr has never reported a maximum frequency for, because it drives IOLOGIC and never reaches a flip-flop pair. One observation of this bitstream did appear to work, the previous entry's TinyDesk and moving pointer, which followed a load with no power cycle between it and the observation, and one success against four failures is the signature of a marginal path rather than a wrong configuration. The second is the bitstream's option preamble, the one structural difference the two files are known to have: the vendor's carries a `dede` field and the multiboot, security-bit and CRC settings that `gowin_pack` is not being given, where ours reaches the `a5c3` marker twelve bytes earlier. The error being corrected is one of inference rather than measurement. The previous entry treated a load the agent had performed as proof of what was running when the user looked, and never verified it; the user asked for evidence before believing results and was right to, and the weakest link in an otherwise well-checked chain was that one unverified step. The required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed `core.md` was not changed and `core-log.md` was, and validated this entry as number 5 of the active log with a conforming header, six sections in canonical order, prose in Outcome and Next Steps, and an allowed Status set. No part of this repository, TinyTang or Tang-Phosphor was found to use intellectual property beyond what `THIRD_PARTY.md` already records.

#### Next Steps:

Separate the two candidates before rebuilding anything. The method that has already worked twice is to read a bitstream back and compare it with the vendor's at the sites that matter, and it applies here directly: unpack this project's bitstream and the vendor's and compare the three PLLs, the CLKDIV that divides `hclk5` down to `hclk`, and the OSER10 and IOLOGIC tiles, because a difference in the clock or serialiser configuration would name the fault outright while an exact match would leave timing as the explanation. This project's `.fs` is not committed, only its `.bin`, but the packing is one-to-one so the text form can be reconstructed from it and neither file needs the board. Timing can then be attacked by giving nextpnr something it can report on for that path, or by measuring the achieved delay through the serialiser clock, since the absence of any maximum frequency for `hclk5` is the reason this was never caught at build time and is the gap that let the previous entry's result stand. Only if both of those come back clean is the option preamble worth pursuing, and it is the most invasive of the three because it means changing what `gowin_pack` is asked to write. Nothing in this needs the board, and the board should be left as it is.

#### Files Modified:

None.

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: FAIL

---

## 6 COMMIT Unreleased 2026-10-08T21:48:31-07:00

#### Coming From:

Unreleased 7b48976

#### Purpose:

Isolate the desktop core's clock chain in a minimal design that can be built, loaded and observed on the board, so that the display path's failure can be attributed to a clock or ruled out of it.

#### Outcome:

The display path's failure was attacked by isolating its clock chain, and the isolation changed what is known. `fpga/clock-smoke/` carries nothing but `sys_clk` 50 MHz into `pll_27`, that into `pll_hdmi`, and that through the desktop core's own `CLKDIV #(.DIV_MODE(5))` to `hclk`, with counters in all three domains as the readout; it is built by `scripts/build-clock-smoke.sh` against the locally generated database. Two faults had to be cleared before it would build. Left unpinned, nextpnr chose exactly the sites the upstream fuzz campaign had already measured as broken in this open flow's model, `PLL_B[0]`, `PLL_B[2]` and HCLK block 1, which `fuzz/gw5ast138c/shapes/clocking_e2e.py` records as unable to route `CLKOUT0` to fabric and as carrying no modelled clock escape, and routing then failed on `hclk`; pinning `pll_27` to `PLL_L[1]`, `pll_hdmi` to `PLL_L[3]` and `div5` to `X181Y81/CLKDIV_3` fixed it, the first two by `INS_LOC` in the constraint file and the third by an RTL `BEL` attribute, which is the desktop core's own arrangement and the only spelling nextpnr's `.cst` reader takes for a CLKDIV on this die. The readout itself had to be replaced. The first version drove `led[0..4]` at the balls Apicula's `tangconsole138k.cst` names, W19, F19, E22, W20 and F20, and the user saw nothing, because the console schematic maps those five to PMOD1_IO0, IO2, IO4, IO1 and IO3 on the PMOD1 header and this carrier has no FPGA-driven LED at all, its one status LED being wired to the FPGA's dedicated READY and DONE configuration nets. The readout is therefore the FPGA's UART on ball U15, the channel `evidence/uart-live-capture.bin` already proved, and `tools/decode-clock-smoke.py` measures it; `evidence/clock-smoke-readout.txt` holds this cycle's capture, its decode and a sample of the lines. What the board then showed is that the clock chain runs. Both PLLs lock, `lock=11` on every one of about five thousand lines, which puts two further operating points on the charge-pump model this project extended, and `sys_clk`, `clk27` and `hclk` all toggle, which means `pll_hdmi`'s 371.25 MHz does reach the CLKDIV and the CLKDIV does divide it, even though nextpnr reached that lane only through general routing after refusing the dedicated path. That is a measured answer to the gap `clocking_e2e.py` records as unbuildable and it bears on the display question directly, because the chain that was suspected is not the broken one. Two things are not settled and are recorded rather than smoothed over. The user test could not be run as designed, because the observable it was written for does not exist on this carrier; the user's one hardware report, an HDMI flicker at load, is the reconfiguration being seen and not a clock result, and the clock result is an agent-run device-side capture, which is not user acceptance. And the counters' top flops are being trimmed by synthesis, `cnt_sys` declared 25 bits with only bit 24 read coming back as 24 flops, so the absolute rates read out for `clk27` and `hclk` are ambiguous by a factor of two between the designed 27.00 and 74.25 MHz and their doubles; `(* keep *)` did not prevent it, `sys_clk` is not ambiguous because the line period and a clean 115200 decode agree on 49.98 MHz, and the desktop core's own keylink answering at a baud derived from `pll_nes` argues the PLLs are right, but that is inference and is labelled as such. The required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed `core.md` was not changed and `core-log.md` was, and validated this entry as number 6 of the active log with a conforming header, six sections in canonical order, prose in Outcome and Next Steps, and an allowed Status set. No part of this repository, TinyTang or Tang-Phosphor was found to use intellectual property beyond what `THIRD_PARTY.md` already records.

#### Next Steps:

Settle the counter indexing before anything else, because it is one small change and it decides what the result means. Reporting two bits of each counter in the message, `cnt_sys[24]` alongside `cnt_sys[23]` and so on, makes the design state its own indexing, since a measured 2:1 ratio between a bit and its neighbour confirms 27.00 and 74.25 MHz and closes the cycle while a 1:1 ratio would mean the PLLs are doubled, which would itself explain the dark display and redirect the work; `(* keep *)` on the counters did not stop the trim, so the fix is that plus a second bit per counter, or a counter whose top bit is genuinely needed. Once the rates are settled, the CLKDIV result is the thread to pull: this cycle has shown that `pll_hdmi`'s output reaches the divider and divides, so the two candidates entry 5 left open, timing on `hclk5` and the bitstream's option preamble, remain the live ones, and the `hclk5` question can now be attacked with a design that gives nextpnr something it can report a maximum frequency for on that net. The design, `scripts/build-clock-smoke.sh` and `tools/decode-clock-smoke.py` are the instruments for that and should be kept working. The board was left loaded with `clock-smoke` in SRAM and needs a power cycle or the reconfig button to return to its flash core.

#### Files Modified:

- fpga/clock-smoke/clock_smoke.v
- fpga/clock-smoke/clock_smoke.cst
- fpga/clock-smoke/clock_smoke.sdc
- scripts/build-clock-smoke.sh
- tools/decode-clock-smoke.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: FAIL

---

## 7 COMMIT Unreleased 2026-10-08T22:05:01-07:00

#### Coming From:

Unreleased 6a8fd4f

#### Purpose:

Settle the factor-of-two ambiguity entry 6 left in the `clk27` and `hclk` rates by making the readout measure cycles rather than report bits.

#### Outcome:

Entry 6 left the rates of `clk27` and `hclk` ambiguous by a factor of two, and this cycle was to settle them by measuring cycles instead of reading bits, which it did. The readout no longer reports a counter bit at all: it counts the edges of bit 12 of `cnt_27` and `cnt_hclk`, each crossed into the `sys_clk` domain as a single bit and counted there, so what is delivered is a count of 8192-cycle units and the reader never has to know which bit was read. That distinction is what entry 6 could not make and the answer needed, because a flop count does not reveal a bit's position. Two faults of this cycle's own making were found and fixed before the result could be trusted. The decoder divided by 2^12 where bit 12 toggles every 2^13 cycles, which halved every frequency and made this cycle's first reading look like the designed values; it was caught against a hand calculation on a single line, where `c27` advances 0x1148 = 4424 per line and 4424 x 8192 / 0.6737 s = 53.8 MHz. And the readout had been transmitting about 9300 bytes per second into a link that carries only about 100 to 170, which is why entry 6's last capture arrived degraded at 307 B/s and the next arrived as nothing at all; the one-wire path forwards the FPGA UART through the BL616, and swamping that bridge presents as silence rather than as errors. A power cycle cleared it, and what proved the link rather than the design was `evidence/uart-message-compressed.fs`, the Apicula example that produced the 17 KB capture, silent before the cycle and talking after it. The cadence was then slowed to 2^25 `sys_clk` cycles, 671.08864 ms, to sit inside the channel. What the board reports is that both PLLs run at exactly twice their configured rate. `clk27` is 53.7911 MHz against a configured 27.0000 and `hclk` 147.9306 MHz against 74.2500; the ratios to `sys_clk` are 1.0800 and 2.9700 where the design says 0.5400 and 1.4850, exactly double to about three parts in a thousand, and both `pll_27` and `pll_hdmi` report LOCK on all 105 lines. Two independent references agree on the scale, `sys_clk` being 49.81 MHz from the line cadence and 49.997 MHz from the design's own UART baud, an agreement of 0.377 per cent. The counter indices are not inferred this time: `cnt_27` is 24 flops for a declared `[23:0]` register and `cnt_hclk` 25 for `[24:0]`, so no bit was dropped or shifted and bit 12 is bit 12 by construction. The consequence is that `hclk5` is 742.5 MHz rather than 371.25, and since the desktop core's own `pll_27` carries this configuration, a pixel clock of 148.5 MHz where the monitor expects 74.25 is a concrete candidate for the display failure that entry 5 could only narrow. The doubling is value-dependent rather than general: `pll_hdmi`, MDIV 55 and ODIV 4, behaves exactly as declared, so the fault sits at `pll_27`, MDIV 27 and ODIV 50, and the desktop core's `pll_nes` at MDIV 40 is left alone, which is why its keylink still answers and why that evidence never contradicted this. That narrows a claim entry 2 recorded: the four PLL attributes it compared are the charge-pump set, `FLDCOUNT`, `KVCO`, `A_ICP_SEL` and `A_LPF_RES_SEL`, and the dividers were never compared, which is the gap this walked through. The required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed `core.md` was not changed and `core-log.md` was, and validated this entry as number 7 of the active log with a conforming header, six sections in canonical order, prose in Outcome and Next Steps, and an allowed Status set. No part of this repository, TinyTang or Tang-Phosphor was found to use intellectual property beyond what `THIRD_PARTY.md` already records.

#### Next Steps:

Settle the divider question without the board, since the next step needs no hardware and the board is presently running `clock-smoke` in SRAM. Unpacking this project's desktop core and the vendor's `TinyTang/build/desktop/source/impl/pnr/desktop.fs` with the fork's `gowin_unpack` puts the three PLL instances side by side; comparing the divider parameters, `MDIV_SEL` and `ODIV0_SEL` above all, against the values the netlist asked for names the fault outright, and comparing them against each other says whether `gowin_pack` derives the dividers wrongly or writes them wrongly. This project's `.fs` is not committed, only its `.bin`, but the conversion is one to one so the text form reconstructs from it, as `evidence/clock-smoke-readout.txt` records for the reconstruction already made. The prediction to test is that `pll_27`'s dividers differ from the vendor's while `pll_hdmi`'s match, because that is the pattern the board measured; if they do differ the fix belongs in the fork's packer and the display follows from it, and if they match then the divider model is right and the error is in what the packer is handed. Nothing in this needs the board.

#### Files Modified:

- fpga/clock-smoke/clock_smoke.v
- tools/decode-clock-smoke.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: FAIL

---

## 8 COMMIT Unreleased 2026-10-08T22:30:58-07:00

#### Coming From:

Unreleased e80a9a8

#### Purpose:

Separate the two things that were varying at once in entry 7's factor of two, the bitstream and the state the board was in, by power-cycling before every run.

#### Outcome:

The factor of two entry 7 recorded was not a property of the design, and this cycle separated the two things that had been varying at once. The instrument was corrected first: `tools/decode-clock-smoke.py` averaged edge deltas without normalising by the line-counter step, so samples spanning two line periods read as a doubled clock, which is what the earlier control run's `min 2211, max 4440` actually was; only deltas of exactly one line period are used now. The packer was then checked directly, because a nondeterministic packer would have explained everything: three packs of the same P&R JSON and the file that was loaded are byte-identical at `sha256 78227dd6...`, so the bitstream is not the variable. The user then proposed and ran the decisive protocol, a power cycle before every load, and it exposed something that had been corrupting readings all session: an SRAM load without a power cycle does not take effect. The three runs made without one fit a strict one-behind pattern, baseline loaded and read as baseline, variant B loaded and read as baseline, baseline loaded and read as variant B, and it had been invisible because the two bitstreams emit character-identical text. With a power cycle before each load the measurement reproduces. The two bitstreams differ by one `defparam`, `pll_27.ODIV0_SEL = 50` against `100`, and four rebooted runs gave two clean pairs, `50` twice at `1.0800 x sys_clk` with 4423.7 bit-12 edges per line and `100` twice at `0.5400 x sys_clk` with 2211.8, `hclk` following at 2.9700 and 1.4850 and `lock=11` on every line of every run. So the requested divider value is effectively halved: 50 divides by 25 and puts the 1350 MHz VCO at 54 MHz, 100 divides by 50 and puts it at the designed 27 MHz. The halving is not uniform, `pll_hdmi` carrying `ODIV0_SEL = 4` and measuring correct in those same runs, so where the boundary lies is not known. The consequence that matters is that the desktop core's own `pll_27` carries `ODIV0_SEL = 50`, which makes its `clk27` 54 MHz and its pixel clock 148.5 MHz where the monitor expects 74.25, and that one number is now the next thing to test; the four captures and this reasoning are in `evidence/clock-smoke-divider-runs.txt`. The required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed `core.md` was not changed and `core-log.md` was, and validated this entry as number 8 of the active log with a conforming header, six sections in canonical order, prose in Outcome and Next Steps, and an allowed Status set. No part of this repository, TinyTang or Tang-Phosphor was found to use intellectual property beyond what `THIRD_PARTY.md` already records.

#### Next Steps:

Reproduce the divider result before acting on it, since the one-behind behaviour shows how easily a measurement here can be of the wrong thing: six power-cycled runs of one bitstream, all of which must read the same ratio. Once that holds, change `pll_27`'s `ODIV0_SEL` from 50 to 100 in the desktop core, build it with the project's own scripts, load it after a power cycle, and look at the display, which is the observable this whole line of work has been missing. `pll_hdmi` should be left alone, having measured correct in these runs. If the display comes up then the same change belongs upstream in the fork's packer rather than in the RTL, because halving the requested divider is a scaling fault that every PLL this project builds inherits. The board is left running variant B in SRAM and a power cycle returns it to its flash core.

#### Files Modified:

- tools/decode-clock-smoke.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 9 COMMIT Unreleased 2026-10-08T22:41:42-07:00

#### Coming From:

Unreleased 1846415

#### Purpose:

Establish that entry 8's divider result reproduces before acting on it, by running one bitstream six times with a power cycle before every load, all six required to agree.

#### Outcome:

The divider result reproduces. Six power-cycled runs of variant B, the bitstream whose only difference from the committed design is `defparam pll_27.ODIV0_SEL = 100`, all measured `0.5400 x sys_clk` with 2211.8 bit-12 edges per line, `hclk` following at `1.4850 x sys_clk` and `lock=11` on every line of every run; 43 samples were used per run with none skipped, so every step in the line counter was exactly one period. The six captures are byte-identical, `sha256 44732b80...`, 2156 bytes and 44 lines each with `n` from 0x0001 to 0x002c, and that is expected rather than suspicious because the design resets to the same state on every configuration while the capture opens before the first line arrives. It is also exactly what a wedged buffer looks like, so it was checked rather than assumed: the same running design captured for sixty seconds returned 122 lines rather than the same 44, so the data is live and the six runs are six real measurements. That check then exposed a second anomaly, recorded and not resolved. The sixty-second capture runs at 2.02 lines per second where the six thirty-second runs ran at 1.43, with `d(c27)` per line constant at 2211.8 in both, which is `0.5400 x 2^25` clk27 cycles per line. If a line really is 2^25 `sys_clk` cycles then the line rate cannot change, so either the cadence is not 2^25 cycles in the implementation or the line rate is not stable, and which of the two is not known. It does not touch the ratio result, which compares two bitstreams measured under the same conditions, but the absolute frequencies rest on assumptions that this leaves unverified: the UART anchor assumes the design's baud is exactly 115200 and the ratio assumes the cadence is exactly 2^25 cycles. The drift also fits the load and configuration trouble entry 8 found, since the board appears to change behaviour while left running. One framing in entry 7 is corrected here: the 3.9 per cent disagreement it noted between the cadence and UART anchors is an artefact of dividing the whole capture window by the number of line intervals when the window opens before the first line arrives, and is not a discrepancy in the design. The consequence for the project is that `pll_27`'s `ODIV0_SEL` is now worth changing in the desktop core itself, where the display is the observable. The required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed `core.md` was not changed and `core-log.md` was, and validated this entry as number 9 of the active log with a conforming header, six sections in canonical order, prose in Outcome and Next Steps, and an allowed Status set. No part of this repository, TinyTang or Tang-Phosphor was found to use intellectual property beyond what `THIRD_PARTY.md` already records.

#### Next Steps:

Change `pll_27`'s `ODIV0_SEL` from 50 to 100 in the desktop core, build it with the project's own scripts, load it after a power cycle rather than on top of whatever is running, and look at the display, which is the observable this line of work has been missing and which needs no absolute frequency to be meaningful. `pll_hdmi` should be left alone, having measured correct in these runs, and `pll_nes` likewise, since its keylink still answers. If the display comes up then the same change belongs upstream in the fork's packer rather than in the RTL, because halving the requested divider is a scaling fault every PLL this project builds inherits, and the boundary of the halving is still unknown after `pll_hdmi` measured correct at `ODIV0_SEL = 4`. The line-rate instability is worth a cycle of its own before any absolute frequency is quoted as fact, and the decoder should take its line period from the first to the last line rather than from the whole capture window. Evidence for this cycle is in `evidence/clock-smoke-six-runs.txt`; the board is left running variant B in SRAM and a power cycle returns it to its flash core.

#### Files Modified:

None.

#### Status:

- Build: N/A
- Deployment: PASS
- User Test: NOT RUN

---

## 10 COMMIT Unreleased 2026-10-08T23:00:03-07:00

#### Coming From:

Unreleased 028d3bf

#### Purpose:

Test whether the divider scaling found in clock-smoke transfers to the desktop core, where the display is the observable the line of work has been missing.

#### Outcome:

The fix does not transfer, and the attempt got further than the attempt itself. The design tree was reconstructed from the pinned nestang commit with the portability patch applied, and the only change made to the design was `defparam PLL_inst.ODIV0_SEL = 50` to `100` in `src/pll/gowin_pll_27.v`, verified by `git diff` on that file to be the whole of it. Synthesis passed at 8,585 cells with 3 PLL, 1 CLKDIV, 3 OSER10 and 4 ELVDS_OBUF, matching this project's recorded netlist. Place and route then failed twice before it passed, and both failures were in `scripts/pnr-desktop.sh` rather than in the design or the tools. It calls bare `nextpnr-himbaechel` from PATH, and sourcing the oss-cad suite puts the suite's build first, the one whose GW5AST-138C has no placeable PLL bel, so the script's "known wall" message is at least partly stale tooling rather than a limit of the open flow. And even the fork's nextpnr cannot place three PLLs unconstrained: the chipdb knows all twelve `PLL_{L,R,B}[n]` sites but the placer's free choice does not find three it considers valid, which is the same lesson clock-smoke already recorded. Pinning them to the sites the vendor's own place-and-route used, `PLL_L[1]` at X0Y45, `PLL_L[3]` at X1Y81 and `PLL_B[1]` at X32Y108, let the run complete with `Program finished normally`, 0 errors and 957 routing warnings against the 947 the design's own successful run emitted. Packing then failed on the change itself: `gowin_pack` raised that the 11010100110000.0MHz frequency is outside the permissible range of 3 to 800 MHz, a garbage figure out of a 1350 MHz VCO divided by an ODIV of 100. So the packer decodes `ODIV0_SEL` rather than using it arithmetically, and 100 is not a value it can interpret in this PLL's attribute set, while clock-smoke's `pll_27` accepted the same request and ran at the designed 27 MHz. The difference between the two is the fields around it, the desktop IP setting `ODIV1_SEL` to `ODIV6_SEL` to 8 with those outputs disabled where clock-smoke sets them to 0, so the effective halving is not a clean write-twice-the-value encoding and the one-number fix is not the fix. A second script defect was found the same way: the fork's nextpnr needs the suite environment sourced rather than `PYTHONHOME` set alone, or its embedded interpreter dies on `encodings`, and `SYNTH_DESKTOP_NO_ENV=1` must be set or the script re-sources the suite and clobbers the fork on PATH, which is what produced a spurious "Invalid constraint" on a `PLL_L[1]` macro that the fork accepts. The board was not touched this cycle, nothing was loaded, and it still runs variant B in SRAM. The required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed `core.md` was not changed and `core-log.md` was, and validated this entry as number 10 of the active log with a conforming header, six sections in canonical order, prose in Outcome and Next Steps, and an allowed Status set. No part of this repository, TinyTang or Tang-Phosphor was found to use intellectual property beyond what `THIRD_PARTY.md` already records.

#### Next Steps:

Map which `ODIV0_SEL` values the packer actually accepts and what the decode is doing, off-board and on the desktop PLL IP rather than on clock-smoke's, since the rejection is a decode failure rather than a range check on the divider and the effective halving is not a simple scaling. In parallel, fix `scripts/pnr-desktop.sh`: it should select the fork toolchain explicitly instead of taking whatever `nextpnr-himbaechel` is first on PATH, should set `SYNTH_DESKTOP_NO_ENV` and source the suite for the embedded interpreter, and should carry the three `INS_LOC` lines, because the desktop core cannot be placed without them and the current script silently uses a nextpnr that cannot place a PLL at all. That script fix is worth doing even before the divider question is settled, since it is the difference between a build that runs and one that stops at a wall that is no longer there. Only once a packable configuration exists is the display testable, and the board should be left alone until then; `evidence/desktop-odiv100-attempt.txt` records the run.

#### Files Modified:

None.

#### Status:

- Build: FAIL
- Deployment: NOT RUN
- User Test: NOT RUN

---

## 11 COMMIT Unreleased 2026-10-09T00:33:58-07:00

#### Coming From:

Unreleased 6ac21dd

#### Purpose:

Make the desktop core pack and load with the divider changed, so that the display becomes the observable, and find out why it has never come up.

#### Outcome:

The desktop core packs now, and the display is still dark, but the day removed most of the field and named one real defect. Packing failed for a reason no one had looked for: `read_slang` keeps a Verilog *string* parameter as a bit vector where `read_verilog` keeps it a string, so this flow's netlist reached `gowin_pack` carrying the ASCII of "50" and "TRUE" instead of those strings -- `FCLKIN = 0011010100110000` against clock-smoke's `FCLKIN = 50` for the same `defparam`. The packer wants the strings, and `float("0011010100110000")` is 1.1e13, which is the exception text this project had already seen, `11010100110000.0MHz`, leading zeros stripped. The diagnosis is exact because the exception was its own fingerprint. The fix is in `scripts/synth-desktop.sh` and its scope is load-bearing: a first attempt tested "does this value decode to printable text" over the whole netlist and would have converted 536 parameters including LUT `INIT` values such as `'_3'`, silently corrupting the design's lookup tables; it did not run, which was luck rather than design. Scoped to PLL-family cells it is safe by construction, because a PLL's numeric fields are 32-bit and a realistic divider leaves its high bytes 0x00, and it restores 129 parameters, 43 for each of three PLLs, matching the string set the cell library declares. Gowin's own IP record settled the ODIV question in the same pass: `src/pll/gowin_pll_27.ipc` says `ClkinClockFrequency=50`, `Clkout0VCODivideFactorStatic=50` and `Clkout0ExpectedFrequency=27`, so the requested divider means divide-by-50 and our 54 MHz is a packer fault, not a design one; a sweep of `ODIV0_SEL` over 4, 8, 16, 32, 64 and 100 showed the field occupying 48 bits in six groups of eight at a 1,584-bit stride, six tiles of the PLL site, and showed it is not a positional binary divide. The packer's refusal of 100 on the desktop IP was also not about the divider: `get_pll_attrvals` calls `float()` on `A_FCLKIN`, which is the cell's `FCLKIN` verbatim, and the front end had made that the ASCII of "50". A second, real defect was found and fixed in the fork: `GW5AST_138C.get_out_iologic_attrs` added the fast-clock selection and the OSER16 aux attributes but never removed `LSRIMUX_0`, which belongs to the input half against the output's `LSROMUX`, so every output serialiser was spending one fuse the vendor does not -- which is precisely the `LSRIMUX_0` difference this project recorded once and never explained, at the TMDS tiles, which are OSER10s. Re-packing moved 14 bits of 35.7 million, every cluster `0 -> 1`, in the TMDS region. On hardware the desktop core loaded three times, each after a power cycle, and the display stayed dark every time; on a better monitor that distinguishes the two, it reported "no signal" rather than "out of range", which means no TMDS clock at all rather than timings it cannot use. That, with the rest of the day, rules out the pixel clock, which was the working hypothesis the previous three cycles were built on: the committed build runs it at 148.5 MHz and this one at 74.25, and both give no signal. It also rules out the placement, which matches the vendor's at every clock and serialiser cell, and the CLKDIV and its lane, which clock-smoke measured at 74.2452 MHz from that exact site. What the observation exposes is a gap in the method rather than in the design: the desktop core has no readout, so its clocks cannot be measured and every question about them has to be asked by loading it and looking at a dark screen. The required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed `core.md` was not changed and `core-log.md` was, and validated this entry as number 11 of the active log with a conforming header, six sections in canonical order, prose in Outcome and Next Steps, and an allowed Status set. No part of this repository, TinyTang or Tang-Phosphor was found to use intellectual property beyond what `THIRD_PARTY.md` already records.

#### Next Steps:

Put the display chain into the design that can talk. clock-smoke reports over the UART this project has already proven on the board, and the desktop core reports nothing, so adding one `OSER10`, one `ELVDS_OBUF` and a TMDS clock lane to clock-smoke makes the serialiser path measurable: if a monitor syncs to that design, the serialiser works and the desktop core's fault is elsewhere, and if it does not, the fault is localised to a design whose clocks are known good rather than one that can only be stared at. Repair `scripts/pnr-desktop.sh` in the same cycle, since it silently uses the suite's nextpnr, which has no placeable PLL bel, and needs `SYNTH_DESKTOP_NO_ENV`, the suite environment sourced for the embedded interpreter, and the three `INS_LOC` PLL pins; it is the difference between a build that runs and one that stops at a wall that is no longer there. The divider scaling itself remains unfixed and `ODIV0_SEL = 100` remains a workaround written into the RTL, so the next cycle that touches the packer should correct the encoding rather than compensate for it. `evidence/desktop-display-cycle.txt` records all of the above, including the negative results, so that none of them has to be re-derived.

#### Files Modified:

- scripts/synth-desktop.sh

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: FAIL

---

## 12 COMMIT Unreleased 2026-10-09T01:09:09-07:00

#### Coming From:

Unreleased 9c25bb5

#### Purpose:

Find out why the desktop core's HDMI display has never come up, now that the core is known to load and run on the board.

#### Outcome:

The display cannot come up, and the reason is the device's clock routing rather than the core, which the two-wire test finally let the project observe with confidence. That cycle ran the vendor's core as a live control at the boot script's prompt and then replaced it with ours through `tangload` on the card's SD image; the load reported `core loaded`, the core answered `core 84 answering on UART1 at 2000000 baud` after a full SRAM erase, and the console returned to its prompt with no hang, while the display stayed dark and the monitor again reported "no signal" rather than a picture it cannot use. That rules out the overlay as the confound, which every earlier dark-screen observation had been unable to exclude, and it separates the two halves of the failure: the core runs, and only the display path is dead. The `.bin` path was eliminated in the same pass, because every earlier load had used the `.fs` over JTAG and two-wire is the first time this project's binary reaches `tangload`: `tools/fs-to-bin.py` reproduces the vendor's own `.bin` from the vendor's own `.fs` byte for byte (`c8406c7f8573097b98de3923def1693ffdd9f8fe304e224775249fc5f0e9c592`, `cmp` clean), `fpga_program` in `ports/bl616/tang_jtag_programmer.c` shifts file bytes straight to TDI without parsing any framing, and the vendor's 96-bit prologue that apicula omits is shown harmless because clock-smoke, which ran on this board, carries apicula's framing exactly. Two routes were then closed so they are not re-walked: `gowin_unpack` cannot decode this device's PLL attribute table at all, reporting `Unknown attr name for table: PLL code:211` against the vendor's bitstream as well as ours, so the PLL configuration cannot be read back from a bitstream; and the output-buffer count difference between the two unpacks is an artifact, because the HDMI outputs are `ELVDS_OBUF`, which is emulated LVDS built from single-ended halves and decodes as `OBUF_A`/`OBUF_B` pairs rather than a primitive of its own. What the P&R log actually contains is 947 `Failed to route ... using dedicated routing` lines, breaking down as `clk` 943, `hclk5` 3 and `clk27` 1, and the three `hclk5` failures are the whole finding: `hclk5` is the 371.25 MHz TMDS bit clock and its only loads are the three OSER10s at the TMDS data pads, `X181Y102`, `X181Y100` and `X181Y57`, so the serialisers never receive a fast clock and no valid TMDS leaves the part. Three clocks of this design cannot reach their loads on dedicated routing because the architecture offers a single global clock buffer, `BUFG: 1/1`, against four clocks, leaving three of them on general fabric; general routing is good enough to count edges, which is why clock-smoke's 74.2452 MHz reading was both true and insufficient, and it cannot clock a serialiser at 371.25 MHz. The clock model that does exist is real and current: the GW5AST-138C database regenerated from the local Gowin install carries `hclk_pips` 171, `io2hclk` 6, `hclk_div2` 6 and `HAS_5A_HCLK` where the published one has zero of each, and nextpnr was built ten minutes after that database so it embeds it, and the SDC is applied, since the log shows all three clocks being constrained. So the regeneration step this project had queued is already done and the remaining gap is the network's coverage and the global buffer count, not the tables' absence. Nothing in the core is implicated: the PLL configuration is correct, reproduced 2/2 with power cycles, at 26.9982 MHz for `pll_27` and 371.25 MHz for `pll_hdmi`; the placement matches the vendor's at every clock and serialiser cell; the pad configuration matches the vendor's tile by tile at all four TMDS pins; and the TMDS tiles' serialiser attributes match the vendor's apart from the `LSRIMUX_0` fixed in the previous cycle. The required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed `core.md` was not changed and that this entry is the only `.ai` change, and validated it as number 12 of the active log with a conforming four-field header, six sections in canonical order, prose in Outcome and Next Steps, an allowed Status set, and no rewrite of settled history. No part of this repository, TinyTang or Tang-Phosphor was found to use intellectual property beyond what `THIRD_PARTY.md` already records.

#### Next Steps:

Extend the clock model for GW5AST-138C rather than the core, because the remaining gap is data about the device and not logic in the design: raise the global clock buffer count beyond the single `BUFG` the architecture currently admits and widen `hclk_pips` so the path from a PLL output to an output serialiser's `FCLKA` exists, both regenerated from the local Gowin 1.9.11.03 install that produced the current database, and then re-place the desktop core and check that the `hclk5` dedicated-routing failures are gone before packing and loading anything. Which of the two is load-bearing is not yet known and should be settled by the same log, since `BUFG: 1/1` starving three clocks and a sparse `hclk_pips` network both predict the observed failures and the fix for each is different. `evidence/desktop-clock-routing.txt` records the failures net by net and the database counts, and `evidence/desktop-2wire-cycle.txt` records the two-wire load, so that neither the dark-screen result nor the exclusions above has to be re-derived. The two dead ends recorded above, unpacked PLL attributes and the output-buffer count, should not be re-walked on this device.

#### Files Modified:

None.

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: FAIL

---

## 13 COMMIT Unreleased 2026-10-09T01:22:58-07:00

#### Coming From:

Unreleased a8fe80f

#### Purpose:

Determine whether apicula's HCLK clock model for GW5AST-138C is missing the data the desktop core's display clock needs, and correct the mechanism entry 12 asserted.

#### Outcome:

This cycle went looking for missing HCLK data and found the clock model largely complete, so it ends with four refuted candidates and one correction rather than a fix. The model is real and present: the database regenerated from the local Gowin install carries `hclk_pips` 171, `io2hclk` 6, `hclk_div2` 6 and `HAS_5A_HCLK`, and nextpnr was built after it. The device has exactly six HCLK blocks, at `(27,0)`, `(27,181)`, `(81,0)`, `(81,181)`, `(108,64)` and `(108,117)`, and `gw5_hclk_idx` is a pure table lookup over those six returning `-1` everywhere else; the vendor's own `.fse` carries table-48 wiring only inside the block tiles, 159 to 165 entries each, against 0 on every interior tile tested on rows 81, 108 and 57. So there is no die-wide pip grid and the predicate that skips interior tiles loses nothing, which refutes the first candidate, missing interior spines, because there are none to miss. The HCLK lines are produced as `add_node` nodes rather than as pips, so searching `hclk_pips` for them returns nothing by construction, which refutes a second candidate that was an error of method rather than of device. `make_hclk_pip` registers both endpoints of every pip as nodes under the same name the producer uses, so the block at `(81,181)` and the IOLOGIC at `(102,181)` are joined by `create_global_nodes` under `HCLK3_HCLK30` and become one routable node, which refutes a third candidate about unjoined wires and a fourth about switch matrices being built only at the 171 pip sites, since the intervening tiles do not need one. The FCLK hooks are present at all three serialisers, `FCLKA <- HCLK30..33` at `(102,181)` and `(100,181)` and `FCLKA <- HCLK10..13` at `(57,181)`. The correction this entry owes is that entry 12 named the single `BUFG` as the cause of the clock failures, which its own evidence file already declined to establish and which the router's line `'hclk5' net was routed using global resources partially` contradicts, since a global path plainly existed; that mechanism is superseded and the mechanism is recorded as not established, with what survives being only that `hclk5` fails dedicated routing to all three serialisers. The one live lead is measured rather than inferred: `_gw5_hclk_logic_entry_wires` is `("CLK0", "CLK1", "CLK2", "LSR2")`, three tile clock wires and one ordinary fabric wire, and the comment on it, measured at `P1.T27` from the vendor's own bitstreams, records that a clock reaches lane 3 over fabric and never over the global plane; two of this design's three TMDS data serialisers are on lane 3 and the PLL at `X1Y81` is adjacent to block 2 at `(81,0)` and so feeds lane 2, which predicts both the symptom and the router's wording. It is deliberately not asserted, because the vendor's build works at the same three serialiser sites with the same forced PLL placement, so either the reading of that comment is incomplete or the vendor flow has something this one lacks. All four refuted candidates failed the same way, a real number read out of the wrong structure, since `hclk_pips`, `db.nodes`, the wire namespace and nextpnr's global node list each hold a different part of the HCLK data, and `evidence/desktop-clock-routing.txt` now records the refutations, the lane-3 lead and that method note so none of them has to be re-derived. The required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed `core.md` was not changed and that this entry is the only `.ai` change, and validated it as number 13 of the active log with a conforming four-field header, six sections in canonical order, prose in Outcome and Next Steps, an allowed Status set, and no rewrite of settled history. No part of this repository, TinyTang or Tang-Phosphor was found to use intellectual property beyond what `THIRD_PARTY.md` already records.

#### Next Steps:

Compare the HCLK mux state decoded from the vendor's bitstream against this build's at the three serialiser FCLK inputs, which is like-for-like because both builds place those serialisers at the same three sites: `gowin_unpack` already reads `db.hclk_pips` as the block's configured and fuse-bearing mux state, so the comparison is available offline with no power cycle and needs no hardware. It either confirms the lane-3 reading or kills it, and until one of those happens the mechanism stays unestablished and no fix should be written against it. The `BUFG` mechanism entry 12 asserted is superseded by this entry and is not to be built on.

#### Files Modified:

None.

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: N/A

---

## 14 COMMIT Unreleased 2026-10-09T01:26:09-07:00

#### Coming From:

Unreleased a0ec7cf

#### Purpose:

Run the comparison entry 13 named as its next step -- the HCLK mux state at the three serialiser FCLK inputs, decoded from the vendor's bitstream and from this build's -- and find out why the TMDS serialisers never receive a fast clock.

#### Outcome:

The comparison was run and it localises the dark display completely: this build's bitstream has no `FCLK` connection at any of its three TMDS serialisers. Both bitstreams were unpacked with the same tool for the same device, and at the same three sites the vendor's carries `.FCLK(R58C182_HCLK0)`, `.FCLK(R101C182_HCLK0)` and `.FCLK(R103C182_HCLK0)` while this build's carries only `.PCLK`, on all three. The design itself does connect it, which is what makes the absence a packing result rather than a design one: `evidence/desktop-core-netlist.json.gz` shows all three `OSER10` cells in `nestang_top` with `FCLK: [2025]`, one shared net, alongside `PCLK: [40]`. The chain is therefore complete and each link is evidenced separately. The design connects all three serialiser `FCLK` inputs to one net, `hclk5`; `hclk5` is the 371.25 MHz TMDS bit clock and is generated correctly, reproduced 2/2 with power cycles; nextpnr cannot route it to `FCLKA` at any of the three serialisers, which is 3 of the 947 dedicated-routing failures, and it records `'hclk5' net was routed using global resources partially`; so the connection never reaches the bitstream; the vendor's bitstream has it, from a Gowin build whose display works; and a serialiser with `FCLK` but no bit clock cannot shift a bit, so no TMDS leaves the part and the sink never locks. `PCLK` being present is what makes the rest of the core work, since the pixel-side logic is clocked and the UART answers at 2 Mbaud, which is exactly why the failure looked like a display fault and not a clocking one. Two earlier leads are retired by this result rather than left standing: the lane-3 finding is not the cause, because the vendor connects `FCLK` at the same three sites and so lane 3 is demonstrably reachable; and the chipdb is not implicated, because the arcs exist in it, `FCLKA <- HCLK30..33` at `(102,181)` and `(100,181)` and `FCLKA <- HCLK10..13` at `(57,181)`, and those sites are in `hclk_pips`, so `create_hclk_switch_matrix` runs for them and creates the pip -- nextpnr has the edge and still cannot route to it. What is left is a single defect: the route from a PLL output through the inter-HCLK network to an IOLOGIC's `FCLK` is not achievable in this nextpnr build for this device even though the graph contains the arcs, which is a routing or model defect rather than missing data. The method that found it is the one the packer's own comments had already used twice, comparing this build's bitstream against Gowin's at a site where both agree and looking for what is absent rather than what differs, and it worked here because the pad configuration and the TMDS serialiser attributes had already passed that same comparison, which put the remaining gap one layer up in the routing. `evidence/desktop-clock-routing.txt` now carries the port maps from both unpacks, the six-link chain and what this result retires. The required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed `core.md` was not changed and that this entry is the only `.ai` change, and validated it as number 14 of the active log with a conforming four-field header, six sections in canonical order, prose in Outcome and Next Steps, an allowed Status set, and no rewrite of settled history. No part of this repository, TinyTang or Tang-Phosphor was found to use intellectual property beyond what `THIRD_PARTY.md` already records.

#### Next Steps:

Scope the routing defect before writing anything against it, since the fix belongs in nextpnr's Gowin arch or router rather than in the core, the packer or the database, and the shape of it is not yet known: establish whether the PLL output reaches the serialisers' lane at all through the inter-HCLK wires, or whether the failure is in the last hop that `create_hclk_switch_matrix` does create, and settle that from nextpnr's own routing state rather than by further inference, because this cycle's predecessor and this one both show that reads of these tables are easy to make against the wrong structure. The desktop core needs no change for this and should not be rebuilt until the route works. Entry 13's next step is discharged by this entry and entry 12's `BUFG` mechanism remains superseded.

#### Files Modified:

None.

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: N/A

---

## 15 COMMIT Unreleased 2026-10-09T01:32:38-07:00

#### Coming From:

Unreleased 36fe909

#### Purpose:

Bring `README.md` and `FINDINGS.md` in line with the project's actual state, because both still described a wall the project passed and would have sent the next agent back into it.

#### Outcome:

The documentation now matches the work, which it had stopped doing in the one way that matters for a handoff. `README.md`'s status list claimed the desktop core "cannot place a PLL" because "`GW5AST-138C` has no clock model in the open database" with "`pad_pll`/`hclk_pips` empty"; the database regenerated from the local Gowin install carries `hclk_pips` 171, `io2hclk` 6, `hclk_div2` 6 and `HAS_5A_HCLK`, the PLLs place, and the design places, routes, packs and loads — so that item is corrected and split into the part that works and the part that does not, the latter being the missing `FCLK` route rather than a missing clock model. Its `.fs` → `.bin` item was unticked and is now ticked, since `tools/fs-to-bin.py` reproduces Gowin's own `.bin` from Gowin's own `.fs` byte for byte and the result loaded through `tangload` on the board. The README also claimed `oss-cad-suite` carries a usable `GW5AST-138C` database, which contradicts `TOOLCHAIN.md` and is false, so the reproduce section now says the database is built locally and points at the recorded hash. Its "no project core has been built this way yet" and "binary format gap" entries in the not-verified list are retired and replaced with what is genuinely unproven — the display, the OLED and audio paths, and timing at pixel rates — and its verified list gained the desktop core's two loads and the exercised `.bin` path. Its core-location line now says `fpga/desktop` lives in the TinyTang tree and that this repository's `fpga/` holds `clock-smoke`, its layout gained the scripts and tools it was missing, and its `pnr-desktop.sh` line no longer says the script stops at the PLL. `FINDINGS.md` changed in five places: section 4's heading called the binary gap the main obstacle and now records it closed, with the validation and the one real encoding difference, the vendor's 96-bit prologue that apicula omits and that clock-smoke's successful run shows is harmless; section 6's list of what is unproven is replaced, since the clock tree and the TMDS path are no longer untested and the display's cause is located; section 7's next steps are replaced with the two that remain; section 8's provenance note said the published database was in use and that using it "needs nothing", and now records that the database in use is generated from the vendor install at `/home/vash/tools/gowin-1.9.11.03`, why the published one cannot drive this part, and the hash a successor can check against; and section 9's place-and-route paragraph, which recorded the wall as current, now records that it is gone and that the display fails for one located reason. Four links written during this cycle pointed outside the repository and were corrected before commit. The required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed `core.md` was not changed and that this entry is the only `.ai` change, and validated it as number 15 of the active log with a conforming four-field header, six sections in canonical order, prose in Outcome and Next Steps, an allowed Status set, and no rewrite of settled history. No part of this repository, TinyTang or Tang-Phosphor was found to use intellectual property beyond what `THIRD_PARTY.md` already records.

#### Next Steps:

`scripts/pnr-desktop.sh` is still unrepaired and is the remaining handoff hazard, because it calls bare `nextpnr-himbaechel` and so takes whatever is first on PATH — the suite's, which carries the published database and would reproduce the wall the README no longer describes — while the binary that works is the fork's build and currently lives in a scratch directory; pin it and fail clearly when it cannot be found. After that, scope the missing clock route in nextpnr, which is the one defect keeping the display dark, from nextpnr's own routing state rather than by inference. Neither needs a hardware cycle, and the desktop core should not be rebuilt until the route works.

#### Files Modified:

- README.md
- FINDINGS.md

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: N/A

---
