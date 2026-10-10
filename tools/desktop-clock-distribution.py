#!/usr/bin/env python3
"""Give the GW5AST-138C desktop main clock a static DCS distribution path.

    tools/desktop-clock-distribution.py pnr-input.json pnr-clocked.json

The current nextpnr fork skips automatic BUFG insertion for PLL outputs and
cannot route this PLL directly onto the clock spines. CLOCK requests a BUFG
at the PLL output; a static CLK0 DCS lets the global router cross the clock
network's DCS bridges. The existing clk net and all of its consumers remain
connected to the pass-through output. No pixel, renderer or PLL recipe changes.

Apply only to the flattened, unrouted desktop netlist, before nextpnr packing.
SPDX-License-Identifier: MIT
"""

import argparse
import copy
import json
from pathlib import Path


PLL = "pll_nes.PLL_inst"
RAW = "desktop_main_pll"
DCS = "desktop_main_distribution"


def prepare(doc):
    result = copy.deepcopy(doc)
    top = result["modules"].get("nestang_top")
    if top is None:
        raise ValueError("missing flattened nestang_top module")
    cells, nets = top["cells"], top["netnames"]
    if DCS in cells or RAW in nets:
        raise ValueError("main-clock distribution already present or names occupied")
    if any("NEXTPNR_BEL" in c.get("attributes", {}) for c in cells.values()):
        raise ValueError("expected an unrouted netlist, before nextpnr packing")
    pll = cells.get(PLL, {})
    clk = nets.get("clk", {}).get("bits", [])
    if (pll.get("type") != "PLL" or len(clk) != 1
            or type(clk[0]) is not int
            or pll.get("connections", {}).get("CLKOUT0") != clk):
        raise ValueError("clk must be driven by pll_nes.PLL_inst/CLKOUT0")
    drivers = []
    all_bits = []
    for name, cell in cells.items():
        for port, bits in cell.get("connections", {}).items():
            all_bits.extend(bits)
            if cell.get("port_directions", {}).get(port) == "output" and clk[0] in bits:
                drivers.append((name, port))
    if drivers != [(PLL, "CLKOUT0")]:
        raise ValueError(f"unexpected main-clock drivers: {drivers}")
    for port in top.get("ports", {}).values():
        all_bits.extend(port["bits"])
        if clk[0] in port["bits"]:
            raise ValueError("main clock unexpectedly exposed at a top-level port")
    for net in nets.values():
        all_bits.extend(net["bits"])
    raw = max(bit for bit in all_bits if type(bit) is int) + 1
    pll["connections"]["CLKOUT0"] = [raw]
    nets[RAW] = {"hide_name": 0, "bits": [raw], "attributes": {"CLOCK": "1"}}
    connections = {
        "CLKIN0": [raw], "CLKIN1": [], "CLKIN2": [], "CLKIN3": [],
        "CLKSEL": [], "SELFORCE": [], "CLKOUT": clk.copy(),
    }
    cells[DCS] = {
        "hide_name": 0, "type": "DCS",
        "parameters": {"DCS_MODE": "CLK0"},
        "attributes": {"DCS_MODE": "CLK0"},
        "port_directions": {pin: "output" if pin == "CLKOUT" else "input"
                            for pin in connections},
        "connections": connections,
    }
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        result = prepare(json.loads(args.input.read_text()))
    except (KeyError, ValueError) as exc:
        parser.error(str(exc))
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print("main clock: PLL CLKOUT0 -> CLOCK/BUFG -> static DCS CLK0 -> clk")


if __name__ == "__main__":
    main()
