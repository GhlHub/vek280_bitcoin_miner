`timescale 1ns/1ps

// Two-stage fast-clock schedule service:
//   stage 1: A = sigma1(W[t-2]) + W[t-7]
//             B = sigma0(W[t-15]) + W[t-16]
//   stage 2: W[t] = A + B
//
// The request and response interfaces are elastic.  Tags are carried through
// the pipeline so a future shared service can safely interleave engines and
// rounds.  This module is intentionally independent of the 250 MHz SHA core;
// CDC wrappers and clocking policy belong at the integration boundary.
module dsp58_schedule_pipeline #(
    parameter int unsigned ENGINE_TAG_WIDTH = 5,
    parameter int unsigned ROUND_TAG_WIDTH = 6
) (
    input  wire                           clk_i,
    input  wire                           rst_ni,
    input  wire                           req_valid_i,
    output wire                           req_ready_o,
    input  wire [31:0]                    sigma1_i,
    input  wire [31:0]                    w_m7_i,
    input  wire [31:0]                    sigma0_i,
    input  wire [31:0]                    w_m16_i,
    input  wire [ENGINE_TAG_WIDTH-1:0]    req_engine_i,
    input  wire [ROUND_TAG_WIDTH-1:0]     req_round_i,
    output wire                           rsp_valid_o,
    input  wire                           rsp_ready_i,
    output wire [31:0]                    w_new_o,
    output wire [ENGINE_TAG_WIDTH-1:0]    rsp_engine_o,
    output wire [ROUND_TAG_WIDTH-1:0]     rsp_round_o
);
    reg v1_q;
    reg v2_q;
    reg [ENGINE_TAG_WIDTH-1:0] engine1_q;
    reg [ROUND_TAG_WIDTH-1:0] round1_q;
    reg [ENGINE_TAG_WIDTH-1:0] engine2_q;
    reg [ROUND_TAG_WIDTH-1:0] round2_q;

    wire stage2_ready = !v2_q || rsp_ready_i;
    wire stage1_ready = !v1_q || stage2_ready;
    wire req_fire = req_valid_i && req_ready_o;
    wire stage2_fire = v1_q && stage2_ready;

    wire [31:0] a_q;
    wire [31:0] b_q;
    wire [31:0] w_new_w;

    assign req_ready_o = stage1_ready;
    assign rsp_valid_o = v2_q;
    assign w_new_o = w_new_w;
    assign rsp_engine_o = engine2_q;
    assign rsp_round_o = round2_q;

    dsp58_add32_registered u_add_a (
        .clk_i(clk_i), .rst_ni(rst_ni), .ce_i(req_fire),
        .a_i(sigma1_i), .b_i(w_m7_i), .sum_o(a_q)
    );
    dsp58_add32_registered u_add_b (
        .clk_i(clk_i), .rst_ni(rst_ni), .ce_i(req_fire),
        .a_i(sigma0_i), .b_i(w_m16_i), .sum_o(b_q)
    );
    dsp58_add32_registered u_add_c (
        .clk_i(clk_i), .rst_ni(rst_ni), .ce_i(stage2_fire),
        .a_i(a_q), .b_i(b_q), .sum_o(w_new_w)
    );

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            v1_q <= 1'b0;
            v2_q <= 1'b0;
            engine1_q <= '0;
            round1_q <= '0;
            engine2_q <= '0;
            round2_q <= '0;
        end else begin
            if (stage2_ready) begin
                v2_q <= v1_q;
                if (v1_q) begin
                    engine2_q <= engine1_q;
                    round2_q <= round1_q;
                end
            end

            if (stage1_ready) begin
                v1_q <= req_valid_i;
                if (req_fire) begin
                    engine1_q <= req_engine_i;
                    round1_q <= req_round_i;
                end
            end
        end
    end
endmodule
