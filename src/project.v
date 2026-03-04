/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_dolphin_self_timed_sync_model (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // All output pins must be assigned. If not used, assign to 0.
  //assign uo_out  = ui_in + uio_in;  // Example: ou_out is the sum of ui_in and uio_in
  assign uio_out = 0;
  assign uio_oe  = 0;

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, uio_in, ui_in[7:2], 1'b0};

//begin my source code
  //edge detect for input button(switch?)
  reg send_d;
  always @(posedge clk) begin
    if (!rst_n) send_d <= 1'b0;
    else        send_d <= ui_in[0];
  end
  wire send_pulse = ui_in[0] & ~send_d;

  // create dual rail out of single rail input
 // create dual rail source that holds token until stage0 consumes it
 wire c0, c1, c2, c3;
wire bitv = ui_in[1];

reg src_plus_r;
reg src_minus_r;

always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    src_plus_r  <= 1'b0;
    src_minus_r <= 1'b0;
  end else begin

    // if no token currently held, latch one when button pressed
    if ((src_plus_r | src_minus_r) == 1'b0) begin
      if (send_pulse) begin
        src_plus_r  <= bitv;
        src_minus_r <= ~bitv;
      end
    end

    // if stage0 consumed token (no longer empty), clear source
    else if (c0 == 1'b0) begin
      src_plus_r  <= 1'b0;
      src_minus_r <= 1'b0;
    end
  end
end

wire src_plus  = src_plus_r;
wire src_minus = src_minus_r;
wire src_comp  = ~(src_plus | src_minus);   // NOR completion (empty=1)

//doing 4 stages, all need dual rail wires and complete signals
  wire s0_plus, s0_minus, s1_plus, s1_minus, s2_plus, s2_minus, s3_plus, s3_minus;
  

 //four stages
  dr_pipe_stage_sync st0 (
    .clk(clk), .rst_n(rst_n),
    .in_plus(src_plus), .in_minus(src_minus),
    .prev_complete(src_comp),
    .next_complete(c1),
    .complete(c0),
    .out_plus(s0_plus), .out_minus(s0_minus)
  );

  dr_pipe_stage_sync st1 (
    .clk(clk), .rst_n(rst_n),
    .in_plus(s0_plus), .in_minus(s0_minus),
    .prev_complete(c0),
    .next_complete(c2),
    .complete(c1),
    .out_plus(s1_plus), .out_minus(s1_minus)
  );

  dr_pipe_stage_sync st2 (
    .clk(clk), .rst_n(rst_n),
    .in_plus(s1_plus), .in_minus(s1_minus),
    .prev_complete(c1),
    .next_complete(c3),
    .complete(c2),
    .out_plus(s2_plus), .out_minus(s2_minus)
  );

  dr_pipe_stage_sync st3 (
    .clk(clk), .rst_n(rst_n),
    .in_plus(s2_plus), .in_minus(s2_minus),
    .prev_complete(c2),
    .next_complete(c3),
    .complete(c3),
    .out_plus(s3_plus), .out_minus(s3_minus)
  );

//detect dual rail protocol violation in any stage
  wire v0 = s0_plus & s0_minus;
  wire v1 = s1_plus & s1_minus;
  wire v2 = s2_plus & s2_minus;
  wire v3 = s3_plus & s3_minus;
  wire any_violation = v0 | v1 | v2 | v3;
  //connect outputs, envisioning LEDs for each stage, need to read documentation further
  assign uo_out[0] = ~c0;
  assign uo_out[1] = ~c1;
  assign uo_out[2] = ~c2;
  assign uo_out[3] = ~c3;
  assign uo_out[4] = 1'b0;
  assign uo_out[5] = any_violation;
  assign uo_out[6] = s3_minus;
  assign uo_out[7] = s3_plus;
  

endmodule

//sync emulation of the consensus element
module c_element_sync(
    input wire clk,
    input wire rst_n,
    input wire a,
    input wire b,
    output reg y
);
 always @(posedge clk) begin
        if (!rst_n) begin
            y <= 1'b0;
        end else begin
            case ({a,b})
                2'b00: y <= 1'b0; //change if consensus
                2'b11: y <= 1'b1;
                default: y <= y; // otherwise hold
            endcase
        end
    end
endmodule

//dual rail, c element pipeline adapted from my poster
module dr_pipe_stage_sync (
    input  wire clk, //not included in poster, but using since this is a sync model of async protocol
    input  wire rst_n, //same

    // dual-rail input from left 
    input  wire in_plus,
    input  wire in_minus,

    input wire prev_complete,
    input wire next_complete,
    output wire complete, //out_plus | out_minus

    // dual-rail output to right 
    output reg  out_plus,
    output reg  out_minus
    );

    wire in_valid = (in_plus | in_minus) & ~(in_plus & in_minus);

    // c-element inputs are like ready/valid
    wire c_a = next_complete;       // downstream is ready
    wire c_b = ~prev_complete & in_valid; //data is valid

    assign complete = ~(out_plus | out_minus);
    
    wire phase;
    c_element_sync handshake_ctrl (
      .clk(clk),
      .rst_n(rst_n), 
      .a(c_a), 
      .b(c_b), 
      .y(phase)
      );

    reg phase_d;
    always @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
        phase_d   <= 1'b0;
        out_plus  <= 1'b0;
        out_minus <= 1'b0;
      end else begin
        phase_d <= phase; //use to determine if handhskae is moving 0 -> 1 or 1-> 0

        // rising edge: capture values
        if (!phase_d && phase) begin
          out_plus  <= in_plus;
          out_minus <= in_minus;
        end

        // falling edge: precharge - clear values
        if (phase_d && !phase) begin
          out_plus  <= 1'b0;
          out_minus <= 1'b0;
        end
      end
    end
endmodule
