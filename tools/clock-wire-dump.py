"""nextpnr post-route hook: what wires did each clock net actually bind?

    NEXTPNR_POST_ROUTE=/abs/path/tools/clock-wire-dump.py scripts/pnr-desktop.sh TREE

`evidence/clock-plane-gate-reach.txt` measured the model's gate reach from the
chipdb and got an answer that contradicts the router: 16 gate sites appear to
reach the whole die through two wires, `CLK1` and `CLK2`, yet nextpnr reports
`no clock gate reaches both its source and its loads` in every log.  This hook
is the other side of that discrepancy: it asks the *routed* design which wires
each clock net holds, so the two accounts can be compared on the same object.

It is deliberately defensive.  If an accessor does not exist in this build of
nextpnr it prints why and keeps going, because a hook that raises can take the
routing with it, and a diagnostic must not be able to fail the thing it is
measuring.

SPDX-License-Identifier: MIT
"""

CLOCKS = ("clk", "hclk5", "clk27", "keyboard_link.clk",
          "desktop_sockets.pixel_clk", "desktop_main_pll")

print("CLOCKWIRE_BEGIN")

nets = None
for how in ("ctx.nets", "ctx.getNets()"):
    try:
        nets = eval(how)
        print("nets via %s: %s" % (how, type(nets).__name__))
        break
    except Exception as e:                                  # noqa: BLE001
        print("nets via %s failed: %s" % (how, e))

def describe(net):
    try:
        name = str(net.name)
    except Exception:                                       # noqa: BLE001
        name = "<unnamed>"
    try:
        wires = net.wires
    except Exception as e:                                  # noqa: BLE001
        print("NET %s: wires unavailable: %s" % (name, e))
        return
    try:
        items = list(wires.keys())
    except Exception:                                       # noqa: BLE001
        items = list(wires)
    print("NET %s wires=%d" % (name, len(items)))
    if items:
        kv = items[0]
        print("   kv.first=%r  str=%r" % (kv.first, str(kv.first)))
        print("   kv.second type=%s attrs=%s"
              % (type(kv.second).__name__, [a for a in dir(kv.second) if not a.startswith('_')]))
        for probe, fn in (("second.pip", lambda: kv.second.pip),
                          ("getWireName", lambda: ctx.getWireName(kv.first)),
                          ("wireName", lambda: ctx.wireName(kv.first))):
            try:
                print("   probe %s -> %r" % (probe, fn()))
            except Exception as e:                          # noqa: BLE001
                print("   probe %s failed: %s" % (probe, e))
    for w in items:
        out = []
        for label, fn in (("wire", lambda o: o.first),
                          ("pip", lambda o: o.second.pip)):
            try:
                out.append("%s=%s" % (label, fn(w)))
            except Exception as e:                          # noqa: BLE001
                out.append("%s?%s" % (label, e))
        print("   %s" % "  ".join(out))

if nets is not None:
    try:
        pairs = nets.items() if hasattr(nets, "items") else [(str(k), v) for k, v in nets]
        for name, net in pairs:
            if str(name) in CLOCKS:
                describe(net)
    except Exception as e:                                  # noqa: BLE001
        print("iteration failed: %s" % e)
else:
    # fall back: reach each clock through a cell that drives it
    for cell_name in ("desktop_sockets.pixel_clk_PLL_inst",):
        try:
            cell = ctx.cells[cell_name]
            print("reached cell %s" % cell_name)
        except Exception as e:                              # noqa: BLE001
            print("cell %s unavailable: %s" % (cell_name, e))

print("CLOCKWIRE_END")
