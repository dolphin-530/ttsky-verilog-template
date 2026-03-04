# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge


def set_ui_in(dut, send: int, bitv: int):
    """Drive ui_in[0]=send, ui_in[1]=bitv, others 0."""
    send = 1 if send else 0
    bitv = 1 if bitv else 0
    dut.ui_in.value = (bitv << 1) | send


async def inject_token(dut, bitv: int):
    """
    Inject one token by creating a rising edge on ui_in[0].
    Your RTL edge-detects ui_in[0], so:
      0 -> 1 -> 0 across successive clock edges.
    """
    set_ui_in(dut, send=0, bitv=bitv)
    await ClockCycles(dut.clk, 1)

    set_ui_in(dut, send=1, bitv=bitv)  # rising edge
    await ClockCycles(dut.clk, 1)

    set_ui_in(dut, send=0, bitv=bitv)
    await ClockCycles(dut.clk, 1)


@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")

    # Clock: 10 us period (100 kHz)
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    # Reset
    dut._log.info("Reset")
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    dut._log.info("Test dual-rail 4-stage pipeline behavior")

    # Helper: read useful signals from uo_out
    def stages_vec():
        # uo_out[3:0] are token-present LEDs in your design
        return int(dut.uo_out.value) & 0xF

    def violation():
        return (int(dut.uo_out.value) >> 5) & 1

    def last_rails():
        uo = int(dut.uo_out.value)
        out_minus = (uo >> 6) & 1
        out_plus  = (uo >> 7) & 1
        return out_plus, out_minus

    # Sanity: no violation after reset
    assert violation() == 0, "Protocol violation asserted right after reset"

    # Run two trials: send bit=1 then bit=0
    for bitv in (1, 0):
        dut._log.info(f"Inject token bit={bitv}")

        await inject_token(dut, bitv)

        # Wait up to N cycles for token to reach stage3 (bit3 set)
        hit_stage3 = False
        last_seen = None
        N = 500

        for _ in range(N):
            if violation():
                raise AssertionError("Protocol violation (uo_out[5]) went high")

            vec = stages_vec()
            last_seen = vec

            if (vec & 0b1000) != 0:
                hit_stage3 = True
                op, om = last_rails()

                if bitv == 1:
                    assert (op, om) == (1, 0), f"Expected stage3 rails 10 for bit=1, got {op}{om}"
                else:
                    assert (op, om) == (0, 1), f"Expected stage3 rails 01 for bit=0, got {op}{om}"
                break

            await ClockCycles(dut.clk, 1)

        assert hit_stage3, f"Token never reached stage3 (vec last seen 0b{last_seen:04b})"

        # A few extra cycles to ensure no violation appears
        await ClockCycles(dut.clk, 20)
        assert violation() == 0, "Protocol violation asserted after token reached stage3"

    dut._log.info("PASS: tokens reached stage3 with correct dual-rail value and no violations.")
