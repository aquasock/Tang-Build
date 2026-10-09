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

## 16 COMMIT Unreleased 2026-10-09T05:23:46-07:00

#### Coming From:

Unreleased dc36999

#### Purpose:

Repair `scripts/pnr-desktop.sh` so it builds against the fork's nextpnr rather than oss-cad-suite's, and settle where that binary lives so the build is reproducible by someone who is not us.

#### Outcome:

The binary this project builds its cores with was gone, and recovering it turned out to be most of the cycle. `nextpnr`'s fork build had been left in a scratch directory under `/tmp`, which was empty; only the fork's source at `/run/media/vash/GIT/nextpnr-mathieufro`, clean at `7ed099ec` on `epic/gw5ast138c`, and the database regenerated from the local Gowin install survived, both on real disks. The rebuild now lives at `/home/vash/tools/nextpnr-mathieufro/nextpnr-himbaechel`, deliberately outside `/tmp`, and it is verified equivalent rather than assumed: run over the surviving prepared netlist it reproduces the lost run exactly, `exit=0` with 3 `hclk5` route failures out of 947, and the architecture it generated is byte-for-byte the expected one at `3aea299a264462a47a022975e06ff2635f53c7ba5fd4f6763605944104321fcf`, 93,519,317 bytes. One script defect and two build traps cost real time. The defect is in `scripts/pnr-desktop.sh`: the suite's own `environment` script **unsets** `PYTHONHOME`, so the script sourced it, never set it again, and nextpnr's embedded interpreter resolved its prefix to the `/yosyshq` the bundle was built with and aborted with `failed to get the Python codec of the filesystem encoding`; the script now sets `PYTHONHOME` after sourcing that file, takes the fork's binary by default, honours `NEXTPNR_HIMBAECHEL`, refuses oss-cad-suite's copy by path with the reason spelled out rather than failing later with a misleading error, and fails clearly when the binary is absent. The traps are that the architecture is generated by the `make` step and not by `cmake`, so `PYTHONPATH` must be exported for the whole build rather than passed on the configure line, and that a transposed `-DHIMBAEHCEL_*` is ignored by CMake with a warning that is easy to read past, so the build succeeds having generated the architecture from the suite's published database instead of the fork's and the resulting binary then reports the old `no BELs remaining to implement cell type 'PLL'` at place time, which reads as the device's fault and is not. TOOLCHAIN.md was misread rather than wrong: its three flags were already spelled `HIMBAECHEL` correctly and its snippet already exported `PYTHONPATH`, so this cycle changed none of them and instead recorded the two traps beside them and added what it lacked, which is where the binary is expected to live and how to tell a correct build from a wrong one by the configure line and the architecture hash. `scripts/pnr-desktop.sh`'s obsolete "known wall" text, which described the published database as if it were unavoidable, is replaced by a diagnostic that names a wrong binary as the cause. All of this is verified end to end: the script ran the whole flow with `exit=0`, `957 warnings, 0 errors`, and the same 3-of-947 signature, so the repository can rebuild and re-place its own core from its own scripts again. The required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed `core.md` was not changed and that this entry is the only `.ai` change, and validated it as number 16 of the active log with a conforming four-field header, six sections in canonical order, prose in Outcome and Next Steps, an allowed Status set, and no rewrite of settled history. No part of this repository, TinyTang or Tang-Phosphor was found to use intellectual property beyond what `THIRD_PARTY.md` already records.

#### Next Steps:

Scope the missing clock route in nextpnr, which is still the one defect keeping the desktop core's display dark: whether the PLL output reaches the serialisers' lane at all through the inter-HCLK wires, or whether the failure is in the last hop that `create_hclk_switch_matrix` does create, settled from nextpnr's own routing state rather than by further inference from the tables. The recovered binary at `/home/vash/tools/nextpnr-mathieufro/nextpnr-himbaechel` is the instrument for that, and the `3`-of-`947` signature it reproduces is the baseline any change should be measured against. The desktop core still needs no change for this and should not be rebuilt until the route works. Nothing in this cycle touched the board.

#### Files Modified:

- scripts/pnr-desktop.sh
- TOOLCHAIN.md

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---

## 17 COMMIT Unreleased 2026-10-09T05:44:03-07:00

#### Coming From:

Unreleased 9376ea6

#### Purpose:

Scope the missing clock route from nextpnr's own routing state rather than by further inference from the clock tables, and find out where the display clock is lost.

#### Outcome:

The route does not fail, which is not what the previous three entries assumed; it succeeds and is then not representable in the bitstream. nextpnr exposes its state after routing through a post-route Python hook, and himbaechel's binding is not the one its docs describe -- `ctx.nets` is an `IdNetMap` with no `keys()` -- but a net resolves to `driver`, `users` and `wires` and a `PortRef` to `cell` and `port`, so `hclk5` can be read directly. It has four users, `div5.HCLKIN` at `X181Y81/CLKDIV_3` and all three serialisers' `FCLK` at `X181Y102/IOLOGICAO`, `X181Y100/IOLOGICAO` and `X181Y57/IOLOGICAO`, driven from `pll_hdmi.PLL_inst.CLKOUT0` at `X1Y81/PLL`, and its 44 wires include `X181Y102/FCLKA`, `X181Y100/FCLKA` and `X181Y57/FCLKA`. All three serialisers are reached. What fails is the three dedicated-routing warnings for this net, after which nextpnr falls back and carries it through general fabric -- and where it goes is the finding: among the 44 wires are `X0Y0/HCLK31` and `X0Y0/HCLK11` alongside `SPINE16`, `SPINE25`, `GT00` and `GB10`. `X0Y0` is not one of the 171 tiles in `hclk_pips`, so it has no HCLK switch matrix and no HCLK pip, yet the HCLK wire names exist there because `create_global_nodes` walks every node and calls `create_reuse_wire` at each of its positions. Read against the unpack of section 8, where this bitstream has no `FCLK` at any of the three serialisers and the vendor's has one at all three, the sequence is that the packer resolves the serialiser's clock source from the HCLK structures and does not recognise a route carried by general fabric through an HCLK wire name at a non-HCLK tile, so it emits no `FCLK`. What is established from nextpnr's own state is that the net is routed to all four users and that all three `FCLKA` wires are in it; what is established from the unpack is the absent `FCLK` and the vendor's present one; what is a hypothesis, and is labelled as one in the evidence, is that the packer drops a `FCLK` driven over general fabric or over an HCLK wire outside `hclk_pips`. Two related readings are recorded beside it: `clk27` has the same shape, one user and its single sink among the warnings, so it is routed and presumably unpacked the same way; and `clk`, the 21.49 MHz NES clock, reports 2138 users and 2138 wires, one wire per sink, so it is routed as a star over general fabric rather than through a clock spine, which is why the rest of the core works while the 371.25 MHz clock does not. The recovered binary from entry 16 is the instrument, and it reproduced the baseline exactly -- 3 `hclk5` failures of 947 -- so the reading is of the same run the earlier entries describe. `evidence/desktop-clock-routing.txt` now carries the resolved driver, users and wire list, the `X0Y0` observation, and the established-versus-hypothesis split. The required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed `core.md` was not changed and that this entry is the only `.ai` change, and validated it as number 17 of the active log with a conforming four-field header, six sections in canonical order, prose in Outcome and Next Steps, an allowed Status set, and no rewrite of settled history. No part of this repository, TinyTang or Tang-Phosphor was found to use intellectual property beyond what `THIRD_PARTY.md` already records.

#### Next Steps:

Test the hypothesis directly before writing any fix against it, because the fix differs depending on which half of the disjunction is true: pack the routed JSON from this run with `gowin_pack` and unpack the result, which is minutes and needs no board, so that the `FCLK` mux is either present -- meaning the loss is elsewhere in the pack and the read above is wrong -- or absent -- meaning the packer drops a general-fabric `FCLK` and the fix belongs in `get_out_iologic_attrs` or in how nextpnr is permitted to fall back. If it is the packer, the narrow fix is to make the FCLK source resolvable for a general-fabric route, or to make nextpnr refuse the fallback for a net whose sink is an IOLOGIC `FCLK` rather than routing it into a state the packer cannot encode; if it is the router, the fix is the `X0Y0` reuse-wire availability, which allows an HCLK wire name to be routed at a tile with no HCLK resource. The desktop core still needs no change and should not be rebuilt until one of those is chosen. Nothing in this cycle touched the board.

#### Files Modified:

None.

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: N/A

---

## 18 COMMIT Unreleased 2026-10-09T06:18:16-07:00

#### Coming From:

Unreleased 5ea7c57

#### Purpose:

Run the test entry 17 named -- pack the routed netlist and unpack the result -- and correct the record if it disagrees.

#### Outcome:

It disagrees, and this entry supersedes entry 14 on the point it rests on. Packing the routed netlist from the same run with `gowin_pack` and unpacking the result shows **FCLK present at all three TMDS serialisers**, `R58C182`, `R101C182` and `R103C182`, each `.FCLK(...HCLK0)` beside its `.PCLK(...CLK0)` -- the same source wire the vendor's own unpack shows. So the packer does not drop it, entry 17's hypothesis that it discards an FCLK driven over general fabric is refuted, and entry 14's finding that this build's bitstream has no `FCLK` at any of the three serialisers was wrong. What makes the reading decisive rather than a third reading of the same kind is that the pack reproduces the loaded bitstream exactly: the freshly packed `.fs` is `ec6baf2a894a8b6c3f991874d969b27ff5bab391a26d8440d85efe39dc80b6f1` and its `.bin` is `9b70a448dfc3f83c1c9d7afd02f0cab6c9fbf18824f12cb905d9badf0aa0f6e5`, both byte-identical to the hashes recorded for the files that were staged and loaded on the board, so the bytes that were on the board are the bytes that were unpacked. Why the earlier unpack read differently is not recoverable, because `unpack-ours.v` lived in `/tmp` and is gone, and this entry does not pretend to explain it; what it records is that the surviving inputs were re-derived twice over and agree, and that the earlier reading is the one to distrust. The correction reaches three files: `README.md`'s status item and its not-verified list, `FINDINGS.md` sections 6 and 9, and the evidence file, whose section 11 now carries the correction and marks sections 8 to 10 as superseded. The second result is the more useful one. The bitstream is **byte-reproducible from this repository's own tools**: the fork's nextpnr at `7ed099ec`, the fork's `gowin_pack`, and the database regenerated from the local Gowin install reproduce the project's own core exactly, from its own netlist, hours after the binary that first built it was lost. That is now recorded in the README's verified list, and it changes what a next cycle can do, because a structured comparison against the vendor's build no longer depends on a build that cannot be repeated. What remains is that the serialisers are clocked, the pad and serialiser configuration matches the vendor's, the PLL frequencies are right, and the display still does not come up, so the difference from the vendor's build is somewhere other than the serialisers' clock port and is open again. The required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed `core.md` was not changed and that this entry is the only `.ai` change, and validated it as number 18 of the active log with a conforming four-field header, six sections in canonical order, prose in Outcome and Next Steps, an allowed Status set, and no rewrite of settled history -- entry 14 is left as written and named here as superseded, which is what the syntax asks for. No part of this repository, TinyTang or Tang-Phosphor was found to use intellectual property beyond what `THIRD_PARTY.md` already records.

#### Next Steps:

Find what else differs from the vendor's build, now that the serialisers' clock port does not, and use the reproducibility to do it: the same structured per-site comparison that cleared the pad configuration and the serialiser attributes is available again, and the places it has not been applied are the HCLK block mux state and the CLKDIV, which is where the lane a serialiser is clocked from gets selected rather than merely named -- `FCLK` naming `HCLK0` in both builds says nothing about which lane's HCLK sits behind it or how that lane is driven. Compare those cells and their configuration between the two bitstreams, tile by tile, and treat any difference as the next lead; if there is none, then the fault is not in the bitstream's configuration at all and the next cycle should say so and move to the board side. The desktop core still needs no change, and the three candidates refuted in entries 14 and 17 -- a missing `FCLK`, an unjoined HCLK node, and a dropped general-fabric `FCLK` -- should not be re-walked.

#### Files Modified:

- README.md
- FINDINGS.md

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: N/A

---

## 19 COMMIT Unreleased 2026-10-09T06:33:04-07:00

#### Coming From:

Unreleased a8ec490

#### Purpose:

Compare the HCLK block mux state between this build's bitstream and the vendor's, which entry 18 named as the next place to look once the serialisers' clock port turned out to match.

#### Outcome:

It found the first real difference in the search, and it is in the right place. The comparison wrapped apicula's own `parse_hclk_block` and ran the ordinary unpack over both bitstreams, so both readings come from the decoder rather than from a reimplementation, and exactly one block decodes to anything in either: `(81,181)`, the HCLK block for lane 3, which serves two of this design's three TMDS serialisers. Ours decodes `HCLK3` with `HCLK_MUX_BETA31="L2HCLK31"` and `HCLK_MUX_BETA33="L2HCLK33"` beside `CLKDIV_3: DIV_MODE="5"`; the vendor's decodes `HCLK3` with `HCLK_MUX_GAMMA30="HCLK_UNK581"` and `HCLK_MUX_ALPHA30="HCLK_BUF_BO30"` beside `CLKDIV_0: DIV_MODE="5"`. `L2HCLK` is the logic-to-HCLK entry, a block whose clock arrives from fabric, and ours selects it where the vendor selects `HCLK_UNK581`, which is the band the inter-HCLK wires live in -- the block-to-block traffic of the dedicated HCLK network, the wires `gw5_make_hclk_pips`' `_IHCLK` branch names out of that band. So the vendor's lane 3 is driven over the dedicated network and ours is driven from general fabric, and the CLKDIV slot differs as well, `CLKDIV_3` against `CLKDIV_0`. This joins up with what was already measured and explains the software path end to end: nextpnr reports 3 dedicated-routing failures for `hclk5`, falls back to general fabric, and `gowin_pack` faithfully encodes the resulting fabric entry, so the bitstream is not lying about the route -- the route is one that cannot work at 371.25 MHz. The serialisers' own `FCLK` and `PCLK` sit downstream of the lane and are untouched, which is why they matched the vendor's and why the last three cycles kept arriving back at them. The block beside the PLL, `(81,0)` for lane 2, decodes to `{}` in both bitstreams, so that is not a difference and is recorded here so the search does not go there. One caveat is stated rather than buried: the vendor bitstream compared is `TinyTang/build/desktop/source/impl/pnr/desktop.fs`, whose `.bin` is `c8406c7f...` and is not the file that runs on the card, `desktop.bin` at `4fcc62e6...`; it is a Gowin build of the same source with the same pin constraints, which is what makes a per-site configuration comparison valid, but its own display has not been confirmed working and a comparison against the card's image would be stronger. What is established is the difference and its direction; that a fabric clock is what makes 371.25 MHz unusable here is inferred from the physics and from the vendor's choice, not measured, and `evidence/desktop-clock-routing.txt` section 12 keeps those apart. The required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed `core.md` was not changed and that this entry is the only `.ai` change, and validated it as number 19 of the active log with a conforming four-field header, six sections in canonical order, prose in Outcome and Next Steps, an allowed Status set, and no rewrite of settled history. No part of this repository, TinyTang or Tang-Phosphor was found to use intellectual property beyond what `THIRD_PARTY.md` already records.

#### Next Steps:

Strengthen the reference before writing any fix, because the whole reading rests on a vendor build whose own display is unconfirmed: the card's `desktop.bin` at `4fcc62e6...` is the file that actually drives a working display, it is only on the SD card, and decoding its HCLK block state and putting it beside the two readings here would either make the lane-3 difference conclusive or replace it. Then, if it holds, the fix is that nextpnr must carry the PLL's clock to lane 3 over the inter-HCLK network rather than falling back to fabric -- the three warnings are the moment it gives up -- which is a change in how the HCLK network is modelled or routed rather than anything in the core, the packer or the database. The desktop core still needs no change, and the refuted candidates -- a missing `FCLK`, an unjoined HCLK node, and a dropped general-fabric `FCLK` -- should not be re-walked.

#### Files Modified:

None.

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: N/A

---

## 20 COMMIT Unreleased 2026-10-09T06:42:35-07:00

#### Coming From:

Unreleased 3a314d1

#### Purpose:

Decode the bitstream that actually drives a working display and settle whether entry 19's lane-3 difference holds against it, since that entry's whole reading rested on a vendor build of unconfirmed provenance.

#### Outcome:

The difference holds, and the caveat that limited it is retired. The card was not mounted, but the bitstream it carries is in the tree: three files under `TinyTang/build/oled-terminal/` hash to `4fcc62e6570805b4ea02fb7356c3344e7df90ad980bfe78c66475f1245439873`, which is the `desktop.bin` on the SD card, and one of them sits in a full Gowin build tree with its `.fs` beside it, `sweep-blockfix/reconstruct.qb3T82/impl/pnr/desktop.{bin,fs}`, with `sweep-blockfix/place2/desktop.bin` and `qualify/desktop-blockfix.bin` the other two. Decoded with the same wrapped `parse_hclk_block`, its block at `(81,181)` is `CLKDIV_0: DIV_MODE="5"` and `HCLK3` with `HCLK_MUX_GAMMA30="HCLK_UNK581"` and `HCLK_MUX_ALPHA30="HCLK_BUF_BO30"` -- IDENTICAL to the tree's other Gowin build, which entry 19 compared and whose own display was unconfirmed, and DIFFERENT from ours, which selects `L2HCLK` on both BETA muxes with `CLKDIV_3`. Two independent Gowin builds agreeing with each other is what settles it: the difference is not a build-to-build artifact, and it is not an artifact of having compared against the wrong bitstream, because the reading of `source/impl/pnr/desktop.fs` at `c8406c7f...` and the reading of the card's file at `4fcc62e6...` are the same. Every other block site decodes to `{}` in all three bitstreams, including `(81,0)`, lane 2's block beside the PLL, so that is confirmed as not a difference. What is established is the difference and its direction: the working bitstreams drive lane 3's clock over the dedicated HCLK network by selecting the inter-HCLK wire `HCLK_UNK581`, ours selects the logic-to-HCLK entry `L2HCLK`, which is fabric, the CLKDIV slot differs likewise, and nextpnr's 3 dedicated-routing warnings for `hclk5` are the moment it gave up and fell back -- with `gowin_pack` then encoding that fallback faithfully, so the bitstream is not lying about the route. What is still inferred and not measured is that a fabric clock is what makes 371.25 MHz unusable here; the physics and two vendor builds' choice both point that way, but nothing has put a probe on the pin, and `evidence/desktop-clock-routing.txt` section 13 keeps the two apart exactly as section 12 did. The required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed `core.md` was not changed and that this entry is the only `.ai` change, and validated it as number 20 of the active log with a conforming four-field header, six sections in canonical order, prose in Outcome and Next Steps, an allowed Status set, and no rewrite of settled history. No part of this repository, TinyTang or Tang-Phosphor was found to use intellectual property beyond what `THIRD_PARTY.md` already records.

#### Next Steps:

Attack the fallback rather than the core, because the defect is now located in the flow and not in the design: nextpnr must carry the PLL's clock to lane 3 over the inter-HCLK network instead of giving up at the three warnings and routing it through fabric, and the question to settle first is why the dedicated path is not found when the arcs for it exist in the chipdb and `create_hclk_switch_matrix` creates the pip -- whether the inter-HCLK arcs between the blocks are missing from the generated architecture, or present and unusable because the router cannot reach the block that would source them. `--test` reports the architecture database as integral, so it is not malformed data; the generator and the router are the two places left. If that turns out to need upstream work rather than a patch here, say so in the next entry rather than widening this one. The desktop core still needs no change, the three earlier candidates -- a missing `FCLK`, an unjoined HCLK node, and a dropped general-fabric `FCLK` -- should not be re-walked, and a fabric clock at 371.25 MHz should not be written up as measured until something measures it.

#### Files Modified:

None.

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: N/A

---

## 21 COMMIT Unreleased 2026-10-09T06:48:18-07:00

#### Coming From:

Unreleased 8d11ffb

#### Purpose:

Rebuild clock-smoke and decode its HCLK block, to settle whether the lane-3 entry that entries 19 and 20 pointed at is really the cause and to close the question of whether the PLL's encoding is sound.

#### Outcome:

It closes the PLL question in the strongest form yet, and it retracts the lane-3 direction. clock-smoke was rebuilt with the recovered toolchain, and its bitstream is byte-identical to the one whose readings are recorded -- `78227dd66d75521230be62e1efbc1d2ba84119ebad993ac6aa4c8701820f23ea`, 34,668,145 bytes, both matching -- so the decode is of the design that measured 26.9982 MHz on `clk27` and 74.2452 MHz on `hclk` on real silicon, 2/2 with power cycles and the PLL lock bits reading 11 throughout. Decoded at `(81,181)`, the same site, its block reads `CLKDIV_3: DIV_MODE="5"` and `HCLK3: HCLK_MUX_BETA33="L2HCLK33"` -- which is OURS, not the vendor's, and the same `CLKDIV_3` and `L2HCLK` fabric entry the desktop core carries. Two things follow and the second is stronger. The lane-3 difference is a property of the open flow rather than of this core, because a design built the same way and known to work on this board has the same entry, so it is a real difference from Gowin's output and it is not why the display is dark. And `hclk` is the `CLKDIV_3` OUTPUT: for it to read 74.2452 MHz the divider's input, 371.25 MHz, had to arrive through that same fabric entry and be divided correctly, which is a measured datum that a 371.25 MHz clock on the fabric entry is usable on this silicon at least as far as a CLKDIV. The inference entries 19 and 20 carried -- that a fabric clock is what makes 371.25 MHz unusable -- does not survive that and is retracted here rather than left standing. On the PLL itself this is the best evidence the project has: the fuse encoding is exercised end to end through a real design, at two frequencies, on the board, with both PLLs locking, and none of tonight's findings places any part of it in doubt -- the differences found are all in the clock network and in routing, not in the PLL. What clock-smoke cannot show is whether a clock on that entry can drive a serialiser's `FCLK`, because it has no OSER10, and that is now the remaining gap between the two designs: the three open-flow and Gowin bitstreams decoded at `(81,181)` are recorded in the evidence, and everything else compared with a working one has matched. Two smaller findings from running the build script: it defaults `NPNR` to `/tmp/tb/npnr-build`, the path lost to `/tmp` being cleared, and its default output directory is `/tmp/tb/clock-smoke`, which is why the previous clock-smoke bitstream had to be rebuilt rather than read; both are instances of the hazard entry 16 fixed in `pnr-desktop.sh` and neither was changed in this cycle. The required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed `core.md` was not changed and that this entry is the only `.ai` change, and validated it as number 21 of the active log with a conforming four-field header, six sections in canonical order, prose in Outcome and Next Steps, an allowed Status set, and no rewrite of settled history. No part of this repository, TinyTang or Tang-Phosphor was found to use intellectual property beyond what `THIRD_PARTY.md` already records.

#### Next Steps:

Compare the OSER10 cells between our bitstream and a working one -- their clock selection and gearbox configuration -- because that is now the only place the two designs differ in kind: clock-smoke drives a CLKDIV from the fabric entry and is measured working, while the desktop core drives three OSER10s from the same entry and is not, and clock-smoke has no serialiser to test that last hop with. The comparison is the same shape as the ones that have already been made and it has not been run; `FCLK` naming `HCLK0` in both builds is established, but what the serialiser does with it internally is not. Repair `scripts/build-clock-smoke.sh` in the same pass, since its `/tmp` defaults reintroduce exactly the hazard that lost the last bitstream, and record the rebuilt bitstream's hash beside the readings it belongs to. The desktop core still needs no change, and the retracted and refuted candidates should not be re-walked.

#### Files Modified:

None.

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---

## 22 COMMIT Unreleased 2026-10-09T06:58:44-07:00

#### Coming From:

Unreleased ff0d794

#### Purpose:

Compare the OSER10 cells' internal configuration between this build's bitstream and one that drives a working display, which entry 21 named as the last place the two differ in kind.

#### Outcome:

The cause is found, and it supersedes entry 21 as well as the three candidates before it. The comparison wrapped the unpacker's `parse_attrvals` and logged every IOLOGIC call, and both bitstreams decode 320 IOLOGIC attribute sets. In the working bitstream exactly three of them -- the three OSER10s -- carry `CLKOMUX 61`, `FCLKSEL0 79`, `FCLKSEL1 81`, `FCLKSEL2 114`, `FCLKSEL3 86`, `HWL 107`, `LSRIMUX_0 1`, `LSROMUX_0 1`, `OUTMODE 16` and `WRFCLKSEL 102`; in ours the same three carry only `CLKOMUX 61`, `OUTMODE 16` and `WRFCLKSEL 102`. Our serialisers are missing `FCLKSEL0` through `FCLKSEL3`, the fast-clock lane selection, and `HWL`, `LSRIMUX_0` and `LSROMUX_0` with them. The mechanism was read in the packer rather than guessed: `get_out_iologic_attrs` adds `fclk_select_attrs(bel, 'FCLKSEL1', 'FCLKSEL2')`, and that function begins `lane = self._fclk_lane.get(bel.fclk); if lane is None: return []`. `_fclk_lane` maps `SPINE10`..`SPINE13` to lanes 0..3, so when the FCLK is not carried on a spine -- which is what the router's fallback to general fabric leaves it -- `bel.fclk` is `None`, nothing is selected, and no lane selection reaches the bitstream. The serialiser's clock input is left unselected, so it has no bit clock. The whole chain is then read rather than assumed: nextpnr cannot route `hclk5` on dedicated routing to any of the three serialisers and falls back to fabric, which entries 2 and 10 recorded as 3 of the 947 warnings; `FCLK` is therefore not on a spine and `bel.fclk` is `None` at pack time; `fclk_select_attrs` returns `[]`; the clock mux is unselected; and no TMDS leaves the part, which is the dark display and the sleeping monitor. The vendor's build routes over the dedicated network, so its `bel.fclk` is set and all four `FCLKSEL`s are written, which is why it works. Two consequences for the record. Entry 21 retracted the lane-3 entry as a cause on the reasoning that clock-smoke carries the same fabric entry and is measured working, and that reasoning is wrong and is superseded here: clock-smoke takes its clock at a CLKDIV, which needs no IOLOGIC lane selection, so it never exercised the thing that turns out to be missing, and the lane entry is implicated after all -- not because fabric is too slow, which entry 21 was right to doubt, but because the packer cannot express a fabric-routed FCLK at all. What is established is that ours lacks `FCLKSEL0` through `FCLKSEL3` where the working bitstream has them and that `fclk_select_attrs` writes nothing when `bel.fclk` is `None`; what is inferred from those two, though tightly, is that an unselected clock mux is why the serialiser is silent, and the link that would settle it -- `bel.fclk` being `None` in this run -- is checkable with the post-route hook that produced entry 17's dump and has not been checked. The fix is not in the core, the design, the packer's tables or the database: it is that nextpnr must route the FCLK on the dedicated HCLK network, which is what the recovered binary and the regenerated database exist to test. The required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed `core.md` was not changed and that this entry is the only `.ai` change, and validated it as number 22 of the active log with a conforming four-field header, six sections in canonical order, prose in Outcome and Next Steps, an allowed Status set, and no rewrite of settled history. No part of this repository, TinyTang or Tang-Phosphor was found to use intellectual property beyond what `THIRD_PARTY.md` already records.

#### Next Steps:

Check the one inferred link before writing any fix: run the post-route hook from entry 17 over the same routed design and print `ctx.cells[...].ports['FCLK'].net.name` for the three OSER10s and the bel's fclk attribute, to confirm that `bel.fclk` is `None` when the net is fabric-routed -- which would make the chain airtight rather than tightly inferred -- and to record which IOLOGIC bel and lane it would have had. Then the fix belongs in nextpnr: make the FCLK route on the dedicated HCLK network, or refuse to fall back for a net whose sink is an IOLOGIC FCLK rather than routing it into a state the packer cannot express, so that the failure is loud instead of silent. A packer-side alternative, teaching `fclk_select_attrs` to express a fabric source, is possible in principle but pointless at 371.25 MHz. The desktop core still needs no change, and the two earlier findings that this supersedes -- the FCLK connection being absent (14) and the lane entry not being the cause (21) -- should not be re-walked in their original form.

#### Files Modified:

None.

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: N/A

---

## 23 COMMIT Unreleased 2026-10-09T07:17:21-07:00

#### Coming From:

Unreleased 561cfe2

#### Purpose:

Run the two checks entry 22 named -- whether `bel.fclk` really is `None`, and whether the packer can encode the lane our serialisers are on -- and settle the chain before writing any fix.

#### Outcome:

Both were run and between them the cause is settled, though not in the shape entry 22 gave it. The first check refutes that entry's inferred link: nextpnr's routed JSON carries `IOLOGIC_FCLK: 'HCLK_OUT1'` on all three OSER10s, so the attribute is set and names a lane; `gowin_pack.set_iologic_bel_fclk` maps `HCLK_OUT0..3` to `SPINE10..SPINE13`, `HCLK_OUT1` becomes `SPINE11`, `_fclk_lane` gives lane 1, and `fclk_select_attrs` does run -- which is why `WRFCLKSEL`, one of the three attributes it writes, is present in our decode while the lane pair is not. The mechanism was right and the specific cause was wrong. The second check is positive and decisive: the three `IOLOGIC_FCLK` attributes were rewritten to `HCLK_OUT2` in the routed JSON and the design repacked without re-routing, and the `FCLKSEL1`/`FCLKSEL2` pair appeared, at 81 = `HCLK2` and 114 = `HCLK2_`, where with lane 1 they do not appear at all and nothing warns. The bitstream hash changed between the two packs, so the attribute is genuinely read. Put beside the working bitstream's serialisers, which carry `FCLKSEL0` 79 = `HCLK0`, `FCLKSEL1` 81 = `HCLK2`, `FCLKSEL2` 114 = `HCLK2_` and `FCLKSEL3` 86 = `HCLK0_`, the conclusion is that the IOLOGIC's fast-clock mux encodes lanes 0 and 2 and has no representation for lanes 1 or 3. Our run lands the FCLK on lane 1, the packer writes values with no fuse rows, and the attributes are dropped in silence, leaving the clock mux unselected and the serialiser without a bit clock. What is established is the whole chain, each link measured rather than inferred: the router cannot use the dedicated network and falls back; the fallback sources the FCLK from lane 1; the mux encodes lanes 0 and 2 only; the packer drops the lane-1 pair silently; and the unselected mux is what leaves the display dark. What is NOT yet known, and it decides which fix is right, is whether lanes 1 and 3 are impossible on this silicon or merely unpopulated in the tables -- the packer's comment asserts this die has no `FCLKSEL0`/`FCLKSEL3` row, which the working bitstream disproves by carrying all four, so that comment was generalised from one measured cell just as this cycle's predecessor was. One more difference from the same comparison is recorded rather than explained: `LSRIMUX_0` and `LSROMUX_0` are present in the working bitstream's serialisers and absent from ours, so entry 11's fix removed one fuse and did not restore the pair. The required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed `core.md` was not changed and that this entry is the only `.ai` change, and validated it as number 23 of the active log with a conforming four-field header, six sections in canonical order, prose in Outcome and Next Steps, an allowed Status set, and no rewrite of settled history. No part of this repository, TinyTang or Tang-Phosphor was found to use intellectual property beyond what `THIRD_PARTY.md` already records.

#### Next Steps:

Settle what the fix must do before writing it, because the two possibilities need opposite changes and the available evidence can decide between them: scan the vendor bitstreams already in the tree -- there are three dozen `desktop*.bin` under `TinyTang/build/` matched by hash, plus their `.fs` siblings -- for any IOLOGIC whose `FCLKSEL` selects lane 1 or lane 3, which would show the mux can encode them and make the fix a matter of populating tables rather than constraining placement. If none exists, constrain the flow instead: nextpnr must not source an IOLOGIC FCLK from lane 1 or 3, and the packer must raise rather than silently dropping a value it cannot encode, so that a bitstream with an unclocked serialiser cannot be built at all. The packer guard is worth writing either way, since a silent miscompile is what let this through six cycles of investigation. The desktop core needs no change, and the refuted links -- fclk `None` (22) and the retraction of the lane entry (21) -- should not be re-walked.

#### Files Modified:

None.

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: N/A

---

## 24 COMMIT Unreleased 2026-10-09T07:32:38-07:00

#### Coming From:

Unreleased fccbfb1

#### Purpose:

Calibrate which `HCLK_OUT` values the IOLOGIC clock selection can actually encode, land the packer guard that makes the silent drop impossible, and capture the fork edit durably.

#### Outcome:

The calibration ran and changed what the fix has to be, and the guard is landed and verified. Four packs of the same routed netlist, each with the three serialisers' `IOLOGIC_FCLK` forced to one value, give: `HCLK_OUT0` and `HCLK_OUT2` both produce `FCLKSEL1` 81 = `HCLK2` and `FCLKSEL2` 114 = `HCLK2_` and are byte-identical to each other, sha `e77ff5b8...`; `HCLK_OUT1` and `HCLK_OUT3` produce neither, sha `ec6baf2a894a8b6c3f991874d969b27ff5bab391a26d8440d85efe39dc80b6f1`, which is the hash of the bitstream that was loaded on the board. The control therefore validates the method exactly: forcing the value the flow actually chose reproduces the as-built bitstream byte for byte, so the calibration measures the real thing rather than a model of it. Even values encode, odd values do not, and the mapping is many-to-one because two different even values give the same output -- which is why the rule is a table and not the block-minus-one that entry 23's next step guessed at, and why guessing it would have been wrong. The second result is that even the encoding value does not reproduce the vendor's set: the working serialisers carry ten attributes including `FCLKSEL0` 79, `FCLKSEL3` 86, `HWL` 107, `LSRIMUX_0` 1 and `LSROMUX_0` 1, and the good lane still yields only `FCLKSEL1`, `FCLKSEL2` and `WRFCLKSEL`. So the packer is incomplete for this device across several IOLOGIC attributes, not merely on the lane, and entry 23's note that the vendor's bitstream disproves the "no `FCLKSEL0`/`FCLKSEL3` row" comment is joined by a second instance of the same thing. The guard was then written in the fork's `get_iologic_attr_val`, and its first form was wrong: refusing every pair `add_attr_val` cannot find also refused `LSROMUX_0`, which the working vendor bitstream carries and these tables do not, and that stopped the one lane that packs from packing. That refusal is itself the second instance -- the tables are incomplete in both directions -- and it scoped the guard to the `FCLKSEL` attributes, where dropping a value leaves a cell with no clock and nothing says so. Verified both ways: the netlist as routed now raises `IOLOGIC FCLKSEL2='HCLK1_' is not encodable on GW5AST-138C`, naming the pair and the consequence, and the `HCLK_OUT2` variant still packs to 35,752,331 bytes. The fork edit is captured as `patches/0002-iologic-refuse-unencodable-clock-selection.patch`, 25 insertions and one deletion, because a fork working tree is as losable as `/tmp` was and this project already carries its design edits as patches. The required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed `core.md` was not changed and that this entry is the only `.ai` change, and validated it as number 24 of the active log with a conforming four-field header, six sections in canonical order, prose in Outcome and Next Steps, an allowed Status set, and no rewrite of settled history. No part of this repository, TinyTang or Tang-Phosphor was found to use intellectual property beyond what `THIRD_PARTY.md` already records.

#### Next Steps:

Complete the packer's IOLOGIC attribute coverage for this device, which the guard has now shown to be the real defect and whose shape is known: `LSROMUX_0`, `LSRIMUX_0`, `HWL`, `FCLKSEL0` and `FCLKSEL3` are all carried by a working vendor bitstream and absent from these tables, so the work is to find their fuse rows and populate them, the way the PLL pump constants were measured from vendor bitstreams rather than derived. The vendor builds already in the tree are the reference and the guard makes the work safe, because anything still missing will refuse instead of vanishing. Which of those five actually matter for the display is not known and should be settled by repacking and comparing, not by assuming that matching the vendor's attribute list is the same as matching its behaviour. The lane question is subordinate to this: once the tables are complete, an odd `HCLK_OUT` will either encode or refuse loudly, and either answer is better than the silent drop that cost six cycles. The desktop core still needs no change, and nothing in this cycle touched the board.

#### Files Modified:

- patches/0002-iologic-refuse-unencodable-clock-selection.patch

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---

## 25 COMMIT Unreleased 2026-10-09T07:57:44-07:00

#### Coming From:

Unreleased 97c3aa7

#### Purpose:

Check whether the IOLOGIC rows entry 24 said were missing really are, and fix what the answer turns out to be.

#### Outcome:

The rows are not missing, and the defect is a name-versus-id confusion in the packer. Probing the device's own table shows every attribute entry 24 proposed to populate already present, with fuse rows: `LSROMUX_0` id 21 on value 1, `LSRIMUX_0` id 20 on value 1, `HWL` id 117 on value 107, `FCLKSEL0` id 79 on 79, 80, 82 and 83, `FCLKSEL1` id 85 on 1, 79, 80 and 81, `FCLKSEL2` id 86 on 2, 82, 86 and 114, and `FCLKSEL3` id 129 on 79 and 86. So the plan entry 24 wrote was wrong, and the lesson is the one this project keeps relearning: check which structure holds a datum before concluding it is absent. What is actually wrong is that the packer passes `AttrVal('LSROMUX_0', '1')`, and `get_iologic_attr_val` resolves any string through `iologic_attrvals`, where `'1'` is the code 2 while this device's table keys that attribute on the value 1 -- so the pair looked up had no row and the fuse vanished in `add_attr_val`'s silent `if attrval:`. Passing the int skips the name table. That is the branch our OSER10s take, since their `OUTMODE` is not `ODDRX1`, which is exactly why a working vendor bitstream carries `LSROMUX_0 1` on its serialisers and this packer wrote nothing. The packer's three `LSROMUX_0` sites were changed to pass value ids, and the 0002 patch regenerated to cover both this and entry 24's guard -- the guard is kept, because its refusal of the lane-1 case is a genuine one and the `LSROMUX_0` refusal it also produced was the caller bug now fixed. Verified by repacking the `HCLK_OUT2` variant, which the guard permits: our serialisers now decode as `CLKOMUX 61`, `FCLKSEL1 81`, `FCLKSEL2 114`, `LSROMUX_0 1`, `OUTMODE 16` and `WRFCLKSEL 102`, against the vendor's ten -- so four attributes remain: `FCLKSEL0`, `FCLKSEL3`, `HWL` and `LSRIMUX_0`. The last of those corrects entry 11, which removed `LSRIMUX_0` from output cells on the reasoning that the vendor does not spend that fuse; the working vendor bitstream carries `LSRIMUX_0 1` on its serialisers and on all 314 ordinary IOLOGICs as well, so that reasoning was wrong or was drawn from the tree's other vendor build, and entry 11's change should be revisited rather than trusted. What is established is the lookup defect, that the table rows exist, and that one attribute now reaches the bitstream. What is not established is whether the four still missing matter for the display, which repacking and comparing would settle rather than assuming. The required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed `core.md` was not changed and that this entry is the only `.ai` change, and validated it as number 25 of the active log with a conforming four-field header, six sections in canonical order, prose in Outcome and Next Steps, an allowed Status set, and no rewrite of settled history. No part of this repository, TinyTang or Tang-Phosphor was found to use intellectual property beyond what `THIRD_PARTY.md` already records.

#### Next Steps:

Revisit entry 11's `LSRIMUX_0` removal, which this cycle's evidence contradicts, and find the other three the same way: `FCLKSEL0`, `FCLKSEL3` and `HWL` have fuse rows in the device's table, so if the packer is not writing them the reason is a caller that does not emit them at all rather than a value that cannot resolve, and that is a different and smaller question than the one entry 24 posed. Then settle whether any of the four matters by repacking and comparing behaviour rather than attribute lists, since matching the vendor's list is not the same as matching its behaviour. The lane remains the substantive question: `FCLKSEL1` carries `HCLK1` but `FCLKSEL2` does not carry `HCLK1_`, so an odd lane half-encodes, and that is why the guard refuses it; whether nextpnr should be constrained to the lanes the device can select is still open and is the last thing between here and a display. The desktop core needs no change, and nothing in this cycle touched the board.

#### Files Modified:

- patches/0002-iologic-encodable-fuses.patch

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---

## 26 COMMIT Unreleased 2026-10-09T08:02:10-07:00

#### Coming From:

Unreleased 6dd72a3

#### Purpose:

Explain the anomaly entry 25 left open -- why forcing `HCLK_OUT0` appeared to produce `FCLKSEL1` 81 rather than 79 -- and record the state such that a successor can make the last change without re-deriving any of this.

#### Outcome:

The anomaly is explained and it is benign, and the constraint it was blocking is now grounded on the real variable. An instrumented pack logged what the packer computes at both stages: `set_iologic_bel_fclk` turns `IOLOGIC_FCLK` into `bel.fclk` and `fclk_select_attrs` turns that into the attribute-value pairs. For `HCLK_OUT0` it produces `bel.fclk='SPINE10'` and the pairs `FCLKSEL1=HCLK0` and `FCLKSEL2=HCLK0_`; for `HCLK_OUT2`, `SPINE12` with `HCLK2` and `HCLK2_`; for `HCLK_OUT1`, `SPINE11` with `HCLK1` and `HCLK1_`. So the packer maps lane to value correctly at every step and the `81`/`114` a decode reports for the lane-0 case is the decoder aliasing `FCLKSEL1` values 79 and 81 onto the same fuses -- which is also why `HCLK_OUT0` and `HCLK_OUT2` pack byte-identically. Neither nextpnr's `HCLK_OUT<n>` handling nor the packer's `_fclk_lane` needs changing; the value is what cannot be encoded. The constraint is therefore precise and measured: an IOLOGIC's fast clock can only be selected from lanes 0 and 2, because `FCLKSEL2` carries `HCLK0_` and `HCLK2_` and has no row for `HCLK1_` or `HCLK3_`; our serialisers are served by lanes 1 and 3, and their pairs are dropped, leaving the clock mux unselected. The vendor's serialisers use lane 2, the PLL's own lane. The change left is to constrain the serving wire in apicula's `gw5_hclk_arcs` and `gw5_create_hclk_iol_pip`, which is where `io2hclk` is built, so an IOLOGIC's FCLK can only come from a lane-0 or lane-2 wire. `evidence/desktop-clock-routing.txt` section 18 is now written as a handoff and carries the state, the exact change, the offline verification steps with their acceptance criteria, the instrument locations under `/home/vash/tools/pnr-test`, the traps that cost time in this session, and the list of readings already refuted so none is re-walked. The required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed `core.md` was not changed and that this entry is the only `.ai` change, and validated it as number 26 of the active log with a conforming four-field header, six sections in canonical order, prose in Outcome and Next Steps, an allowed Status set, and no rewrite of settled history. No part of this repository, TinyTang or Tang-Phosphor was found to use intellectual property beyond what `THIRD_PARTY.md` already records.

#### Next Steps:

Make the one change section 18 of `evidence/desktop-clock-routing.txt` specifies -- constrain the IOLOGIC FCLK's serving wire to lanes 0 and 2 in `gw5_hclk_arcs` and `gw5_create_hclk_iol_pip` -- then rebuild the chipdb and nextpnr, re-place and re-pack, and decode the three OSER10s' attributes, with the acceptance criterion that they carry the vendor's ten attributes including all four `FCLKSEL` values rather than the three they carry now; section 18 lists the commands, the expected database and architecture hashes, and the router baseline of 3 `hclk5` dedicated-routing failures out of 947 to measure against. Do not change nextpnr's `HCLK_OUT<n>` handling or the packer's `_fclk_lane`, and do not re-walk the readings section 18 lists as refuted. Revisit entry 11's removal of `LSRIMUX_0` in the same pass, since the working vendor bitstream carries it and that removal is now contradicted. Nothing here needs the board until the bitstream carries the selection, at which point the desktop core can finally be loaded and looked at.

#### Files Modified:

None.

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: N/A

---

## 27 COMMIT Unreleased 2026-10-09T08:45:02-07:00

#### Coming From:

Unreleased a47855e

#### Purpose:

Make the one change section 18 of the evidence file specified -- constrain an IOLOGIC's fast clock to a lane this device can encode -- and record what it does to the routed and packed design.

#### Outcome:

The lane constraint is made, and it is not where the handoff said. Reading the generated database rather than the code settled the site: every IOLOGIC was offered all four HCLK lanes of its serving block by the `for i in range(2): for j in range(4)` loop in apicula's `gw5_make_hclk_pips`, measured as `HCLK30..HCLK33` at `(102,181)` and `(100,181)` and `HCLK10..HCLK13` at `(57,181)`, while the two functions section 18 named -- `gw5_hclk_arcs` and `gw5_create_hclk_iol_pip` -- return the serving *block* index and a yes/no gate respectively, so editing either would have changed nothing about the display; that misdirection is itself the finding, because the log had spent eight cycles on numbers read out of the wrong structure and this would have been the ninth. The loop now iterates a measured, device-scoped lane set, `(0, 2)` on the GW5AST-138C and all four wherever nobody has measured, and the invariant behind it is a table lookup: a lane is selectable exactly when the device's `IOLOGIC` table can spell it both plain and underscored, `FCLKSEL1 = HCLK<n>` and `FCLKSEL2 = HCLK<n>_`, which covers lanes 0 and 2 and neither odd lane, since `FCLKSEL1` has no `HCLK3` row and `FCLKSEL2` has no `HCLK1_` row. The lane turns out to be chosen by the router and not at placement, which is why the routable arcs are the lever: nextpnr's `postRoute()` reads the name of the wire driving each `FCLK` port and indexes `hclk_up_wire[block][out]` to report `IOLOGIC_FCLK = HCLK_OUT<out>`, so nothing in nextpnr's `HCLK_OUT<n>` handling and nothing in the packer's `_fclk_lane` was changed, and neither needs it. The change was verified against a control rather than a baseline: the pre-change binary and its architecture were kept, the same routed netlist was placed and routed twice, and the control reproduced the recorded baseline exactly -- 947 `Failed to route` lines, `clk` 943, `hclk5` 3, `clk27` 1 -- with its routed JSON differing from the archived one in exactly one key, `settings['cst.filename']`, which is a path, so any difference between the two runs is attributable to the architecture. The lane-fixed architecture produces the same 947 / 943 / 3 / 1 signature, which retires the "0 `hclk5` failures" criterion this project had implied, and moves the three `OSER10`s from `HCLK_OUT1` three times to `HCLK_OUT2`, `HCLK_OUT0` and `HCLK_OUT0`, while the HCLK block at `(81,181)` goes from driving lanes 1 and 3 to lanes 0 and 3 -- lane 0 for the serialisers, which is the lane the vendor's own build drives, and lane 3 for the `CLKDIV` that divides `hclk5` down to `hclk`. Packing then succeeds where the guard had been refusing: the `.fs` is `8ce8671df6723f5c5015428a50d94d31845c656fe24fecc7b68ff7abd5853484` at 35,752,331 bytes, converting through the repository's own `tools/fs-to-bin.py` to a `.bin` of `bb5d01cc90c22f5d03e9fefc948d1f0a074e491d55acdf3994c9574b95ff8c37` at 4,466,048 bytes, and the three serialisers decode with seven attributes -- `CLKOMUX 61`, `FCLKSEL1 81`, `FCLKSEL2 114`, `LSRIMUX_0 1`, `LSROMUX_0 1`, `OUTMODE 16`, `WRFCLKSEL 102` -- where the previous build carried three and no lane selection at all. `LSRIMUX_0` is the cycle's second change and it reverses entry 11: that removal rested on `TinyTang/build/desktop/source/impl/pnr/desktop.fs`, which entry 19 had already flagged as not the file that drives the working display, and re-measuring the working bitstream `e83e2d4afbd7...` shows `LSRIMUX_0 1` on its serialisers and on 314 ordinary IOLOGICs, so the revert restores them to the vendor's set and leaves the ordinary cells unchanged. Two claims are retracted with it: the packer's assertion that this die "has no `FCLKSEL0`/`FCLKSEL3` row", which the device's own table disproves, `FCLKSEL0` being id 79 on `HCLK0`, `HCLK1` and `HCLK3` and `FCLKSEL3` id 129 on `HCLK0` and `HCLK0_`, and which had been generalised from one measured `OSER4`; and the "0 `hclk5` failures" acceptance criterion. What is explicitly NOT established, and is written into the code and the evidence as open rather than acted on, is whether the four-attribute difference that remains at the serialisers is a difference in fuses at all: the decoder aliases `FCLKSEL` values onto the same fuses, since forcing `HCLK_OUT0` and `HCLK_OUT2` packs byte-identically and both decode as `FCLKSEL1 81`, so an attribute-list difference is not evidence of anything and the comparison has to be made at the fuse level at the three TMDS tiles or on the board, and nothing was loaded this cycle, which leaves the display a hypothesis rather than a result. Two environment facts were established rather than assumed. `msgspec`, which the bundle does not ship and which `save_chipdb`, `chipdb_builder` and `gowin_pack` all need, had been lost with `/tmp/tb/pydeps` when `/tmp` was cleared and is restored to `/home/vash/tools/pydeps`, with the documented `chipdb_builder` command verified back to byte-identical output against the recorded database hash before anything was changed. And `gowin_pack` loads the chipdb at pack time, so the database, the architecture and the packer must come from one apicula revision; mixing them fails with a bare `KeyError` from `get_simple_pip_fuses` that reads as a packer bug and is not, which `TOOLCHAIN.md` now records beside the corrected database, `.bba` and `.bin` hashes. The other measured device was regression-checked by building it rather than by argument: the GW5A-25A database is byte-identical before and after this change, which the device-scoped default makes true by construction and the paired build confirms. The required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed `core.md` was not changed and that this entry is the only `.ai` change, and validated it as number 27 of the active log with a conforming four-field header, six sections in canonical order, prose in Outcome and Next Steps, an allowed Status set, and no rewrite of settled history. No part of this repository, TinyTang or Tang-Phosphor was found to use intellectual property beyond what `THIRD_PARTY.md` already records.

#### Next Steps:

Load the bitstream at `bb5d01cc...` and look at the display, which is the test this cycle could not run: if it is lit, the only work left is the unquantified `FCLKSEL0`/`FCLKSEL3`/`HWL` difference at the serialisers, and if it is dark that difference is the first thing to compare at the fuse level at the three TMDS tiles rather than as attribute lists, because the decoder aliases the values and the list cannot settle it. `scripts/build-clock-smoke.sh` still defaults its build to `/tmp/tb/...` and should be pointed somewhere durable the way `scripts/pnr-desktop.sh` was, and any re-run must regenerate the device database, the architecture and the packer's tables together. The desktop core still needs no change; the change site is not `gw5_hclk_arcs` or `gw5_create_hclk_iol_pip`; the vendor's lane is 0 and not 2; and the readings section 18 and section 19 list as refuted should not be re-walked.

#### Files Modified:

- patches/0002-iologic-encodable-fuses.patch
- patches/0003-hclk-iol-fclk-lanes.patch
- README.md
- FINDINGS.md
- TOOLCHAIN.md
- evidence/desktop-clock-routing.txt

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---

## 28 COMMIT Unreleased 2026-10-09T09:45:28-07:00

#### Coming From:

Unreleased 797e5bb

#### Purpose:

Put a visible output in front of the user for the first time -- eight LEDs driven by a bitstream this repository built -- and record the run beside the UART report that verifies it.

#### Outcome:

The board now shows the open toolchain working, and the run is verified two ways at once. `scripts/build-clock-smoke.sh` was repaired first, because it defaulted its output directory, its nextpnr directory and its Python dependency directory into `/tmp` and had already lost this design's only bitstream to a reboot once: they now point at `/home/vash/tools/clock-smoke`, `/home/vash/tools/nextpnr-mathieufro` and `/home/vash/tools/pydeps`, the script refuses oss-cad-suite's nextpnr by path with the reason written out, and it fails clearly when the Python dependencies are absent. Rebuilding through it produced a bitstream byte-identical to the one `evidence/clock-smoke-readout.txt` recorded before this cycle's changes -- `78227dd6...` at 34,668,145 bytes -- where an expectation recorded earlier in the cycle had said the change to the device database would necessarily move the hash; the prediction was wrong and the reason is the better result: the lane constraint only removes HCLK arcs an IOLOGIC may use for its fast clock, this design has no OSER10 and so no IOLOGIC that selects a lane, so its placement, routing and packed output are untouched. That is the change demonstrated behaviour-preserving for a design with no IOLOGIC FCLK rather than argued, and it also rules out the desktop core's dark display being caused by the edit perturbing placement. The bitstream was then loaded over the MCU port in the one-wire arrangement and captured twice off `/dev/ttyUSB1` at 115200: 46 lines over 31 seconds and 23 over 15, `lock=11` on every one of both, no sample skipped and every line-counter step exactly one period, `sys_clk` 49.9968 MHz from the UART anchor in both, `clk27` 1.0800 and `hclk` 2.9701 times `sys_clk`, the two runs agreeing to about three parts in 10^5 and carrying the same counter values at the same line index (`n=0007` reads `c27=7907 hk=4cd1` in both), which makes the design deterministic from reset across separate loads. The doubled clock rates are not new: `clock_smoke.v` carries `defparam pll_27.ODIV0_SEL = 50` and `evidence/clock-smoke-divider-runs.txt` records that 50 divides by 25 where 100 divides by 50, so 54 and 148.5 MHz are what this committed design reports and hclk5 follows at 742.5 rather than 371.25, while the desktop core's own pll_27 asks for 100. With an 8-LED PMOD in PMOD1 the user then reported LEDs 1, 2 and 5 blinking and 3, 4, 6, 7 and 8 dark, and against the lane order this project records for the dock -- lanes 0-7 on module pins 1, 2, 3, 4, 7, 8, 9 and 10, interleaved onto IO0/2/4/6 and IO1/3/5/7 -- the three blinking are exactly the three counter lanes including the non-adjacent lane 4 read as LED5, a set that cannot match by accident, so if the module's own LEDs run in lane order then the dock's interleave is confirmed on hardware for the first time; the module was not identified, and that assumption is the one thing the reading rests on and is written down as such. The two dark LEDs are the two pins the design holds steadily high, the PLL lock bits, which makes this module active-low -- an LED lights when its pin is driven low -- so those two are dark precisely because both PLLs are locked, the same fact the UART reports as `lock=11` read by eye instead of by tool, and it also explains the power-on state the user reported, all eight lit with nothing loaded, since a ball with no design on it reads low; an expectation recorded earlier in the cycle said the three undriven lanes would stay lit and five would be steady, which was the opposite polarity and was wrong, and the user's observation corrected it. What this does NOT establish is anything about the display: this design drives no TMDS and its screen output is blank by construction, so the desktop core's dark screen and its two unresolved candidates, the fabric-versus-dedicated clock path and the serialiser attribute difference, are untouched and remain in sections 18 and 19 of `evidence/desktop-clock-routing.txt`. Nor are the three blink rates measured: they follow from the counters and the doubled rates at 1.49, 3.22 and 4.43 Hz, and the user read the three as similar rates with phase offsets rather than as rates two to three times apart, which is worth a re-look and is not a finding. The run is recorded in `evidence/clock-smoke-led-and-uart.txt` with the artifact digest, both decodes, the lane table, the module-order caveat and the reproduction commands. The required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed `core.md` was not changed and that this entry is the only `.ai` change, and validated it as number 28 of the active log with a conforming four-field header, six sections in canonical order, prose in Outcome and Next Steps, an allowed Status set, and no rewrite of settled history. No part of this repository, TinyTang or Tang-Phosphor was found to use intellectual property beyond what `THIRD_PARTY.md` already records.

#### Next Steps:

Settle what the LED observation was allowed to claim by identifying the 8-LED module and confirming that its LEDs run in lane order, because the dock's interleave only becomes measured once that assumption is closed; everything else in section 3 of `evidence/clock-smoke-led-and-uart.txt` is already hardware-backed. Re-read the three blink rates while the design is loaded, since rates two to three times apart and three similar rates with phase offsets cannot both be true, and the answer distinguishes a perception artifact from a divider problem. Then return to the display, which is where this project's purpose still sits: the two candidates recorded in sections 18 and 19 are the fabric-versus-dedicated clock path at the HCLK block, where ours still arrives over fabric and the working vendor build uses the dedicated inter-HCLK wire, and the serialiser attribute difference, which needs comparing at the fuse level at the three TMDS tiles rather than as attribute lists because the decoder aliases `FCLKSEL` values. `scripts/build-clock-smoke.sh` and the durable paths under `/home/vash/tools` are now the instruments for that, and any re-run must regenerate the device database, the architecture and the packer's tables together.

#### Files Modified:

- scripts/build-clock-smoke.sh
- evidence/clock-smoke-led-and-uart.txt
- FINDINGS.md

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 29 COMMIT Unreleased 2026-10-09T09:55:20-07:00

#### Coming From:

Unreleased 8550ed6

#### Purpose:

Drive all eight PMOD1 lanes as a chaser so the dock's lane order becomes readable by eye, and give the user a recognisable output from a bitstream this repository built.

#### Outcome:

The chaser works and it confirmed the mapping, corrected a polarity claim recorded an entry earlier, and exposed a reproducible clock failure that matters more than either. All eight lanes are now driven, one at a time, stepping at 4 Hz so a lap takes two seconds and every lane blinks at 0.5 Hz, with the step counted in the `sys_clk` domain so the marker is independent of every PLL in the design and cannot be confused with a clock report; the five per-clock lanes this replaces are gone, and what they exposed is not lost because the UART already carries the counters and both lock bits. The user reports the marker walking LED 1 through LED 8 in order and then repeating, which is the first hardware confirmation of the dock's interleave, recorded until now from Tang-Phosphor's constraint files and its `pmod_slot.sv`; it also retires the one assumption that entry 28's section 3 rested on, that the module's own LEDs run in lane order, since an out-of-order walk would have shown that assumption false and the walk is in order. The first load of the chaser produced a travelling HOLE rather than a travelling light: with the lit lane driven LOW the user saw a dark marker and the other seven lit, which makes this module active-HIGH, so the drive was inverted and the second build shows a lit marker travelling, which is the effect that was asked for. That makes entry 28's section 3 conclusion of active-low WRONG, and `evidence/clock-smoke-led-and-uart.txt` section 3 is marked corrected rather than rewritten; the likely error is the glance at two LEDs rather than the pin state, since `lock27` and `lock_hdmi` are active-high and were driven high, so those two lanes should have been lit on an active-high module and either they were misread or they were not driving. It also explains the power-on state the user reported, all eight lit with nothing loaded, because a ball with no design on it reads high. The chaser's evidence is preferred because it drives a lane known by construction, which is the third time this project has recorded that a claim generalised from one or two cells is not a measurement. The substantive finding is in the clock. The UART reports both PLL lock bits set and `clk27` at 1.0800 times `sys_clk` while the `hclk` count is exactly zero, in two different chaser builds each loaded after its own power cycle, against two pre-chaser loads of the same board that measured 2.9701 and 2.9700 times `sys_clk`; the loads were checked in the routed netlist rather than inferred, and `div5.HCLKIN` is driven by `hclk5`, `div5.CLKOUT` drives the net named `hclk`, that net clocks 25 counter flops, and `cnt_hclk[12]` -- the bit the report actually reads -- is driven by a flip-flop whose clock net is `hclk` and feeds the sampler whose count the UART prints. The design therefore states that `hclk` must toggle and be counted, and the count is zero, so the CLKDIV's output is not toggling on silicon in this design while it did in its predecessor. Losing the pin consumer of the counter's top bit is not the explanation: bit 12 still has a driven path and nextpnr still constrains `hclk` and reports endpoints for it. What is inferred, and deliberately not asserted, is that `hclk5` reaches the CLKDIV over the general-fabric fallback after its single `Failed to route ... using dedicated routing`, and that this fallback is fragile enough to be broken by an unrelated change to the I/O and a little `sys_clk` logic. That inference is why this is worth recording: it is the desktop core's open candidate in miniature, since section 18 records that the working vendor build drives lane 0 of the HCLK block from the dedicated inter-HCLK wire while ours arrives over fabric, and a small design in which a 371.25 to 74.25 MHz division either works or does not, with a UART to say which, is the instrument that question has lacked. One measurement was discarded rather than counted: a load made without a power cycle produced a plausible 2.5874 times `sys_clk` for a design that cannot produce it, the user stopped the capture and named the cause, and `TOOLCHAIN.md` now records in its board-side section that a power cycle precedes every load, which core-log entry 8 had measured and which still cost a false reading here. The run is recorded in `evidence/clock-smoke-chaser.txt` with both bitstream digests, the whole session's `hclk` readings in order including the discarded one, what was checked in the routed netlist, and the discrimination still owed. The required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed `core.md` was not changed and that this entry is the only `.ai` change, and validated it as number 29 of the active log with a conforming four-field header, six sections in canonical order, prose in Outcome and Next Steps, an allowed Status set, and no rewrite of settled history. No part of this repository, TinyTang or Tang-Phosphor was found to use intellectual property beyond what `THIRD_PARTY.md` already records.

#### Next Steps:

Discriminate the `hclk` failure before drawing anything from it, because the two candidate causes have different consequences and one build separates them: keep the chaser but drive only the original five lanes, leaving IO5, IO6 and IO7 unconsumed, and see whether `hclk` returns; if it does, the three extra driven lanes are what disturbs the `hclk5` fallback, and if it does not, the chaser's own `sys_clk` logic is, and either answer is a measurement about how fragile that fallback is. Compare the two routed netlists' `hclk5` wire sets while doing it, from nextpnr's own state rather than from the tables, since that is where the difference must be if the fallback is the mechanism and the project has already lost eight cycles to reads of the wrong structure. Then take the answer back to the display, which is what this is all for: sections 18 and 19 of `evidence/desktop-clock-routing.txt` remain the handoff, section 4 of `evidence/clock-smoke-chaser.txt` is now the instrument for the clock half of it, and the serialiser attribute half still needs comparing at the fuse level at the three TMDS tiles rather than as attribute lists because the decoder aliases `FCLKSEL` values. Keep the discarded-power-cycle rule in mind on every load, and do not re-walk the polarity claim in `clock-smoke-led-and-uart.txt` section 3 -- it is corrected here and the correction is the measurement.

#### Files Modified:

- fpga/clock-smoke/clock_smoke.v
- fpga/clock-smoke/clock_smoke.cst
- evidence/clock-smoke-chaser.txt
- evidence/clock-smoke-led-and-uart.txt
- TOOLCHAIN.md

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 30 COMMIT Unreleased 2026-10-09T10:20:20-07:00

#### Coming From:

Unreleased 069d404

#### Purpose:

Make the clock-smoke panel cover all three of the desktop core's PLLs and measure each one, so that a PLL's ability to take a divider and produce the frequency asked for is established before the HDMI is touched again.

#### Outcome:

The third PLL now exists in the instrument, is measured rather than inferred, and measuring it forced the correction of a two-times error in this project's own decoder that five entries had built conclusions on. `pll_nes` was added on PLL_B[1] at X32Y108, the same site the desktop core's own place-and-route used, so this design holds the trio the real core holds, PLL_L[1], PLL_L[3] and PLL_B[1], and nextpnr reports three of twelve PLLs placed; its configuration is the desktop core's own, MDIV 40 to a 2000 MHz VCO and ODIV0 93 to 21.505 MHz. Until this cycle that clock's correctness was inferred only: the desktop core's keylink answered coherently at a baud derived from it, which argues the clock is right without measuring anything. The eight lanes became a liveness panel in which each heartbeat's divider sits IN THE CLOCK'S OWN DOMAIN, which is the property that makes a lane a witness to that clock and to nothing else, a divider clocked by sys_clk proving only that sys_clk is alive; each modulus is that clock's cycles in half a second at its nominal frequency, so a lane blinks at exactly 1 Hz when the clock is right and at 2 Hz when it is wrong by a factor of two, and the three spare lanes are held high so that nothing on the panel is dark by accident and any dark lane is a fault whose kind is read from its position. The report grew to 58 bytes with three lock bits and three rates, `clock-smoke s=A lock=DEF c27=XXXX hk=XXXX ns=XXXX n=XXXX`, and the first load after a power cycle returned every one of 37 lines reading `lock=111` with no sample skipped: all three PLLs lock, and the three outputs measure 26.9982, 74.2452 and 21.5040 MHz against designed 27.00, 74.25 and 21.50. The user reports the four heartbeat lanes blinking at 1 Hz and in phase, which is both the design's prediction and the sync question answered on hardware, since there is no second oscillator here for anything to drift against. The correction the panel forced is the cycle's most important result. The design counts EDGES of bit 12 of each counter; that bit has a period of 8192 cycles and yields two edges per period, so a count of N edges spans N times 4096 cycles, where tools/decode-clock-smoke.py multiplied by 8192 on the reading that an edge count is a cycle count. Every rate it reported since entry 7 was twice the truth, and the disagreement was confirmed three ways without the corrected script: by the panel, whose four lanes blink at 1 Hz in phase and could not if clk27 were 54 MHz; by hand arithmetic on a raw capture, where c27 advancing 0x1148 per line gives 4424 times 4096 over 2^25 equals 0.5400 times sys_clk and hk advancing 0x2F76 gives 1.4832; and by the record itself, since decoding with the corrected factor reproduces the 74.2452 MHz that `evidence/clock-smoke-readout.txt` recorded before entry 7 changed that factor. The design's own SDC had said 27 MHz for clk27 all along while the decoder reported 54 for the same net, and a constraint file and a measurement contradicting each other for five cycles went unreconciled. What this overturns is that the committed design was never doubled, and that the ODIV conclusion inverts: the field is a straight divisor, so 50 divides by 50 exactly as the design asks and 100 halves the output to 13.5 MHz, which is what entry 9's six power-cycled variant-B runs say when re-read through the corrected factor. The desktop core's `ODIV0_SEL = 100`, the workaround entries 10 and 11 landed, is therefore a two-times error that halves pll_27 to 13.5 MHz, halves pll_hdmi's reference, and puts hclk5 at 185.6 MHz instead of 371.25, half the TMDS bit clock, in the very bitstream loaded on 2026-10-09; it does not by itself crack the display, because entry 11 compared two pixel rates and the valid one was dark, but the current core now carries two defects and the known one should be removed before the unknown one is tested. Two smaller results are recorded rather than left. The hclk anomaly from entry 29 is bounded: the chaser's two builds reported hclk as zero while this panel and the two pre-chaser builds report it alive, with zero route errors and a timing pass in all four, so it is placement-dependent rather than design-dependent and remains unexplained in mechanism but reproducible and measurable. And the readout's `s=` field reads 0 on every line when it should alternate at 1.49 Hz, because `cnt_sys` is declared `reg [24:0]` and comes back as 24 flop cells so bit 24 is gone -- the same silent trim the RTL's own comment says `(* keep *)` was added to prevent, which it is evidently not preventing for that counter; nothing depends on the field today but it is recorded rather than left as a loose end. The decoder's message format changed with the design, so captures older than this cycle no longer parse, which is expected and is stated in the evidence; five evidence files that carry the two-times rates now open with a correction banner naming the factor, the inversion, and this entry. The required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed `core.md` was not changed and that this entry is the only `.ai` change, and validated it as number 30 of the active log with a conforming four-field header, six sections in canonical order, prose in Outcome and Next Steps, an allowed Status set, and no rewrite of settled history. No part of this repository, TinyTang or Tang-Phosphor was found to use intellectual property beyond what `THIRD_PARTY.md` already records.

#### Next Steps:

Run the sweep, which is what the instrument was built for and is now a script rather than an investigation: change one PLL's divider, rebuild, load after a power cycle, and confirm the measured rate follows the request, one PLL at a time, with the UART as the number and the panel as the light; a rate that does not follow the request is the finding, and a rate that does is the capability the user asked to have established before the HDMI is touched. Then revert the desktop core's `ODIV0_SEL` from 100 to 50, because with the decoder corrected that value is a two-times error that halves its pll_27 and its hclk5, and it is in the core as committed; a rebuild and a reload there removes a known confound so that a dark screen means something new rather than something already understood. Keep the power-cycle rule on every load, since a load onto a running board produced a plausible and meaningless reading this session. The `(* keep *)` that is not holding for `cnt_sys` deserves a look the next time the readout is touched, and the readings corrected here -- the doubled clocks, the ODIV0 halving, and any conclusion drawn from either -- should not be re-walked in their original form.

#### Files Modified:

- fpga/clock-smoke/clock_smoke.v
- fpga/clock-smoke/clock_smoke.cst
- fpga/clock-smoke/clock_smoke.sdc
- tools/decode-clock-smoke.py
- evidence/clock-smoke-panel.txt
- evidence/clock-smoke-divider-runs.txt
- evidence/clock-smoke-six-runs.txt
- evidence/clock-smoke-led-and-uart.txt
- evidence/clock-smoke-chaser.txt
- evidence/desktop-display-cycle.txt

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 31 COMMIT Unreleased 2026-10-09T10:45:09-07:00

#### Coming From:

Unreleased cc313c0

#### Purpose:

Run the sweep's first step by setting pll_27's ODIV0_SEL to the value whose meaning five entries got wrong, and diagnose the phase drift the user reported on one lane.

#### Outcome:

The divider is a straight divisor, measured on silicon, and the drift was this project's arithmetic rather than the PLL's. The user reported that lane 4 walked against lanes 1 to 3 -- a small fast phase shift, plainly out of sync after two or three minutes, while 1 to 3 stayed locked -- and estimated the beat at about an hour, saying they would have liked to catch it but could not watch that long. They were right on both counts and wrong about the cause: pll_nes has a 2000 MHz VCO and a divider of 93, so it produces 21.505376 MHz and cannot produce a round 21.5, and the modulus had been written for 21.5, a 250 ppm error. Four independent views agree. The eye gave a beat of about an hour; arithmetic gives 250 ppm, one slip every 4000 s or 67 minutes; a 180-second capture gives lanes 1 to 3 all blinking at 0.999936 Hz against lane 4 at 1.000185 Hz, a difference of 249.2 ppm and a beat of 0.2492 mHz, one slip every 66.9 minutes; and the measured ratios settle the cause, because clk_nes sits within 0.8 ppm of its designed ratio and the PLL is therefore exact. Those ratios are reference-free -- both the clock and sys_clk scale with the same crystal so its error cancels -- which is what makes this a PLL measurement and not a crystal one: clk27 landed 0.2 ppm from its designed ratio, hclk 0.3 and clk_nes 0.8, all three at the limit of what 398 lines resolve. Lanes 1 to 3 stand still for the same reason: their nominals are exact and the crystal's 65 ppm error is common to all three, and a common error is a fixed phase offset rather than a drift. The modulus is corrected to 10,752,688 cycles, half a second at the achievable 21.505376 MHz, with a comment saying that a modulus taken from a requested frequency rather than an achievable one is a deliberate drift and belongs in a test rather than a default. A side result is recorded because it corrects an earlier claim: the 1 Hz panel resolved a 249 ppm difference by eye in two or three minutes, where an earlier reading here dismissed 1 Hz LEDs as far too coarse for anything small and prescribed a TIA for the work. The sweep step itself then measured cleanly: with pll_27's ODIV0_SEL taken from 50 to 100, clk27 reads 0.2700 times sys_clk or 13.4992 MHz against 0.5400 before, hclk reads 0.7425 or 37.1226 against 1.4850, and clk_nes is UNCHANGED at 0.4301 -- 90 lines over 60 seconds, every one of them lock=111, no sample skipped. pll_hdmi follows because its reference is clk27, its VCO landing at 742.5 MHz which is still inside the fitted 650 to 1300 MHz band, which is why it still locks; pll_nes does not move at all, because it runs from the crystal and not from clk27, so the tree's dependency structure is now shown on hardware rather than argued. One divider changed, exactly the two clocks downstream of it moved by exactly the predicted factor, the independent one did not, and the user reports all four heartbeat lanes locked and holding with the drift gone -- which is the capability this cycle was for. The consequence matters more than the demonstration. The desktop core carries ODIV0_SEL = 100, the workaround entries 10 and 11 landed on the strength of the decoder error, and it is now MEASURED that the value halves its pll_27 to 13.5 MHz, halves pll_hdmi's VCO to 742.5, and puts its hclk5 at 185.625 MHz instead of 371.25 -- half the TMDS bit clock, in the bitstream loaded on 2026-10-09. Entry 11's comparison of two pixel rates still stands and the pixel clock is still not the display's cause; what this does is remove a known two-times defect from a core that is carrying it before the unknown one is tested again. One thing the user raised and this entry leaves open: the CASCADE ORDER they see, lane 3 then lane 2 then lane 1, is not what the clock tree implies, since sys_clk should start first with no PLL to lock and hclk last after two PLLs and the CLKDIV; a mirrored numbering is ruled out by the chaser's in-order walk, the UART cannot see phase, and it needs either a phase instrument or a deliberate test. `FINDINGS.md` section 7 now puts the ODIV0 revert first and says why, `evidence/desktop-display-cycle.txt` carries the measurement beside its correction banner, the panel evidence records the corrected modulus, and `evidence/clock-smoke-sweep.txt` holds the drift diagnosis, the fix, the sweep measurement and what remains open. The required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed `core.md` was not changed and that this entry is the only `.ai` change, and validated it as number 31 of the active log with a conforming four-field header, six sections in canonical order, prose in Outcome and Next Steps, an allowed Status set, and no rewrite of settled history. No part of this repository, TinyTang or Tang-Phosphor was found to use intellectual property beyond what `THIRD_PARTY.md` already records.

#### Next Steps:

Revert the desktop core's `ODIV0_SEL` from 100 to 50, rebuild it and load it after a power cycle, because that single number is now measured to halve its pll_27 and therefore its hclk5 to 185.625 MHz, and a core carrying a known two-times defect should not be used to test an unknown one; the HDMI is the next thing after that, with sections 18 and 19 of `evidence/desktop-clock-routing.txt` still the handoff for it. Continue the sweep from here, since the mechanism is proven and each rung is cheap: a deliberately fast beat is the best next one, because a one per cent offset turns the 67-minute beat into about ten seconds and makes the arithmetic visible in a single glance, and other dividers on other PLLs follow the same shape. Give the cascade order a real look when a phase instrument exists or a deliberate test can be built, since it is the one observation from the user that no counter here can confirm or deny. Keep the power-cycle rule on every load, keep `/home/vash/tools` as the durable home for builds, and do not re-walk the doubled clocks or the ODIV0 halving, both corrected in entry 30 and both now measured here.

#### Files Modified:

- fpga/clock-smoke/clock_smoke.v
- evidence/clock-smoke-sweep.txt
- evidence/clock-smoke-panel.txt
- evidence/desktop-display-cycle.txt
- FINDINGS.md

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 32 COMMIT Unreleased 2026-10-09T11:04:41-07:00

#### Coming From:

Unreleased 6ea8b47

#### Purpose:

Give the four working lanes a heartbeat instead of a blink, one beat a second at the ordinary adult cardiac shape, so that all three PLLs are exercised into a shape the eye can judge rather than a duty cycle it cannot.

#### Outcome:

The four lanes now beat like a heart, each clocked by its own clock, and the waveform is verified without a board. The panel keeps its four lanes -- sys_clk, clk27, hclk and clk_nes, one per LED, LEDs 5 to 8 still the three lock flags -- but a blink becomes a new `heartbeat` module instantiated once per lane and clocked by the very clock it measures: `TICK_DIV` is that clock's cycles in one millisecond, so a tick IS a millisecond whichever clock counts it, `TICKS` is 1000, and a beat is therefore one second, which is 60 beats a minute; nothing divides one clock by another, and no lane depends on another lane or on the 50 MHz reference, so each lane is still a witness to its own clock. Each beat carries two sounds, a loud S1 and a quieter S2, each a fast attack and a slow decay, which is what a pulse both sounds and looks like, with the loudness carried on PWM: `pwm` free-runs through 256 values in the lane's own clock and the LED is high while `pwm` is below the envelope, so mean brightness is the envelope over 256 and the carrier is that clock over 256, 84 to 290 kHz across these four clocks, far above anything an eye resolves. This build also returns `pll_27.ODIV0_SEL` to 50, its nominal point, so all four clocks are nominal together and the four hearts beat together; the previous build carried 100 as the sweep's step 1. The waveform is verified by `tools/test-heartbeat-waveform.sh`, a new deterministic tool beside the decoder: the whole design cannot be simulated because `PLL` and `CLKDIV` are Gowin primitives with no model here, so the tool extracts the primitive-free `heartbeat` module and simulates one beat of it at `TICK_DIV` 1000, the smallest tick that still contains the 256-clock PWM carrier, with every figure the module reports in ticks and a tick a millisecond by construction so the simulated timing is the design's timing. It measures and asserts S1 107 ms wide beginning at the beat, S2 68 ms wide beginning at 332 ms, 598 ms of diastole, 1000 ms per beat, and brightness tracking the envelope to within 6 of 256, and it exits non-zero if any of those move, so the shape is now a regression rather than a one-off. Simulating it taught two things worth keeping. Nothing in `clock_smoke.v` has a reset and that is load bearing: the design relies on Gowin flops powering up at zero, which every build so far has silently depended on, and a simulator starting at x sat at x forever until the testbench forced the state a real device begins in -- fine as bring-up practice, but a real reset is warranted if this instrument grows. And the PWM carrier has to be far shorter than the tick: a first attempt simulated a tick small enough that the 256-clock carrier outran it and brightness aliased back and forth, a testbench artifact that states a real constraint. The build itself is clean on the same flow as every build since entry 7, `yosys` then `nextpnr-himbaechel` then `gowin_pack`: the artifact `/home/vash/tools/clock-smoke/clock-smoke.fs` has sha256 `ea4a9b9fa54417b1f27b4601b32f86bcb5988816f6c4093c9bbf1093ff85aa3c` and is 34,668,145 bytes, there are no timing failures, and post-route maximum frequency is 202.51 MHz for clk27 against its 27.00, 189.50 for hclk against 74.25, 167.50 for clk_nes against 21.50 and 181.88 for the sys domain, with the usual dedicated-router fallbacks of 75 attempts on clk27, 74 on clk_nes and 1 on hclk5 all fabric-routed, which at these rates are harmless. One constraint caveat is recorded because it bounds how much a future number from this SDC can be trusted: the `create_clock` lines for `sys_clk` and `hclk5` do not appear to bind, the report naming the sys domain `hb_sys.clk` and constraining it at nextpnr's 12 MHz default rather than the 20 ns asked for, which changes no conclusion here because that domain's maximum frequency is 181.88 MHz and so passes 50 MHz too. This cycle stops before deployment and that is a deferral rather than a failure: the heartbeat has never been on the board, no power cycle was taken because the user was still watching the build entry 31 deployed, and they asked for the cycle to be logged and pushed as it stands, which the log's rules allow when the user defers a cycle after implementation began. That watch is worth recording even though it tests the previous artifact and not this one: the user held `57dcef1c` for fifteen minutes and reports all four lanes still locked and in phase, against the three minutes entry 31 recorded, and since the drift entry 31 diagnosed was a quarter per thousand and showed a visible slip inside two or three minutes, fifteen minutes with no drift is a strong negative and closes the drift question for the 1 Hz heartbeats; entry 31's artifact is the one under test there, and entry 31's User Test already records that acceptance, which is why this entry claims no user test of its own. The required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed `core.md` was not changed and that this entry is the only `.ai` change, and validated it as number 32 of the active log with a conforming four-field header, six sections in canonical order, prose in Outcome and Next Steps, an allowed Status set, and no rewrite of settled history. No part of this repository, TinyTang or Tang-Phosphor was found to use intellectual property beyond what `THIRD_PARTY.md` already records.

#### Next Steps:

Deploy the heartbeat build after a power cycle, since `ea4a9b9f` has never been on the board, and have the user confirm that all four lanes beat together at a rate they can count against a clock, which is the user test this cycle deferred and the first thing to close. Then take the desktop core's `ODIV0_SEL` from 100 to 50, rebuild it and load it, because entry 31 measured that this single number halves its pll_27 and therefore its hclk5 to 185.625 MHz, half the TMDS bit clock, and it is the open thread entry 31 handed over; the HDMI comes after that, with sections 18 and 19 of `evidence/desktop-clock-routing.txt` still the handoff. Two smaller things stay open and neither blocks the above: the cascade order the user sees, lanes 3 then 2 then 1, still wants a phase instrument or a deliberate test, and the SDC's `sys_clk` and `hclk5` constraints want binding before any marginal timing number from this design is believed. Keep the power-cycle rule on every load, keep `/home/vash/tools` as the durable home for builds, and do not re-walk the doubled clocks or the ODIV0 halving, both measured in entry 31.

#### Files Modified:

- fpga/clock-smoke/clock_smoke.v
- tools/test-heartbeat-waveform.sh
- evidence/clock-smoke-heartbeat.txt

#### Status:

- Build: PASS
- Deployment: NOT RUN
- User Test: NOT RUN

---
