# clock-smoke timing constraints. SPDX-License-Identifier: MIT
#
# `#` comments, not `//`: nextpnr's SDC reader rejects the C++ style.
#
# The four clock periods are the desktop core's own numbers where they overlap
# (sys_clk 20 ns, hclk5 2.6936 ns) so a pass here means the same thing as a
# pass there.

create_clock -name sys_clk -period 20      [get_nets {sys_clk}]
create_clock -name clk27   -period 37.037  [get_nets {clk27}]
create_clock -name hclk5   -period 2.6936  [get_nets {hclk5}]
create_clock -name hclk    -period 13.468  [get_nets {hclk}]
create_clock -name clk_nes -period 46.511  [get_nets {clk_nes}]
