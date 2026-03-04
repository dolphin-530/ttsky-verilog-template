<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

# Self-Timed Dual-Rail Pipeline (Synchronous Model)

## Overview

This project implements a four-stage self-timed dual-rail pipeline inspired by asynchronous design, emulated here using a synchronous system. This was inspire by my poster presentation for cse 185E. ChatGPT was used to generate this write up and to generate the cocoTB testbench, but not the RTL for the module itself.

Although the design uses a clock for simulation and synthesis purposes, the logical protocol itself follows the structure of a self-timed asynchronous datapath. The clock simply models the internal state updates of consensus elements and storage registers.

The pipeline accepts a single-bit data value and propagates it through four stages using dual-rail encoding and completion signaling.

## Dual-Rail Data Encoding

Instead of representing data with a single signal, each logical bit is encoded using two wires called the plus rail and the minus rail.

plus = 1, minus = 0 → logical value 1
plus = 0, minus = 1 → logical value 0
plus = 0, minus = 0 → spacer (no valid data)
plus = 1, minus = 1 → illegal state

This encoding allows a stage to determine when data is valid without relying on a global clock signal. When either rail becomes asserted, the stage knows that valid data has arrived.

The design also includes a protocol violation detector that asserts if both rails are high simultaneously, indicating an illegal state.

## Completion Signaling

Each pipeline stage produces a completion signal derived from its dual-rail outputs. The completion signal is implemented using a NOR of the two rails.

complete = ~(out_plus | out_minus)

## This means:

rails = 00 → complete = 1 (stage empty / spacer)
rails = 01 → complete = 0 (stage holds data)
rails = 10 → complete = 0 (stage holds data)

The completion signal is used for handshake coordination between adjacent pipeline stages.

## Pipeline Stage Architecture

Each stage of the pipeline contains three key components:

### Dual-rail storage registers

### Completion detection logic

### A consensus controller implemented with a C-element

Each stage operates in two alternating phases.

Evaluation Phase

During the evaluation phase, the stage captures dual-rail input data when:

the previous stage indicates valid data, and

the next stage indicates it is empty.

Precharge Phase

After the downstream stage consumes the token, the stage clears its rails and returns to the spacer state so that the next token can propagate through the pipeline.

## C-Element

The handshake protocol is coordinated using a C-element (consensus element). The C-element updates its output only when its two inputs agree.

a = 0, b = 0 → output becomes 0
a = 1, b = 1 → output becomes 1
a ≠ b → output holds previous value

C-elements are widely used in asynchronous logic because they synchronize handshake signals between stages.

In this implementation, the C-element is modeled using synchronous logic:

always @(posedge clk)

This preserves the logical behavior of the consensus element while allowing the design to run in standard Verilog simulation environments and synthesis tools.

Pipeline Structure

The design instantiates four pipeline stages connected in sequence.

source → stage0 → stage1 → stage2 → stage3

Each stage communicates with its neighbors using completion signals.

prev_complete → stage → next_complete

The final stage feeds its completion signal back into its own handshake input so that it can return to the spacer state after producing a token.

Input Interface

Two dedicated input bits are used to control the pipeline.

ui_in[0] → send signal
ui_in[1] → data value

A rising edge on the send signal generates a token containing the value of the data bit.

The token is converted into dual-rail form:

data = 1 → plus = 1, minus = 0
data = 0 → plus = 0, minus = 1

The source logic holds the rails asserted until the first pipeline stage consumes the token. This mimics the behavior of asynchronous request signals, which remain asserted until acknowledged.

## Output Signals

The eight output pins expose internal pipeline state so that the behavior of the circuit can be observed during simulation or on hardware.

uo_out[0] → stage0 occupied indicator
uo_out[1] → stage1 occupied indicator
uo_out[2] → stage2 occupied indicator
uo_out[3] → stage3 occupied indicator
uo_out[4] → reserved
uo_out[5] → dual-rail protocol violation flag
uo_out[6] → stage3 minus rail
uo_out[7] → stage3 plus rail

The stage occupancy outputs make it possible to observe the movement of tokens through the pipeline.

Testbench and Verification

The design is verified using a cocotb-based testbench.

The testbench performs the following steps:

Generate a clock signal.

Apply a reset to initialize the pipeline.

Inject tokens into the pipeline.

Monitor pipeline stage indicators.

Verify that the final stage outputs the correct dual-rail value.

Test Procedure

Two tokens are injected sequentially:

token 1 → logical value 1
token 2 → logical value 0

For each token the testbench performs the following sequence:

Wait until the pipeline returns to the spacer state.

Generate a send pulse.

Monitor the pipeline stage indicators.

Wait until stage3 becomes occupied.

Verify that the dual-rail outputs match the expected encoding.

Expected results:

data = 1 → stage3 rails should be (plus=1, minus=0)
data = 0 → stage3 rails should be (plus=0, minus=1)

Protocol Safety Checks

The testbench continuously monitors the protocol violation signal.

violation = plus & minus

If both rails become high simultaneously, the test fails immediately because the dual-rail encoding has been violated.

The testbench also enforces a timeout condition. If a token fails to reach the final pipeline stage within a fixed number of cycles, the test fails.

# Why the Testbench is Sufficient

The testbench verifies three critical aspects of the design.

### Correct Data Encoding

By injecting both logical values and checking the final dual-rail outputs, the test confirms that the pipeline preserves data values correctly.

### Correct Handshake Progression

Monitoring the stage occupancy indicators confirms that tokens propagate through all four stages of the pipeline.

### Protocol Correctness

Continuous checking of the violation signal ensures that the pipeline never enters the illegal dual-rail state.

Together these checks demonstrate that the handshake control, token propagation, and dual-rail encoding all function as intended.

While the testbench does not exhaustively explore every possible timing condition, it exercises the full pipeline datapath and handshake protocol, which is sufficient to validate the intended behavior of this demonstration design.
