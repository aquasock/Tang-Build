"""nextpnr post-route hook: inspect the route to each VGA data/sync pin.

    NEXTPNR_POST_ROUTE=/absolute/path/tools/inspect-vga-routing.py \
        scripts/pnr-desktop.sh TREE

Reports interconnect delay and combinational depth back to RGB/raster registers.
LUT propagation, register clock-to-Q and board delays are not included. The
Clocked OLED, socket-control and constant sources are excluded. The structural
cone can still include routes selected by other socket declarations/flips; these
values are diagnostic observations, not output timing constraints or limits.

SPDX-License-Identifier: MIT
"""


def route_delay(net, cell_name, pin):
    for user in net.users:
        if user.cell.name == cell_name and user.port == pin:
            return ctx.getDelayNS(ctx.getNetinfoRouteDelay(net, user))
    raise RuntimeError(f"missing sink {cell_name}.{pin}")


cache = {}


def cone(net, visiting):
    if net.name in cache:
        return cache[net.name]
    if net.name in visiting:
        raise RuntimeError(f"combinational loop at {net.name}")
    driver = net.driver
    cell = driver.cell
    if cell is None or cell.type.startswith("DFF") or cell.type in (
        "VCC", "GND", "IBUF", "GOWIN_VCC", "GOWIN_GND", "GOWIN_IBUF"
    ):
        if cell is not None and cell.type.startswith("DFF") and cell.name.startswith((
            "desktop_rgb_DFFRE_Q", "desktop_sockets.visible_DFFRE_Q",
            "desktop_sockets.hs_DFFRE_Q", "desktop_sockets.vs_DFFRE_Q"
        )):
            return 0.0, 0, f"{cell.name}.{driver.port}"
        return None
    visiting = visiting | {net.name}
    candidates = []
    # nextpnr's contextual PortMap has indexed lookup but no dict.items().
    if cell.type.startswith("LUT"):
        pins = [f"I{i}" for i in range(int(cell.type[3:]))]
    elif cell.type.startswith("MUX2_"):
        pins = ["I0", "I1", "S0"]
    elif cell.type == "ALU":
        pins = ["I0", "I1", "I2", "I3", "CIN"]
    else:
        raise RuntimeError(f"unsupported combinational cell {cell.name}: {cell.type}")
    for pin in pins:
        try:
            info = cell.ports[pin]
        except (KeyError, IndexError):
            continue
        if info.net is None:
            continue
        child = cone(info.net, visiting)
        if child is None:
            continue
        delay, depth, source = child
        candidates.append((delay + route_delay(info.net, cell.name, pin), depth + 1, source))
    result = max(candidates) if candidates else None
    cache[net.name] = result
    return result


print("VGA_INTERCONNECT_BEGIN")
for slot in range(2):
    for io in range(8):
        lane = io // 2 + (io % 2) * 4
        label = (f"green[{lane}]" if lane < 4 else ("hsync" if lane == 4 else "vsync")) if slot == 0 else (
            f"red[{lane}]" if lane < 4 else f"blue[{lane - 4}]")
        if slot == 0 and lane > 5:
            continue
        name = f"pmod{slot}_io_IOBUF_IO" + (f"_{io}" if io else "")
        cell = ctx.cells[name]
        net = cell.ports["I"].net
        path = cone(net, set())
        if path is None:
            raise RuntimeError(f"{name}: no path from RGB/raster registers")
        delay, depth, source = path
        delay += route_delay(net, name, "I")
        print(f"VGA_INTERCONNECT pmod{slot}[{io}] {label} bel={cell.bel} "
              f"wire_ns={delay:.3f} stages={depth} source={source}")
print("VGA_INTERCONNECT_END")
