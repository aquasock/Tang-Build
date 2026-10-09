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
    // SWEEP STEP 1 IS DONE and recorded in evidence/clock-smoke-sweep.txt: at
    // ODIV0_SEL = 100 this output measured 0.2700 x sys_clk against 0.5400, so
    // the field is a straight divisor, and the desktop core's ODIV0_SEL = 100 is
    // the two-times error entry 30 describes.  Back to 50 here, the value the
    // design asks for, so that all four clocks sit at their nominal rates and
    // the four heartbeats agree -- the point of this build is the shape, and four
    // lanes at four different rates would not show it.
    defparam pll_27.ODIV0_SEL = 50;
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

    wire [7:0] ch_s = hexd(env_ramp_probe[7:4]);
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
    // Each lane's light is a HEARTBEAT, and the beat is one second at that
    // clock's nominal rate -- 60 a minute, the ordinary adult resting figure --
    // so the four lanes beat together when the four clocks are at their nominal
    // rates and a clock that is wrong beats at the wrong rate.  The shape is the
    // two sounds a stethoscope hears, with PWM brightness for the envelope; the
    // `heartbeat` module at the end of this file holds the waveform.
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
    // The tick divisor is that clock's cycles per MILLISECOND, so every
    // boundary inside the heartbeat module is a count of milliseconds and the
    // waveform is the same in time on all four lanes.  Three of the four
    // divisors are exact; pll_nes's is 21,505.376 rounded down, a 17 ppm error,
    // which is one beat of slip in about sixteen hours.
    wire led_sys, led_27, led_hclk, led_nes;
    wire [7:0] env_sys;

    // The same sound on all four clocks, and DUTY_SHIFT is left at its default
    // of 8, which is a plain env/256 -- the shape accepted on the board.  A
    // carrier ladder and a duty ladder both ran and neither moved the look: what
    // this envelope needed was time, and the LEDs compress the top of the duty
    // range (6, 25, 50 and 100 per cent duty read as 70, 80, 90 and 100 per cent
    // brightness) without that mattering, since a fade from off to on reads as a
    // full excursion at any peak.  A sixteen-bit carrier is kept because it puts
    // the carrier at a few hundred hertz with no prescaler at all, and because
    // its extra levels are what let a lower duty range stay smooth if one is ever
    // wanted.
    heartbeat #(.TICK_DIV(50_000), .TICKS(1000)) hb_sys  (.clk(sys_clk), .led(led_sys), .env_out(env_sys));
    heartbeat #(.TICK_DIV(27_000), .TICKS(1000)) hb_27   (.clk(clk27),   .led(led_27));
    heartbeat #(.TICK_DIV(74_250), .TICKS(1000)) hb_hclk (.clk(hclk),    .led(led_hclk));
    heartbeat #(.TICK_DIV(21_505), .TICKS(1000)) hb_nes  (.clk(clk_nes), .led(led_nes));

    wire blip_27, blip_hdmi, blip_nes, led_breath;

    // The lock lanes echo the beat: the same sound, single (S2_EN 0) and crisp
    // (FALL 4, so it is over in about 107 ms), each beginning later than the
    // last so the three of them ring down through the dark half of the second.
    // Each is still clocked by its own clock, and each is gated by its own lock
    // at the pin, so a PLL that loses lock goes dark rather than lying.
    heartbeat #(.TICK_DIV(27_000), .TICKS(1000), .DELAY_MS(550), .S2_EN(0), .FALL(8'd4)) echo_27   (.clk(clk27),   .led(blip_27));
    heartbeat #(.TICK_DIV(74_250), .TICKS(1000), .DELAY_MS(700), .S2_EN(0), .FALL(8'd4)) echo_hdmi (.clk(hclk),    .led(blip_hdmi));
    heartbeat #(.TICK_DIV(21_505), .TICKS(1000), .DELAY_MS(850), .S2_EN(0), .FALL(8'd4)) echo_nes  (.clk(clk_nes), .led(blip_nes));

    breath  #(.TICK_DIV(50_000)) brd (.clk(sys_clk), .led(led_breath));

    // Ramp evidence for the `s=` field of the message.  The envelope is supposed
    // to climb six per millisecond from zero to 255, so it must pass through
    // values just under the top: this holds the largest envelope value ever seen
    // that is still below 250.  A ramping envelope reaches 246 and this reads
    // 15.  An envelope that steps straight from zero to 255 never passes below
    // 250 on the way up, so this stays 0 -- and that, not any impression of the
    // LEDs, is what says whether the bitstream ramps the envelope at all.
    reg [7:0] env_ramp_probe;
    always @(posedge sys_clk)
        if (env_sys > env_ramp_probe && env_sys < 8'd250) env_ramp_probe <= env_sys;

    // Module lane n is module pin (1, 2, 3, 4, 7, 8, 9, 10)[n], and the dock
    // interleaves those onto IO0/2/4/6 for lanes 0-3 and IO1/3/5/7 for lanes
    // 4-7.  In module order the panel reads: sys_clk, clk27, hclk, clk_nes,
    // pll_27 lock, pll_hdmi lock, pll_nes lock, spare.
    //
    // One panel, one rhythm.  The first four lanes are the four clocks beating.
    // The three lock lanes answer each beat with a short ripple through the
    // quiet half of the second -- the same sound, single and crisp and delayed,
    // so the panel is not four lanes of information with four leftovers beside
    // them.  The ripple holds its shape because every clock here is an exact
    // ratio of the one crystal.  The spare lane breathes, slowly, so there is
    // one calm thing on the panel while the other seven count.
    assign pmod1_io0 = led_sys;            // LED 1 <- sys_clk  50.00 MHz  the beat
    assign pmod1_io2 = led_27;             // LED 2 <- clk27    27.00 MHz  the beat
    assign pmod1_io4 = led_hclk;           // LED 3 <- hclk     74.25 MHz  the beat
    assign pmod1_io6 = led_nes;            // LED 4 <- clk_nes  21.50 MHz  the beat
    assign pmod1_io1 = lock27   && blip_27;    // LED 5 <- pll_27 lock   echo at 550 ms
    assign pmod1_io3 = lock_hdmi && blip_hdmi; // LED 6 <- pll_hdmi lock  echo at 700 ms
    assign pmod1_io5 = lock_nes  && blip_nes;  // LED 7 <- pll_nes lock   echo at 850 ms
    assign pmod1_io7 = led_breath;         // LED 8   slow breath, ~4 s
endmodule


// ------------------------------------------------------------------ heartbeat
//
// One beat of a normal cardiac cycle, as a brightness envelope on one LED, and
// CLOCKED BY THE CLOCK WHOSE LANE IT DRIVES.  That is the whole reason this is a
// module rather than a 1 Hz square wave driven from sys_clk: a lane that is not
// clocked by its own clock stops being a witness to that clock, and every
// reading this panel has produced rests on that property.
//
// The waveform is S1 and S2, the two sounds a stethoscope hears.  Each is a fast
// attack and a slower decay and S2 is quieter than S1, which is what makes the
// pair read as "lub ... dub ... " rather than as two equal blinks.  A long pause
// follows, the diastole.
//
// One beat is one second at the clock's nominal rate -- 60 a minute -- so every
// boundary below is a count of MILLISECONDS: TICKS is 1000, TICK_DIV is that
// clock's cycles per millisecond, and the tick counter is the only place the
// clock's frequency enters.  A clock at the wrong rate beats at the wrong rate,
// which is what the square-wave version told us, now with a shape.
//
// Brightness is the envelope carried on a carrier the LED can actually follow.
// `pwm` steps through all 256 values once per carrier period and the lane is
// HIGH while it is below `env`, so the duty -- and so the average brightness --
// is env/256.
//
// CARRIER_DIV sets that period: `pwm` steps once every CARRIER_DIV clocks, so
// the carrier is the lane's clock over 256 * CARRIER_DIV.  That parameter, and
// not the modulation, is the whole point of this version.
//
// The first build ran the carrier as fast as it could -- the clock over 256,
// which is 84 to 290 kHz across these four lanes -- and every lane read as fully
// on for the whole non-zero span of the envelope and dark outside it.  Two
// things had to be untangled, and the message's `s=` field untangled them: it
// reports the envelope's ramp directly, and it said the envelope had been
// ramping all along, so the logic was never at fault.  A carrier ladder from
// 195 kHz down to 100 Hz changed nothing either, which cleared the rate.  A
// single steady six per cent duty on the spare lane then settled the other
// half: it reads clearly dim beside the full-brightness lanes, so these LEDs do
// display a duty as brightness.
//
// What the envelope was missing was time.  A brightness change has to outlast
// the eye's integration window to be seen as a change at all, and the first
// version decayed over 64 ms, inside a single 107 ms sound.  Four correct lanes
// therefore read as nothing but on and off.  Both the carrier and the decay are
// slow now.
//
// One beat is one second -- 60 a minute, the ordinary resting rate.  S1 begins
// at the beat and lasts about 300 ms, S2 begins at 400 ms and lasts about
// 145 ms, and the rest of the second is dark.  The absolute durations are the
// ordinary adult ones where they can be; the decay is stretched past them on
// purpose, because a faithful one cannot be seen.
module heartbeat #(
    parameter integer TICK_DIV = 50_000,   // this clock's cycles per millisecond
    parameter integer TICKS    = 1000,     // milliseconds in one beat
    parameter integer CARRIER_DIV = 1,     // clocks per carrier step
    parameter integer DELAY_MS = 0,        // shift the whole beat by this much
    parameter integer S2_EN    = 1,        // 0 for a single short sound
    parameter [7:0]   FALL     = 8'd1,     // brightness given up per millisecond
    parameter integer DUTY_SHIFT = 8       // duty range used, of 16 bits
) (
    input  wire clk,
    output wire led,
    output wire [7:0] env_out   // the envelope, for diagnostics
);
    localparam [9:0] S2_ONSET = 10'd400;   // S2 begins, ms into the beat

    // Ramp steps per millisecond and the peak each sound rises to.  S1 reaches
    // full brightness in 43 ms and fades over 255; S2 rises to 120 of 255 in
    // 24 ms and fades over 120.  Fast up and slow down, which is what a pulse
    // both sounds and looks like -- and the slow part is what makes the
    // brightness legible rather than merely correct.
    localparam [7:0] S1_PEAK = 8'd255, S2_PEAK = 8'd120;
    localparam [7:0] S1_RISE = 8'd6,   S2_RISE = 8'd5;

    localparam [2:0] ST_WAIT1 = 3'd0, ST_UP1 = 3'd1, ST_DN1 = 3'd2,
                     ST_WAIT2 = 3'd3, ST_UP2 = 3'd4, ST_DN2 = 3'd5;

    reg [9:0]  phase;      // 0..TICKS-1, milliseconds into the beat
    reg [17:0] tick;       // this clock's cycles within the current millisecond
    reg [7:0]  env;        // the envelope, and so the brightness
    reg [15:0] pwm;        // the carrier counter, 0..65535
    reg [15:0] cdiv;       // carrier prescaler: clocks between carrier steps

    // This design has no reset: every flop here powers up at zero and the
    // waveform depends on that.  `st` is the one register where the value it
    // powers up at is load bearing -- zero is ST_WAIT1, the state the beat
    // starts from -- so the encoding must stay binary and 0 must keep meaning
    // ST_WAIT1.
    //
    // Left to itself yosys's FSM pass re-encodes this register ONE-HOT, six
    // state bits for six states, and the transition table it builds has no row
    // for the all-zero code.  On silicon that is fatal: Gowin flops power up at
    // zero, so `st` comes up as six zeros, which is not a valid one-hot code,
    // and nothing moves it.  The FSM is a trap, `env` never leaves 0, the
    // PWM comparison is never true and every lane stays dark -- which is
    // exactly what the first board test of this module showed.  A simulation
    // cannot see it, because iverilog keeps the binary encoding and the
    // testbench forces the power-up state, which in binary is valid.
    //
    // `fsm_encoding = "none"` keeps the register as written, so all eight codes
    // are real and the power-up value is the state the beat is supposed to
    // start in.  A real reset would be the sturdier fix and is the right thing
    // if this instrument grows past bring-up; while it has none, this is what
    // makes the no-reset convention safe.
    (* fsm_encoding = "none" *)
    reg [2:0]  st;

    wire tick_now = (tick == TICK_DIV - 1);

    // DUTY_SHIFT is how much of a sixteen-bit carrier's range the envelope is
    // allowed to use, so the peak duty is 255 * 2**DUTY_SHIFT / 65536.  The
    // default of 8 reproduces a plain env/256 across a 256-step carrier; smaller
    // values put the whole envelope into a dimmer band.  That matters because
    // this deck's LEDs are compressed at the top: measured by eye, 6, 25, 50 and
    // 100 per cent duty read as 70, 80, 90 and 100 per cent brightness, so a
    // fade spent across the top of the range has almost nowhere to go.  A wider
    // counter also puts the carrier at a few hundred hertz with no prescaler at
    // all, since it is the lane's clock over 65536.
    wire [15:0] thresh = env << DUTY_SHIFT;
    wire pwm_step = (cdiv == CARRIER_DIV - 1);

    always @(posedge clk) begin
        cdiv <= pwm_step ? 16'd0 : cdiv + 16'd1;
        if (pwm_step) pwm <= pwm + 16'd1;
        if (tick_now) begin
            tick  <= 18'd0;
            phase <= (phase == TICKS - 1) ? 10'd0 : phase + 10'd1;
        end else begin
            tick <= tick + 18'd1;
        end
    end

    always @(posedge clk) begin
        if (tick_now) begin
            case (st)
                ST_WAIT1: if (phase == DELAY_MS) st <= ST_UP1;
                ST_UP1:   if (env >= S1_PEAK)    st <= ST_DN1;
                ST_DN1:   if (env == 8'd0)       st <= ST_WAIT2;
                // With S2 switched off the beat is over, so WAIT2 lasts one tick
                // and returns to the start.  It must NOT wait for the S2 onset:
                // S2_ONSET + DELAY_MS can run past the end of the second, and a
                // lane delayed that far never leaves WAIT2 -- which is exactly
                // what two of the three lock lanes did, blinking once at
                // power-up and then sitting dead.
                ST_WAIT2: if (!S2_EN)                        st <= ST_WAIT1;
                          else if (phase >= S2_ONSET + DELAY_MS) st <= ST_UP2;
                ST_UP2:   if (env >= S2_PEAK)    st <= ST_DN2;
                ST_DN2:   if (env == 8'd0)       st <= ST_WAIT1;
                default:                         st <= ST_WAIT1;
            endcase

            case (st)
                ST_UP1: env <= (env > S1_PEAK - S1_RISE) ? S1_PEAK : env + S1_RISE;
                ST_DN1: env <= (env < FALL)              ? 8'd0    : env - FALL;
                ST_UP2: env <= (env > S2_PEAK - S2_RISE) ? S2_PEAK : env + S2_RISE;
                ST_DN2: env <= (env < FALL)              ? 8'd0    : env - FALL;
                default: env <= 8'd0;
            endcase
        end
    end

    assign led     = (pwm < thresh);
    assign env_out = env;
endmodule

`default_nettype wire


// ------------------------------------------------------------------ breath
//
// A slow swell for the spare lane: brightness rising and falling over about four
// seconds, so the panel has one calm thing on it while the other seven count.
//
// The envelope is the top eight bits of a millisecond counter that runs 0 to
// 4095, which makes a triangle whose brightness steps once every eight
// milliseconds -- slow enough to watch, and smooth rather than stepped because
// the carrier underneath it is still two hundred hertz.  No reset and no state
// machine: this is a counter, a slice, and a comparison, which is the part of
// this flow that has never been in doubt.
module breath #(
    parameter integer TICK_DIV = 50_000,   // this clock's cycles per millisecond
    parameter integer CARRIER_DIV = 1,     // clocks per carrier step
    parameter integer DUTY_SHIFT = 8       // duty range used, of 16 bits
) (
    input  wire clk,
    output wire led
);
    reg [11:0] phase;      // milliseconds, 0..4095 = 4.096 s
    reg [17:0] tick;
    reg [15:0] pwm;
    reg [15:0] cdiv;

    wire tick_now = (tick == TICK_DIV - 1);
    wire pwm_step = (cdiv == CARRIER_DIV - 1);
    wire [7:0] env = phase[11] ? ~phase[10:3] : phase[10:3];
    wire [15:0] thresh = env << DUTY_SHIFT;

    always @(posedge clk) begin
        cdiv <= pwm_step ? 16'd0 : cdiv + 16'd1;
        if (pwm_step) pwm <= pwm + 16'd1;
        if (tick_now) begin
            tick  <= 18'd0;
            phase <= (phase == 12'd4095) ? 12'd0 : phase + 12'd1;
        end else begin
            tick <= tick + 18'd1;
        end
    end

    assign led = (pwm < thresh);
endmodule


// ------------------------------------------------------------- steady_duty
//
// A steady duty, for qualifying the LEDs.  A carrier at about two hundred hertz
// with a fixed duty, so four lanes at four duties can be ranked by eye and the
// panel's brightness curve read off directly instead of argued about.  Same
// carrier as every other lane, so the comparison is fair.
module steady_duty #(
    parameter integer CARRIER_DIV = 1,     // clocks per carrier step
    parameter integer DUTY_SHIFT = 8       // duty range used, of 16 bits
) (
    input  wire clk,
    output wire led
);
    reg [15:0] pwm;
    reg [15:0] cdiv;

    wire pwm_step = (cdiv == CARRIER_DIV - 1);

    always @(posedge clk) begin
        cdiv <= pwm_step ? 16'd0 : cdiv + 16'd1;
        if (pwm_step) pwm <= pwm + 16'd1;
    end

    assign led = (pwm < (16'd255 << DUTY_SHIFT));
endmodule
