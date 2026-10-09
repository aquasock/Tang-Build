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
