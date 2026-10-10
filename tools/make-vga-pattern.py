#!/usr/bin/env python3
"""Make changing VGA colour bands without changing the desktop's routing.

Replace the glyph selector with a registered raster-coordinate bit and replace
the fifteen colour mux functions with two fixed RGB colours. This bypasses cell
memory, font lookup and cell colours. Existing pipeline registers, clocking,
VGA blanking, socket selection and all routed wires remain intact. As in the
solid-white control, the RGB registers' shared synchronous clear is disabled.

    tools/make-vga-pattern.py routed.json bands.json --width 8

The image alternates green and red bands of the specified output-pixel width;
no black pixels are intended inside the visible picture. This diagnostic does
not bypass the existing pixel pipeline or measure the analog output waveform.

SPDX-License-Identifier: MIT
"""

import argparse
import copy
import hashlib
import json
from pathlib import Path


def override(doc, width, first, second):
    result = copy.deepcopy(doc)
    if len(result["modules"]) != 1:
        raise ValueError("expected one flattened routed module")
    module = next(iter(result["modules"].values()))
    cells = module["cells"]
    drivers, users = {}, {}
    for name, cell in cells.items():
        for pin, bits in cell["connections"].items():
            for bit in bits:
                if cell["port_directions"][pin] == "output":
                    if bit in drivers:
                        raise ValueError(f"multiple drivers on bit {bit}")
                    drivers[bit] = (name, pin)
                else:
                    users.setdefault(bit, set()).add((name, pin))

    def driver(bit, port, kind):
        name, pin = drivers[bit]
        if pin != port or cells[name]["type"] != kind:
            raise ValueError(f"bit {bit}: expected {kind}.{port}")
        return name, cells[name]

    muxes, registers, clears, selectors, clocks = [], set(), set(), set(), set()
    for index in range(24):
        if index % 8 < 3:
            continue
        bit = module["netnames"][f"desktop_rgb[{index}]"]["bits"][0]
        name, ff = driver(bit, "Q", "DFFRE")
        registers.add(name)
        clocks.add(ff["connections"]["CLK"][0])
        clears.add(ff["connections"]["RESET"][0])
        passthrough, lut = driver(ff["connections"]["D"][0], "F", "LUT4")
        if int(lut["parameters"]["INIT"], 2) != 0xFF00:
            raise ValueError(f"{passthrough}: RGB input is not a passthrough")
        _, colour_ff = driver(lut["connections"]["I3"][0], "Q", "DFF")
        clocks.add(colour_ff["connections"]["CLK"][0])
        colour_d = colour_ff["connections"]["D"][0]
        mux, cell = driver(colour_d, "F", "LUT3")
        if int(cell["parameters"]["INIT"], 2) != 0xAC:
            raise ValueError(f"{mux}: unexpected foreground/background mux")
        selectors.add(cell["connections"]["I2"][0])
        if users[colour_d] != {(drivers[lut["connections"]["I3"][0]][0], "D")}:
            raise ValueError(f"{mux}: colour output drives unrelated logic")
        muxes.append((index, mux))
    if len(registers) != 15 or len(clears) != 1 or len(selectors) != 1 or len(clocks) != 1:
        raise ValueError("unexpected RGB register/clear/selector structure")
    selector = selectors.pop()
    if users[selector] != {(name, "I2") for _, name in muxes}:
        raise ValueError("glyph selector also drives unrelated logic")

    # Independently identify each coordinate bit from the ORIGINAL selector's
    # one-hot font selection, rather than assuming synthesis suffix numbering.
    coord_names = ["u_hdmi.u_wide.cx2_DFF_Q" + (f"_{i}" if i else "") for i in range(3)]
    coord_bits = []
    font_bits = []
    for name in coord_names:
        if cells[name]["type"] != "DFF":
            raise ValueError("expected three registered glyph-column bits")
        if cells[name]["connections"]["CLK"][0] not in clocks:
            raise ValueError("raster coordinate and RGB registers use different clocks")
        coord_bits.append(cells[name]["connections"]["Q"][0])
    for i in range(8):
        name = "u_hdmi.u_wide.font_r_DFF_Q" + (f"_{i}" if i else "")
        if cells[name]["type"] != "DFF":
            raise ValueError("expected eight registered font bits")
        font_bits.append(cells[name]["connections"]["Q"][0])

    def evaluate(bit, values):
        if bit in values:
            return values[bit]
        if bit in ("0", "1"):
            return int(bit)
        name, _ = drivers[bit]
        cell = cells[name]
        connections = cell["connections"]
        if cell["type"].startswith("LUT"):
            address = 0
            for i in range(int(cell["type"][3:])):
                bits = connections.get(f"I{i}", [])
                if bits:
                    address |= evaluate(bits[0], values) << i
            value = (int(cell["parameters"]["INIT"], 2) >> address) & 1
        elif cell["type"].startswith("MUX2_"):
            pick = evaluate(connections["S0"][0], values)
            value = evaluate(connections[f"I{pick}"][0], values)
        else:
            raise ValueError(f"unexpected dependency in glyph selector: {name}")
        values[bit] = value
        return value

    positions = {}
    for font_index in (0, 1, 2, 3, 6, 7):
        font_bit = module["netnames"][f"u_hdmi.u_wide.font_r[{font_index}]"]["bits"][0]
        matches = []
        for position in range(8):
            values = {bit: int(bit == font_bit) for bit in font_bits}
            values.update({bit: (position >> i) & 1 for i, bit in enumerate(coord_bits)})
            if evaluate(selector, values):
                matches.append(position)
        if len(matches) != 1:
            raise ValueError("original selector is not a one-hot font-column selection")
        positions[font_index] = matches[0]
    masks = {2: positions[0] ^ positions[1], 4: positions[0] ^ positions[2],
             8: positions[2] ^ positions[6]}
    if set(masks.values()) != {1, 2, 4}:
        raise ValueError("glyph coordinate significance could not be established")
    mask = masks[width]
    coordinate = coord_bits[mask.bit_length() - 1]
    selector_name, selector_lut = driver(selector, "F", "LUT4")
    pins = [i for i in range(4) if selector_lut["connections"].get(f"I{i}") == [coordinate]]
    if len(pins) != 1:
        raise ValueError("requested coordinate is not already routed to the final selector LUT")

    changes = []

    def lut_init(name, value):
        cell = cells[name]
        old = cell["parameters"]["INIT"]
        bits = 1 << int(cell["type"][3:])
        cell["parameters"]["INIT"] = format(value, f"0{len(old)}b")
        if value >= 1 << bits:
            raise ValueError("INIT exceeds LUT width")
        changes.append({"cell": name, "bel": cell["attributes"]["NEXTPNR_BEL"],
                        "old_init": old, "new_init": cell["parameters"]["INIT"]})

    lut_init(selector_name, sum(((address >> pins[0]) & 1) << address for address in range(16)))
    for index, name in muxes:
        low, high = (first >> index) & 1, (second >> index) & 1
        lut_init(name, sum((high if address & 4 else low) << address for address in range(8)))
    clear = clears.pop()
    if users[clear] != {(name, "RESET") for name in registers}:
        raise ValueError("RGB clear drives unrelated logic")
    clear_name, _ = driver(clear, "F", "LUT2")
    lut_init(clear_name, 0)

    restored = copy.deepcopy(result)
    restored_cells = next(iter(restored["modules"].values()))["cells"]
    for change in changes:
        restored_cells[change["cell"]]["parameters"]["INIT"] = change["old_init"]
    if restored != doc or len(changes) != 17 or len({c["cell"] for c in changes}) != 17:
        raise ValueError("more than seventeen intended LUT INIT values changed")
    return result, changes, {"coordinate_register": coord_names[mask.bit_length() - 1],
                             "selector_lut": selector_name, "selector_pin": f"I{pins[0]}",
                             "original_selector_font_positions": positions}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--width", type=int, choices=(8,), default=8,
                        help="eight output pixels; other widths need a different routed selector")
    parser.add_argument("--first", default="00ff00", help="first RGB colour, six hex digits")
    parser.add_argument("--second", default="ff0000", help="second RGB colour, six hex digits")
    args = parser.parse_args()
    try:
        if any(len(v) != 6 for v in (args.first, args.second)):
            raise ValueError("colours must have six hexadecimal digits")
        colours = [int(v, 16) for v in (args.first, args.second)]
        if any(not 0 <= v <= 0xFFFFFF for v in colours):
            raise ValueError("RGB colour out of range")
        raw = args.input.read_bytes()
        result, changes, selection = override(json.loads(raw), args.width, *colours)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2) + "\n")
        manifest = {"source_sha256": hashlib.sha256(raw).hexdigest(),
                    "output_sha256": hashlib.sha256(args.output.read_bytes()).hexdigest(),
                    "width_pixels": args.width, "first_rgb": args.first.lower(),
                    "second_rgb": args.second.lower(), "changes": changes,
                    "placement_and_routing_unchanged": True, **selection}
        args.output.with_suffix(".manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        print(f"{args.output}: {args.width}-pixel colour bands; 17 INIT overrides, routes unchanged")
    except (ValueError, KeyError, OSError) as exc:
        parser.exit(1, f"refusing diagnostic: {exc}\n")


if __name__ == "__main__":
    main()
