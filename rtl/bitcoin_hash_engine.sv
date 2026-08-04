`timescale 1ns/1ps

module bitcoin_hash_engine #(
    parameter int unsigned NONCE_STRIDE = 1
) (
    input  wire         clk_i,
    input  wire         rst_ni,
    input  wire         start_i,
    input  wire         stop_i,
    input  wire [255:0] midstate_i,
    input  wire [127:0] header_tail_i,
    input  wire [255:0] target_i,
    input  wire [31:0]  nonce_start_i,
    input  wire [31:0]  nonce_count_i,
    output wire         busy_o,
    output reg          done_o,
    output reg          result_valid_o,
    output reg  [31:0]  result_nonce_o,
    output reg  [255:0] result_hash_o
);
    localparam [1:0] ST_IDLE  = 2'd0;
    localparam [1:0] ST_PASS1 = 2'd1;
    localparam [1:0] ST_PASS2 = 2'd2;
    localparam [1:0] ST_CHECK = 2'd3;

    reg [1:0]   state_q;
    reg         core_start_q;
    reg [511:0] core_block_q;
    reg [255:0] core_h_q;
    wire        core_busy;
    wire        core_done;
    wire [255:0] core_digest;
    localparam [31:0] NONCE_STRIDE_W = NONCE_STRIDE;

    reg [255:0] midstate_q;
    reg [127:0] header_tail_q;
    reg [255:0] target_q;
    reg [31:0]  nonce_q;
    reg [31:0]  remaining_q;

    assign busy_o = (state_q != ST_IDLE) || core_busy;

    sha256_core_fabric u_core (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .start_i(core_start_q),
        .block_i(core_block_q),
        .h_i(core_h_q),
        .busy_o(core_busy),
        .done_o(core_done),
        .digest_o(core_digest)
    );

    function automatic [511:0] make_first_pass_block(
        input [127:0] header_tail,
        input [31:0] nonce
    );
        begin
            make_first_pass_block = {
                header_tail[127:96],
                header_tail[95:64],
                header_tail[63:32],
                nonce | (header_tail[31:0] & 32'h00000000),
                32'h80000000,
                32'h00000000,
                32'h00000000,
                32'h00000000,
                32'h00000000,
                32'h00000000,
                32'h00000000,
                32'h00000000,
                32'h00000000,
                32'h00000000,
                32'h00000000,
                32'h00000280
            };
        end
    endfunction

    function automatic [511:0] make_second_pass_block(input [255:0] digest);
        begin
            make_second_pass_block = {
                digest,
                32'h80000000,
                32'h00000000,
                32'h00000000,
                32'h00000000,
                32'h00000000,
                32'h00000000,
                32'h00000000,
                32'h00000100
            };
        end
    endfunction

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q <= ST_IDLE;
            core_start_q <= 1'b0;
            core_block_q <= 512'h0;
            core_h_q <= 256'h0;
            midstate_q <= 256'h0;
            header_tail_q <= 128'h0;
            target_q <= 256'h0;
            nonce_q <= 32'h0;
            remaining_q <= 32'h0;
            done_o <= 1'b0;
            result_valid_o <= 1'b0;
            result_nonce_o <= 32'h0;
            result_hash_o <= 256'h0;
        end else begin
            core_start_q <= 1'b0;
            done_o <= 1'b0;
            result_valid_o <= 1'b0;

            if (stop_i) begin
                state_q <= ST_IDLE;
                done_o <= (state_q != ST_IDLE);
            end else begin
                case (state_q)
                    ST_IDLE: begin
                        if (start_i && (nonce_count_i != 32'd0)) begin
                            midstate_q <= midstate_i;
                            header_tail_q <= header_tail_i;
                            target_q <= target_i;
                            nonce_q <= nonce_start_i;
                            remaining_q <= nonce_count_i;
                            core_block_q <= make_first_pass_block(header_tail_i, nonce_start_i);
                            core_h_q <= midstate_i;
                            core_start_q <= 1'b1;
                            state_q <= ST_PASS1;
                        end
                    end

                    ST_PASS1: begin
                        if (core_done) begin
                            core_block_q <= make_second_pass_block(core_digest);
                            core_h_q <= {
                                32'h6a09e667, 32'hbb67ae85, 32'h3c6ef372, 32'ha54ff53a,
                                32'h510e527f, 32'h9b05688c, 32'h1f83d9ab, 32'h5be0cd19
                            };
                            core_start_q <= 1'b1;
                            state_q <= ST_PASS2;
                        end
                    end

                    ST_PASS2: begin
                        if (core_done) begin
                            result_hash_o <= core_digest;
                            if (core_digest <= target_q) begin
                                result_valid_o <= 1'b1;
                                result_nonce_o <= nonce_q;
                            end
                            state_q <= ST_CHECK;
                        end
                    end

                    ST_CHECK: begin
                        if (remaining_q <= 32'd1) begin
                            done_o <= 1'b1;
                            state_q <= ST_IDLE;
                        end else begin
                            remaining_q <= remaining_q - 32'd1;
                            nonce_q <= nonce_q + NONCE_STRIDE_W;
                            core_block_q <= make_first_pass_block(header_tail_q, nonce_q + NONCE_STRIDE_W);
                            core_h_q <= midstate_q;
                            core_start_q <= 1'b1;
                            state_q <= ST_PASS1;
                        end
                    end

                    default: begin
                        state_q <= ST_IDLE;
                    end
                endcase
            end
        end
    end
endmodule
