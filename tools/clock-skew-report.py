"""nextpnr post-route hook: the real skew of every clock net, passing or not.

    NEXTPNR_POST_ROUTE=/abs/path/tools/clock-skew-report.py scripts/pnr-desktop.sh TREE

`tools/pnr-timing.py` reads `clk-skew` out of nextpnr's *violation* blocks, so it
only ever reports the skew of a clock that already failed.  A build that passes
timing reports 0.000 -- which is not "no skew", it is "no measurement", and that
is exactly the build whose skew matters (on this device the one placement with
zero hold violations is the one whose clock skew is unknown).

This hook measures it directly instead: for each clock net it takes every sink's
routed delay (`getNetinfoRouteDelay`) and reports the spread, min to max, in ns.
That spread *is* the skew the clock's sinks see, and it is a property of the
placement, so it can be compared across seeds.

Written defensively on purpose: a hook that raises can take the routing with it,
and a diagnostic must not be able to fail the thing it measures.

SPDX-License-Identifier: MIT
"""

CLOCKS = ("clk", "hclk5", "clk27", "keyboard_link.clk",
          "desktop_sockets.pixel_clk", "desktop_main_pll")

print("CLOCKSKEW_BEGIN")
try:
    nets = ctx.nets
except Exception as e:                                      # noqa: BLE001
    print("no ctx.nets: %s" % e)
    print("CLOCKSKEW_END")
    raise SystemExit

print("%-28s %6s %9s %9s %9s" % ("net", "sinks", "min_ns", "max_ns", "skew_ns"))
try:
    pairs = nets.items() if hasattr(nets, "items") else [(str(k), v) for k, v in nets]
except Exception as e:                                      # noqa: BLE001
    print("cannot iterate nets: %s" % e)
    pairs = []

for name, net in pairs:
    if str(name) not in CLOCKS:
        continue
    try:
        delays = []
        for u in net.users:
            try:
                d = ctx.getDelayNS(ctx.getNetinfoRouteDelay(net, u))
                if d is not None:
                    delays.append(d)
            except Exception:                               # noqa: BLE001
                continue
        if not delays:
            print("%-28s %6d      ---       ---       ---" % (str(name), 0))
            continue
        lo, hi = min(delays), max(delays)
        print("%-28s %6d %9.3f %9.3f %9.3f" % (str(name), len(delays), lo, hi, hi - lo))
    except Exception as e:                                  # noqa: BLE001
        print("%-28s  unreadable: %s" % (str(name), e))
print("CLOCKSKEW_END")
