// clock-smoke: the desktop core's clock chain, isolated and nothing else.
//
// The desktop core's display path needs three things that nothing has yet
// proven on real silicon, all of them in the chain below:
//
//   sys_clk 50 MHz -> pll_27 (VCO 1350 MHz) -> clk27 27 MHz
//                  -> pll_hdmi (VCO 1485 MHz) -> hclk5 371.25 MHz
//                  -> CLKDIV 5 -> hclk 74.25 MHz
//
// Both VCOs sit above the 1300 MHz figure `gowin_pack` refused before this
// project extended the charge-pump model with measured points, so a locking
// pair is evidence for that extension, on hardware, independent of the
// desktop core's other 8,500 cells.
//
// ---------------------------------------------------------------- readout
//
// The readout is the FPGA's UART (ball U15), not LEDs, and that is a measured
// correction rather than a preference.  The first version of this design drove
// `led[0..4]` at the balls Apicula's `tangconsole138k.cst` calls `led[0]` ..
// `led[4]` -- W19, F19, E22, W20, F20.  On this carrier those are not LEDs:
// `Tang_Mega_138K_Console_32001C__Schematics.pdf` sheet /SOM_BTB0/ maps them to
// PMOD1_IO0 (W19), PMOD1_IO1 (W20), PMOD1_IO2 (F19), PMOD1_IO3 (F20) and
// PMOD1_IO4 (E22) on the PMOD1 header.  The console has no FPGA-driven LED at
// all -- its one status LED, `LED1`, is wired to the FPGA's dedicated READY and
// DONE configuration nets and to SYS_ACT, none of which fabric drives.  All
// eight of those balls are driven here instead, under their real names, as a
// clock-liveness panel on the PMOD1 header -- see the panel block at the end of
// this file for what each lane means, its polarity, and why each heartbeat sits
// in its own clock domain.  The UART report is unchanged and still carries the
// counts, so a lane says alive-or-not by eye and a number says at what rate.
//
// The UART is clocked by `sys_clk` alone, so it keeps reporting even if every
// PLL is dead -- which is exactly the case worth being able to see.  It sends
// one fixed 58-byte line:
//
//   clock-smoke s=A lock=DEF c27=XXXX hk=XXXX ns=XXXX n=XXXX\r\n
//
//      s     cnt_sys[24], a sanity bit for the 50 MHz input
//      D E F pll_27, pll_hdmi and pll_nes LOCK
//      c27   count of clk27's bit-12 edges
//      hk    the same for hclk, the CLKDIV output
//      ns    the same for clk_nes, pll_nes's output
//      n     a counter of lines sent, so the design states its own time base
//
// c27 and hk are COUNTS rather than bits, and that is the point.  A reader
// turns a count of bit-8 edges into cycles without knowing which bit was read,
// which is what the two earlier versions of this readout could not do: a flop
// count does not reveal a bit's position, so a real doubling of a PLL and a
// reporting error were indistinguishable.
//
// A line is sent every 2^25 = 33,554,432 `sys_clk` cycles -- 671.08864 ms at
// 50 MHz -- and nothing else in the design can delay that.  The slow cadence is
// not a choice: the one-wire path that carries this UART to the host only
// delivers about 100-170 B/s, measured, and a faster readout swamps its bridge
// and arrives as nothing at all.  Counting *lines* between two edges of a clock's bit 8 gives that
// clock three ways over -- the count itself, the line period, and hence cycles
// per line -- with the 50 MHz crystal as the only reference, so a wrong rate
// is visible rather than merely "off".  hclk5 gets no counter of its own: a
// 371.25 MHz flop path fails timing here (288.77 MHz against 371.33 required,
// measured on this design's first version), and hclk is hclk5/5, so a correct
// hclk rate is what establishes hclk5. SPDX-License-Identifier: MIT

`default_nettype none

module clock_smoke (
    input  wire sys_clk,
    output wire uart_tx,
    output wire pmod1_io0,
    output wire pmod1_io1,
    output wire pmod1_io2,
    output wire pmod1_io3,
    output wire pmod1_io4,
    output wire pmod1_io5,
    output wire pmod1_io6,
    output wire pmod1_io7
);

    wire gw_vcc;
    wire gw_gnd;
    assign gw_vcc = 1'b1;
    assign gw_gnd = 1'b0;

    wire clk27;
    wire hclk5;
    wire hclk;
    wire lock27;
    wire lock_hdmi;
    wire clk_nes;
    wire lock_nes;

    // ---------------------------------------------------------------- clocks

    // 50 MHz in, 27 MHz out.  IDIV 1, FBDIV 1, MDIV 27 -> VCO 1350 MHz,
    // ODIV0 50 -> 27 MHz.  The desktop core's own operating point.
    PLL pll_27 (
        .LOCK       (lock27),
        .CLKOUT0    (clk27),
        .CLKOUT1    (),
        .CLKOUT2    (),
        .CLKOUT3    (),
        .CLKOUT4    (),
        .CLKOUT5    (),
        .CLKOUT6    (),
        .CLKFBOUT   (),
        .CLKIN      (sys_clk),
        .CLKFB      (gw_gnd),
        .RESET      (gw_gnd),
        .PLLPWD     (gw_gnd),
        .RESET_I    (gw_gnd),
        .RESET_O    (gw_gnd),
        .FBDSEL     (6'b0),
        .IDSEL      (6'b0),
        .MDSEL      (7'b0),
        .MDSEL_FRAC (3'b0),
        .ODSEL0     (7'b0),
        .ODSEL0_FRAC(3'b0),
        .ODSEL1     (7'b0),
        .ODSEL2     (7'b0),
        .ODSEL3     (7'b0),
        .ODSEL4     (7'b0),
        .ODSEL5     (7'b0),
        .ODSEL6     (7'b0),
        .DT0        (4'b0),
        .DT1        (4'b0),
        .DT2        (4'b0),
        .DT3        (4'b0),
        .ICPSEL     (6'b0),
        .LPFRES     (3'b0),
        .LPFCAP     (2'b0),
        .PSSEL      (3'b0),
        .PSDIR      (gw_gnd),
        .PSPULSE    (gw_gnd),
        .ENCLK0     (gw_vcc),
        .ENCLK1     (gw_vcc),
        .ENCLK2     (gw_vcc),
        .ENCLK3     (gw_vcc),
        .ENCLK4     (gw_vcc),
        .ENCLK5     (gw_vcc),
        .ENCLK6     (gw_vcc),
        .SSCPOL     (gw_gnd),
        .SSCON      (gw_gnd),
        .SSCMDSEL   (7'b0),
        .SSCMDSEL_FRAC(3'b0)
    );
    defparam pll_27.FCLKIN = "50";
    defparam pll_27.IDIV_SEL = 1;
    defparam pll_27.FBDIV_SEL = 1;
    defparam pll_27.MDIV_SEL = 27;
    defparam pll_27.MDIV_FRAC_SEL = 0;
    // SWEEP STEP 1.  ODIV0_SEL is the field whose interpretation was wrong for
    // five core-log entries: with the decoder's 2x factor removed the recorded
    // variant-B runs say it is a STRAIGHT DIVISOR, so 100 must halve this
    // output to 13.5 MHz and carry hclk5 down with it to 185.625.  If clk27
    // measures 0.2700 x sys_clk instead of 0.5400, the divisor reading is
    // confirmed on silicon and the desktop core's ODIV0_SEL = 100 is the 2x
    // error entry 30 says it is.  If it stays at 0.5400, that value is special
    // and the old halving reading was right after all.
    defparam pll_27.ODIV0_SEL = 100;
    defparam pll_27.CLKOUT0_EN = "TRUE";
    defparam pll_27.CLKFB_SEL = "INTERNAL";

    // 27 MHz in, 371.25 MHz out.  MDIV 55 -> VCO 1485 MHz, ODIV0 4.
    PLL pll_hdmi (
        .LOCK       (lock_hdmi),
        .CLKOUT0    (hclk5),
        .CLKOUT1    (),
        .CLKOUT2    (),
        .CLKOUT3    (),
        .CLKOUT4    (),
        .CLKOUT5    (),
        .CLKOUT6    (),
        .CLKFBOUT   (),
        .CLKIN      (clk27),
        .CLKFB      (gw_gnd),
        .RESET      (gw_gnd),
        .PLLPWD     (gw_gnd),
        .RESET_I    (gw_gnd),
        .RESET_O    (gw_gnd),
        .FBDSEL     (6'b0),
        .IDSEL      (6'b0),
        .MDSEL      (7'b0),
        .MDSEL_FRAC (3'b0),
        .ODSEL0     (7'b0),
        .ODSEL0_FRAC(3'b0),
        .ODSEL1     (7'b0),
        .ODSEL2     (7'b0),
        .ODSEL3     (7'b0),
        .ODSEL4     (7'b0),
        .ODSEL5     (7'b0),
        .ODSEL6     (7'b0),
        .DT0        (4'b0),
        .DT1        (4'b0),
        .DT2        (4'b0),
        .DT3        (4'b0),
        .ICPSEL     (6'b0),
        .LPFRES     (3'b0),
        .LPFCAP     (2'b0),
        .PSSEL      (3'b0),
        .PSDIR      (gw_gnd),
        .PSPULSE    (gw_gnd),
        .ENCLK0     (gw_vcc),
        .ENCLK1     (gw_vcc),
        .ENCLK2     (gw_vcc),
        .ENCLK3     (gw_vcc),
        .ENCLK4     (gw_vcc),
        .ENCLK5     (gw_vcc),
        .ENCLK6     (gw_vcc),
        .SSCPOL     (gw_gnd),
        .SSCON      (gw_gnd),
        .SSCMDSEL   (7'b0),
        .SSCMDSEL_FRAC(3'b0)
    );
    defparam pll_hdmi.FCLKIN = "27";
    defparam pll_hdmi.IDIV_SEL = 1;
    defparam pll_hdmi.FBDIV_SEL = 1;
    defparam pll_hdmi.MDIV_SEL = 55;
    defparam pll_hdmi.MDIV_FRAC_SEL = 0;
    defparam pll_hdmi.ODIV0_SEL = 4;
    defparam pll_hdmi.CLKOUT0_EN = "TRUE";
    defparam pll_hdmi.CLKFB_SEL = "INTERNAL";

    // 50 MHz in, 21.5 MHz out: the desktop core's THIRD PLL, and the one this
    // project has never measured directly -- its working state was only ever
    // inferred from the desktop core's keylink answering coherently at a baud
    // derived from this clock.  MDIV 40 -> VCO 2000 MHz, ODIV0 93 -> 21.505 MHz.
    // Its site is PLL_B[1] at X32Y108, the same site the desktop core's own
    // place-and-route used, so this design holds the same trio of PLL sites:
    // PLL_L[1], PLL_L[3] and PLL_B[1].
    PLL pll_nes (
        .LOCK       (lock_nes),
        .CLKOUT0    (clk_nes),
        .CLKOUT1    (),
        .CLKOUT2    (),
        .CLKOUT3    (),
        .CLKOUT4    (),
        .CLKOUT5    (),
        .CLKOUT6    (),
        .CLKFBOUT   (),
        .CLKIN      (sys_clk),
        .CLKFB      (gw_gnd),
        .RESET      (gw_gnd),
        .PLLPWD     (gw_gnd),
        .RESET_I    (gw_gnd),
        .RESET_O    (gw_gnd),
        .FBDSEL     (6'b0),
        .IDSEL      (6'b0),
        .MDSEL      (7'b0),
        .MDSEL_FRAC (3'b0),
        .ODSEL0     (7'b0),
        .ODSEL0_FRAC(3'b0),
        .ODSEL1     (7'b0),
        .ODSEL2     (7'b0),
        .ODSEL3     (7'b0),
        .ODSEL4     (7'b0),
        .ODSEL5     (7'b0),
        .ODSEL6     (7'b0),
        .DT0        (4'b0),
        .DT1        (4'b0),
        .DT2        (4'b0),
        .DT3        (4'b0),
        .ICPSEL     (6'b0),
        .LPFRES     (3'b0),
        .LPFCAP     (2'b0),
        .PSSEL      (3'b0),
        .PSDIR      (gw_gnd),
        .PSPULSE    (gw_gnd),
        .ENCLK0     (gw_vcc),
        .ENCLK1     (gw_vcc),
        .ENCLK2     (gw_vcc),
        .ENCLK3     (gw_vcc),
        .ENCLK4     (gw_vcc),
        .ENCLK5     (gw_vcc),
        .ENCLK6     (gw_vcc),
        .SSCPOL     (gw_gnd),
        .SSCON      (gw_gnd),
        .SSCMDSEL   (7'b0),
        .SSCMDSEL_FRAC(3'b0)
    );
    defparam pll_nes.FCLKIN = "50";
    defparam pll_nes.IDIV_SEL = 1;
    defparam pll_nes.FBDIV_SEL = 1;
    defparam pll_nes.MDIV_SEL = 40;
    defparam pll_nes.MDIV_FRAC_SEL = 0;
    defparam pll_nes.ODIV0_SEL = 93;
    defparam pll_nes.CLKOUT0_EN = "TRUE";
    defparam pll_nes.CLKFB_SEL = "INTERNAL";

    // 371.25 -> 74.25 MHz, the plain pixel clock.  The desktop core's CLKDIV.
    //
    // The site is pinned by an attribute rather than a .cst line on purpose:
    // nextpnr's .cst reader cannot parse this die's CLKDIV spelling (the fuzz
    // campaign hit a fatal `Unknown placement macro` on `BOTTOMSIDE[4]`), and
    // the RTL `BEL` attribute is the spelling the open flow does take.
    // X181Y81 is HCLK block 3 and is where the desktop core's own div5 landed.
    (* BEL = "X181Y81/CLKDIV_3" *) CLKDIV #(.DIV_MODE(5)) div5 (
        .CLKOUT (hclk),
        .HCLKIN (hclk5),
        .RESETN (gw_vcc),
        .CALIB  (gw_gnd)
    );

    // ---------------------------------------------------------------- counters
    //
    // One counter per clock domain, each read out on its slowest bit.  The
    // three rates are distinct (~1.49, ~1.61 and ~2.21 Hz) so that a clock
    // running at the wrong rate, or not at all, is visible rather than merely
    // "off".  A counter with no consumer is optimised away, so each of these
    // exists because the report reads it.

    // `keep` on the counters is not decoration.  Without it yosys trims a
    // counter whose top bit is the only one read -- `cnt_sys[24]` came back as
    // 24 flops, not 25 -- so `cnt_sys[24]` silently became bit 23 and the
    // reported rate doubled.  Measured, and the reason this design's first
    // readout could not be trusted about absolutes.
    (* keep *) reg [24:0] cnt_sys;
    always @(posedge sys_clk) cnt_sys <= cnt_sys + 1'b1;

    (* keep *) reg [23:0] cnt_27;
    always @(posedge clk27) cnt_27 <= cnt_27 + 1'b1;

    (* keep *) reg [24:0] cnt_hclk;
    always @(posedge hclk) cnt_hclk <= cnt_hclk + 1'b1;

    (* keep *) reg [23:0] cnt_nes;
    always @(posedge clk_nes) cnt_nes <= cnt_nes + 1'b1;

    // clk27's and hclk's slow bits are sampled by sys_clk so one domain can
    // report on all three.  Two flops each: the report wants a sampled bit, not
    // a synchronised value, and it is only ever read by the UART below.
    reg [1:0] s27;
    reg [1:0] shclk;

    // ------------------------------------------------- counting, not reading
    //
    // Bit 12 of each counter toggles once every 4096 cycles of its own clock, so
    // crossing *that single bit* into sys_clk is a clean one-bit CDC -- no
    // tearing and no bit-index assumption -- and counting its edges in the sys
    // domain measures the clock as a NUMBER OF CYCLES rather than as a bit that
    // then has to be interpreted.  That distinction is the whole reason this
    // version exists: the previous readout could not tell a real doubling of a
    // PLL apart from a reporting error, because a flop count does not reveal
    // which bit is which.  A count does.
    //
    // Rates: bit 12 toggles at f/8192, which is 3.3 kHz for a 27 MHz clk27 and
    // 9.1 kHz for a 74.25 MHz hclk -- far below the 50 MHz sampling clock, so
    // no edge is ever missed, and the counts fit in 16 bits per line.
    reg [1:0]  q27;
    reg [1:0]  qhclk;
    reg [1:0]  qnes;
    reg [15:0] n27;
    reg [15:0] nhclk;
    reg [15:0] nnes;
    always @(posedge sys_clk) begin
        s27   <= {s27[0],   cnt_27[23]};
        shclk <= {shclk[0], cnt_hclk[24]};
        q27   <= {q27[0],   cnt_27[12]};
        qhclk <= {qhclk[0], cnt_hclk[12]};
        qnes  <= {qnes[0],  cnt_nes[12]};
        if (q27[1]   != q27[0])   n27   <= n27   + 16'd1;
        if (qhclk[1] != qhclk[0]) nhclk <= nhclk + 16'd1;
        if (qnes[1]  != qnes[0])  nnes  <= nnes  + 16'd1;
    end

    // ------------------------------------------------------------- line cadence
    //
    // Exactly 2^18 sys_clk cycles.  A line takes 33 x 10 x 434 = 143,220
    // cycles, so it always finishes inside the window and no tick is ever
    // skipped -- which is what lets a reader treat the period as exact.

    localparam CAD_BITS = 25;
    reg [CAD_BITS-1:0] cad;
    wire line_tick = (cad == {CAD_BITS{1'b1}});
    always @(posedge sys_clk) cad <= line_tick ? {CAD_BITS{1'b0}} : cad + 1'b1;

    // ----------------------------------------------------------- UART, 115200
    //
    // 50 MHz / 115200 = 434.03 -> 434, an error of +0.007% .  Characters go
    // out as 8N1, LSB first, with one idle bit between frames.

    localparam BAUD_DIV = 434;
    localparam MSG_LEN  = 58;

    // A line counter, reported in the message as four hex digits.  It exists
    // because the first version of this readout could not settle its own time
    // base from outside: whether the host was seeing every line, and how many
    // `sys_clk` cycles a line really spans, are both decided here rather than
    // inferred from a capture.  `n=` in two consecutive lines differing by one
    // is the capture being faithful; a repeat is a duplicated read.
    reg [31:0] cnt_line;
    function [7:0] hexd;
        input [3:0] v;
        begin
            hexd = (v < 4'd10) ? (8'h30 + {4'b0, v})
                               : (8'h61 + {4'b0, v} - 8'd10);
        end
    endfunction

    reg [15:0] baud;
    reg [3:0]  bit_idx;
    reg [5:0]  msg_idx;
    reg [5:0]  chars_left;
    reg        tx_busy;
    reg [9:0]  frame;

    wire [7:0] ch_s = cnt_sys[24] ? 8'h31 : 8'h30;
    wire [7:0] ch_d = lock27     ? 8'h31 : 8'h30;
    wire [7:0] ch_e = lock_hdmi  ? 8'h31 : 8'h30;
    wire [7:0] ch_f = lock_nes   ? 8'h31 : 8'h30;

    // "clock-smoke s=A lock=DEF c27=XXXX hk=XXXX ns=XXXX n=XXXX", one case
    // arm per byte.  c27, hk and ns are counts of that clock's bit-12 edges, so a
    // reader gets cycles per line and never has to know which bit was read; F is
    // pll_nes's LOCK bit.
    function [7:0] msg_byte;
        input [5:0] i;
        begin
            case (i)
                6'd0:  msg_byte = 8'h63; // c
                6'd1:  msg_byte = 8'h6c; // l
                6'd2:  msg_byte = 8'h6f; // o
                6'd3:  msg_byte = 8'h63; // c
                6'd4:  msg_byte = 8'h6b; // k
                6'd5:  msg_byte = 8'h2d; // -
                6'd6:  msg_byte = 8'h73; // s
                6'd7:  msg_byte = 8'h6d; // m
                6'd8:  msg_byte = 8'h6f; // o
                6'd9:  msg_byte = 8'h6b; // k
                6'd10: msg_byte = 8'h65;// e
                6'd11: msg_byte = 8'h20;//  
                6'd12: msg_byte = 8'h73;// s
                6'd13: msg_byte = 8'h3d;// =
                6'd14:  msg_byte = ch_s;
                6'd15: msg_byte = 8'h20;//  
                6'd16: msg_byte = 8'h6c;// l
                6'd17: msg_byte = 8'h6f;// o
                6'd18: msg_byte = 8'h63;// c
                6'd19: msg_byte = 8'h6b;// k
                6'd20: msg_byte = 8'h3d;// =
                6'd21:  msg_byte = ch_d;
                6'd22:  msg_byte = ch_e;
                6'd23:  msg_byte = ch_f;
                6'd24: msg_byte = 8'h20;//  
                6'd25: msg_byte = 8'h63;// c
                6'd26: msg_byte = 8'h32;// 2
                6'd27: msg_byte = 8'h37;// 7
                6'd28: msg_byte = 8'h3d;// =
                6'd29:  msg_byte = hexd(n27[15:12]);
                6'd30:  msg_byte = hexd(n27[11:8]);
                6'd31:  msg_byte = hexd(n27[7:4]);
                6'd32:  msg_byte = hexd(n27[3:0]);
                6'd33: msg_byte = 8'h20;//  
                6'd34: msg_byte = 8'h68;// h
                6'd35: msg_byte = 8'h6b;// k
                6'd36: msg_byte = 8'h3d;// =
                6'd37:  msg_byte = hexd(nhclk[15:12]);
                6'd38:  msg_byte = hexd(nhclk[11:8]);
                6'd39:  msg_byte = hexd(nhclk[7:4]);
                6'd40:  msg_byte = hexd(nhclk[3:0]);
                6'd41: msg_byte = 8'h20;//  
                6'd42: msg_byte = 8'h6e;// n
                6'd43: msg_byte = 8'h73;// s
                6'd44: msg_byte = 8'h3d;// =
                6'd45:  msg_byte = hexd(nnes[15:12]);
                6'd46:  msg_byte = hexd(nnes[11:8]);
                6'd47:  msg_byte = hexd(nnes[7:4]);
                6'd48:  msg_byte = hexd(nnes[3:0]);
                6'd49: msg_byte = 8'h20;//  
                6'd50: msg_byte = 8'h6e;// n
                6'd51: msg_byte = 8'h3d;// =
                6'd52:  msg_byte = hexd(cnt_line[15:12]);
                6'd53:  msg_byte = hexd(cnt_line[11:8]);
                6'd54:  msg_byte = hexd(cnt_line[7:4]);
                6'd55:  msg_byte = hexd(cnt_line[3:0]);
                6'd56: msg_byte = 8'h0d;// CR
                6'd57: msg_byte = 8'h0a;// LF
                default: msg_byte = 8'h20;
            endcase
        end
    endfunction

    // A line begins on the cadence tick itself and its characters run back to
    // back, so the whole 33-byte line occupies 33 x 10 x 434 = 143,220 sys_clk
    // cycles -- 2.86 ms -- well inside the 262,144-cycle window.  Restarting
    // `baud` at the tick is what makes every line exactly 2^18 cycles apart,
    // and chaining the characters is what makes a line one coherent sample
    // rather than 33 samples 5.24 ms apart.
    always @(posedge sys_clk) begin
        if (line_tick && !tx_busy) begin
            baud       <= 16'd0;
            frame      <= {1'b1, msg_byte(6'd0), 1'b0};  // stop, data, start
            bit_idx    <= 4'd0;
            tx_busy    <= 1'b1;
            msg_idx    <= 6'd0;
            chars_left <= MSG_LEN - 1;
            cnt_line   <= cnt_line + 32'd1;
        end else if (baud == BAUD_DIV - 1) begin
            baud <= 16'd0;
            if (tx_busy) begin
                if (bit_idx != 4'd9) begin
                    bit_idx <= bit_idx + 4'd1;
                end else if (chars_left != 0) begin
                    frame      <= {1'b1, msg_byte(msg_idx + 6'd1), 1'b0};
                    bit_idx    <= 4'd0;
                    msg_idx    <= msg_idx + 6'd1;
                    chars_left <= chars_left - 6'd1;
                end else begin
                    tx_busy <= 1'b0;
                end
            end
        end else begin
            baud <= baud + 16'd1;
        end
    end

    assign uart_tx = tx_busy ? frame[bit_idx] : 1'b1;

    // ------------------------------------------- PMOD1: a clock-liveness panel
    //
    // One lane per clock, each driven by a divider IN THAT CLOCK'S OWN DOMAIN,
    // so a blinking lane is a witness to that clock and to nothing else: if the
    // PLL stops, its counter stops, its toggle flop stays where it powered up,
    // and the lane goes dark.  A divider clocked by sys_clk would prove only
    // that sys_clk is alive, which is why every heartbeat below sits in its own
    // domain.
    //
    // Each modulus is that clock's cycles in HALF A SECOND at its NOMINAL
    // frequency, so each lane blinks at exactly 1 Hz when its clock is right.
    // The modulus is a test and not a convenience: a clock running at twice its
    // nominal rate blinks at 2 Hz, which is how the recorded ODIV0 halving would
    // show up as a light rather than as a UART field.
    //
    // All the clocks in this design are exact rational multiples of the one
    // 50 MHz crystal -- a PLL's output is an integer ratio of its own reference
    // -- so the lanes share one frequency exactly and have no independent
    // oscillator to drift against.  Their counters start together at
    // configuration, so they hold a FIXED phase offset; only a wrong ratio
    // moves one, and only grossly.  An error at the crystal's own tens-of-ppm
    // level is not visible by eye at all, which is why the UART counts stay.
    //
    // `hclk5` gets no lane of its own: a 371.25 MHz flop path fails timing here
    // (288.77 MHz measured against 371.33 required).  Its liveness rides on
    // `hclk`, which is hclk5/5.
    //
    // The three lanes with no indicator are driven HIGH rather than left
    // floating, so that nothing on the panel is dark by accident: this module
    // lights on HIGH, so ANY dark lane is a fault -- a clock that stopped or a
    // PLL that did not lock -- and which it is, is read from the lane's position.
    //
    // The modulus counters cannot be trimmed the way the raw-tap versions could:
    // every bit of each one feeds a comparison, so no bit index is implicit.
    localparam integer DIV_SYS   = 25_000_000;   // 50.00 MHz x 0.5 s
    localparam integer DIV_CLK27 = 13_500_000;   // 27.00 MHz x 0.5 s
    localparam integer DIV_HCLK  = 37_125_000;   // 74.25 MHz x 0.5 s
    // pll_nes cannot make a round 21.5 MHz: its VCO is 2000 MHz and its divider
    // is 93, so it produces 2000/93 = 21.505376 MHz.  This modulus is half a
    // second at THAT value, not at 21.5.  The first version used 21.5 and the
    // lane drifted 249 ppm against the other three -- one slip every 67 minutes,
    // which the user saw by eye and the UART then measured to 0.2%.  A modulus
    // taken from a requested frequency rather than an achievable one is a
    // deliberate drift, and it belongs in a test, not in a default.
    localparam integer DIV_NES   = 10_752_688;   // 21.505376 MHz x 0.5 s

    reg [24:0] hb_sys;
    reg [23:0] hb_27;
    reg [25:0] hb_hclk;
    reg [23:0] hb_nes;
    reg        led_sys, led_27, led_hclk, led_nes;

    always @(posedge sys_clk) begin
        if (hb_sys == DIV_SYS - 1) begin hb_sys <= 25'd0; led_sys <= ~led_sys; end
        else                             hb_sys <= hb_sys + 25'd1;
    end

    always @(posedge clk27) begin
        if (hb_27 == DIV_CLK27 - 1) begin hb_27 <= 24'd0; led_27 <= ~led_27; end
        else                            hb_27 <= hb_27 + 24'd1;
    end

    always @(posedge hclk) begin
        if (hb_hclk == DIV_HCLK - 1) begin hb_hclk <= 26'd0; led_hclk <= ~led_hclk; end
        else                              hb_hclk <= hb_hclk + 26'd1;
    end

    always @(posedge clk_nes) begin
        if (hb_nes == DIV_NES - 1) begin hb_nes <= 24'd0; led_nes <= ~led_nes; end
        else                           hb_nes <= hb_nes + 24'd1;
    end

    // Module lane n is module pin (1, 2, 3, 4, 7, 8, 9, 10)[n], and the dock
    // interleaves those onto IO0/2/4/6 for lanes 0-3 and IO1/3/5/7 for lanes
    // 4-7.  In module order the panel reads: sys_clk, clk27, hclk, spare,
    // pll_27 lock, pll_hdmi lock, spare, spare.
    assign pmod1_io0 = led_sys;      // LED 1 <- sys_clk  50.00 MHz  1 Hz
    assign pmod1_io2 = led_27;       // LED 2 <- clk27    27.00 MHz  1 Hz
    assign pmod1_io4 = led_hclk;     // LED 3 <- hclk     74.25 MHz  1 Hz
    assign pmod1_io6 = led_nes;      // LED 4 <- clk_nes  21.50 MHz  1 Hz
    assign pmod1_io1 = lock27;       // LED 5 <- pll_27    LOCK, steady
    assign pmod1_io3 = lock_hdmi;    // LED 6 <- pll_hdmi  LOCK, steady
    assign pmod1_io5 = lock_nes;     // LED 7 <- pll_nes   LOCK, steady
    assign pmod1_io7 = 1'b1;         // LED 8   spare
endmodule

`default_nettype wire
