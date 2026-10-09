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
// eight of those balls are driven here instead, under their real names, as an
// eight-lane chaser on the PMOD1 header -- see the chaser block at the end of
// this file for why, for its polarity, and for what it trades away.  The
// instrument remains the UART, which the chaser does not touch.
//
// The UART is clocked by `sys_clk` alone, so it keeps reporting even if every
// PLL is dead -- which is exactly the case worth being able to see.  It sends
// one fixed 49-byte line:
//
//   clock-smoke s=A lock=DE c27=XXXX hk=XXXX n=XXXX\r\n
//
//      s     cnt_sys[24], a sanity bit for the 50 MHz input
//      D E   pll_27 and pll_hdmi LOCK
//      c27   count of clk27's bit-8 edges: clk27 = c27 x 256 / line period
//      hk    the same for hclk, the CLKDIV output
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
    // 18.1 kHz for a 148.5 MHz hclk -- far below the 50 MHz sampling clock, so
    // no edge is ever missed, and the counts fit in 16 bits per line.
    reg [1:0]  q27;
    reg [1:0]  qhclk;
    reg [15:0] n27;
    reg [15:0] nhclk;
    always @(posedge sys_clk) begin
        s27   <= {s27[0],   cnt_27[23]};
        shclk <= {shclk[0], cnt_hclk[24]};
        q27   <= {q27[0],   cnt_27[12]};
        qhclk <= {qhclk[0], cnt_hclk[12]};
        if (q27[1]   != q27[0])   n27   <= n27   + 16'd1;
        if (qhclk[1] != qhclk[0]) nhclk <= nhclk + 16'd1;
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
    localparam MSG_LEN  = 49;

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

    // "clock-smoke s=A lock=DE c27=XXXX hk=XXXX n=XXXX\r\n", one case arm per
    // byte.  c27 and hk are counts of that clock's bit-8 edges, so a reader gets
    // cycles per line and never has to know which bit was read.
    function [7:0] msg_byte;
        input [5:0] i;
        begin
            case (i)
                6'd0:  msg_byte = 8'h63;  // c
                6'd1:  msg_byte = 8'h6c;  // l
                6'd2:  msg_byte = 8'h6f;  // o
                6'd3:  msg_byte = 8'h63;  // c
                6'd4:  msg_byte = 8'h6b;  // k
                6'd5:  msg_byte = 8'h2d;  // -
                6'd6:  msg_byte = 8'h73;  // s
                6'd7:  msg_byte = 8'h6d;  // m
                6'd8:  msg_byte = 8'h6f;  // o
                6'd9:  msg_byte = 8'h6b;  // k
                6'd10: msg_byte = 8'h65;  // e
                6'd11: msg_byte = 8'h20;  // ' '
                6'd12: msg_byte = 8'h73;  // s
                6'd13: msg_byte = 8'h3d;  // =
                6'd14: msg_byte = ch_s;
                6'd15: msg_byte = 8'h20;  // ' '
                6'd16: msg_byte = 8'h6c;  // l
                6'd17: msg_byte = 8'h6f;  // o
                6'd18: msg_byte = 8'h63;  // c
                6'd19: msg_byte = 8'h6b;  // k
                6'd20: msg_byte = 8'h3d;  // =
                6'd21: msg_byte = ch_d;
                6'd22: msg_byte = ch_e;
                6'd23: msg_byte = 8'h20;  // ' '
                6'd24: msg_byte = 8'h63;  // c
                6'd25: msg_byte = 8'h32;  // 2
                6'd26: msg_byte = 8'h37;  // 7
                6'd27: msg_byte = 8'h3d;  // =
                6'd28: msg_byte = hexd(n27[15:12]);
                6'd29: msg_byte = hexd(n27[11:8]);
                6'd30: msg_byte = hexd(n27[7:4]);
                6'd31: msg_byte = hexd(n27[3:0]);
                6'd32: msg_byte = 8'h20;  // ' '
                6'd33: msg_byte = 8'h68;  // h
                6'd34: msg_byte = 8'h6b;  // k
                6'd35: msg_byte = 8'h3d;  // =
                6'd36: msg_byte = hexd(nhclk[15:12]);
                6'd37: msg_byte = hexd(nhclk[11:8]);
                6'd38: msg_byte = hexd(nhclk[7:4]);
                6'd39: msg_byte = hexd(nhclk[3:0]);
                6'd40: msg_byte = 8'h20;  // ' '
                6'd41: msg_byte = 8'h6e;  // n
                6'd42: msg_byte = 8'h3d;  // =
                6'd43: msg_byte = hexd(cnt_line[15:12]);
                6'd44: msg_byte = hexd(cnt_line[11:8]);
                6'd45: msg_byte = hexd(cnt_line[7:4]);
                6'd46: msg_byte = hexd(cnt_line[3:0]);
                6'd47: msg_byte = 8'h0d;  // CR
                6'd48: msg_byte = 8'h0a;  // LF
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

    // -------------------------------------- PMOD1: an eight-lane chaser
    //
    // All eight lanes are driven, and one of them at a time is LOW, so a single
    // lit LED travels 1 -> 8 -> 1.  Two reasons this replaced the five
    // per-clock outputs the earlier versions carried:
    //
    //   * the travelling dot makes the module's lane order readable by eye.  A
    //     direction of travel cannot be mistaken, so this is what turns the
    //     dock's row interleave -- lanes 0-3 on module pins 1-4 and lanes 4-7 on
    //     pins 7-10 -- from a sourced claim into a measured one;
    //   * it is the first output of this project that a person can recognise,
    //     which a UART line is not.
    //
    // What it gives up is the meter reading of cnt_sys, cnt_27, cnt_hclk and the
    // two lock bits, which the earlier five lanes exposed.  The UART keeps all
    // of that and better: the counters are still here and still read by the
    // report, only their pins are gone.
    //
    // POLARITY, measured 2026-10-09 with an 8-LED PMOD in PMOD1, twice and in
    // the second case decisively: the lane this design drives LOW is the DARK
    // one, and the seven it drives HIGH are lit, so the module lights when its
    // pin is driven HIGH.  The chaser is what settles it, because it drives
    // exactly one lane low at a time and the user could see which one went out.
    //
    // An earlier reading in this same cycle inferred the opposite from the two
    // lock lanes being dark while their pins were high, and that inference is
    // therefore wrong somewhere -- either those two LEDs were misread at a
    // glance or their lanes were not in fact driving.  The chaser's evidence is
    // the better one because the driver is known by construction, so this file
    // follows the chaser: the lit lane is driven HIGH.
    // `evidence/clock-smoke-led-and-uart.txt` section 3 records the earlier
    // reading; the log entry after this one corrects it.
    //
    // 4 steps a second, so a lap takes 2 s and every lane blinks at 0.5 Hz --
    // slow enough to follow a single dot around the module.  50 MHz / 4.
    localparam integer STEP_DIV = 12_500_000;
    reg [23:0] step_cnt;
    reg [2:0]  lane;                 // the lit module lane, 0..7
    wire step_tick = (step_cnt == STEP_DIV - 1);

    always @(posedge sys_clk) begin
        if (step_tick) begin
            step_cnt <= 24'd0;
            lane     <= lane + 3'd1;
        end else begin
            step_cnt <= step_cnt + 24'd1;
        end
    end

    wire [7:0] dot = 8'h01 << lane;  // bit n set = module lane n is lit

    // The dock interleaves the socket rows, so module lane n is not IO n: lanes
    // 0-3 land on IO0/2/4/6 and lanes 4-7 on IO1/3/5/7.  Driving these in lane
    // order while the socket is wired in IO order is what makes the direction
    // of travel mean something -- and the first load of this chaser confirmed
    // it on hardware: the marker travels 1 -> 8 in order and then repeats, so
    // the module's own LEDs run in lane order.
    assign pmod1_io0 = dot[0];       // module pin 1  <- lane 0
    assign pmod1_io2 = dot[1];       // module pin 2  <- lane 1
    assign pmod1_io4 = dot[2];       // module pin 3  <- lane 2
    assign pmod1_io6 = dot[3];       // module pin 4  <- lane 3
    assign pmod1_io1 = dot[4];       // module pin 7  <- lane 4
    assign pmod1_io3 = dot[5];       // module pin 8  <- lane 5
    assign pmod1_io5 = dot[6];       // module pin 9  <- lane 6
    assign pmod1_io7 = dot[7];       // module pin 10 <- lane 7

endmodule

`default_nettype wire
