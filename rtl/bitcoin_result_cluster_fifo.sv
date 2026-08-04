`timescale 1ns/1ps

module bitcoin_result_cluster_fifo #(
    parameter int unsigned CLUSTER_INDEX = 0,
    parameter int unsigned CLUSTER_SIZE = 16,
    parameter int unsigned FIFO_DEPTH = 2
) (
    input  wire                         clk_i,
    input  wire                         rst_ni,
    input  wire                         clear_i,
    input  wire                         pop_i,
    input  wire [CLUSTER_SIZE-1:0]      engine_valid_i,
    input  wire [CLUSTER_SIZE*32-1:0]   engine_nonce_i,
    input  wire [CLUSTER_SIZE*256-1:0]  engine_hash_i,
    output wire                         valid_o,
    output wire [31:0]                  engine_id_o,
    output wire [31:0]                  nonce_o,
    output wire [255:0]                 hash_o,
    output reg                          overflow_o
);
    localparam int unsigned PTR_WIDTH = (FIFO_DEPTH <= 2) ? 1 : $clog2(FIFO_DEPTH);
    localparam [31:0] CLUSTER_BASE_ID = CLUSTER_INDEX * CLUSTER_SIZE;

    reg [31:0]  engine_id_mem [0:FIFO_DEPTH-1];
    reg [31:0]  nonce_mem [0:FIFO_DEPTH-1];
    reg [255:0] hash_mem [0:FIFO_DEPTH-1];
    reg [PTR_WIDTH-1:0] wr_ptr_q;
    reg [PTR_WIDTH-1:0] rd_ptr_q;
    reg [PTR_WIDTH:0] count_q;

    integer i;
    integer hit_idx;
    integer valid_count;
    reg push_valid;
    reg [31:0] push_engine_id;
    reg [31:0] push_nonce;
    reg [255:0] push_hash;
    wire do_pop;
    wire do_push;

    assign valid_o = (count_q != 0);
    assign engine_id_o = engine_id_mem[rd_ptr_q];
    assign nonce_o = nonce_mem[rd_ptr_q];
    assign hash_o = hash_mem[rd_ptr_q];
    assign do_pop = pop_i && (count_q != 0);
    assign do_push = push_valid && ((count_q < FIFO_DEPTH[PTR_WIDTH:0]) || do_pop);

    always @(*) begin
        hit_idx = -1;
        valid_count = 0;
        push_valid = 1'b0;
        push_engine_id = 32'h0;
        push_nonce = 32'h0;
        push_hash = 256'h0;

        for (i = 0; i < CLUSTER_SIZE; i = i + 1) begin
            if (engine_valid_i[i]) begin
                valid_count = valid_count + 1;
                if (hit_idx < 0) begin
                    hit_idx = i;
                end
            end
        end

        if (hit_idx >= 0) begin
            push_valid = 1'b1;
            push_engine_id = CLUSTER_BASE_ID + hit_idx[31:0];
            push_nonce = engine_nonce_i[hit_idx*32 +: 32];
            push_hash = engine_hash_i[hit_idx*256 +: 256];
        end
    end

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            wr_ptr_q <= {PTR_WIDTH{1'b0}};
            rd_ptr_q <= {PTR_WIDTH{1'b0}};
            count_q <= {(PTR_WIDTH+1){1'b0}};
            overflow_o <= 1'b0;
            for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
                engine_id_mem[i] <= 32'h0;
                nonce_mem[i] <= 32'h0;
                hash_mem[i] <= 256'h0;
            end
        end else begin
            if (clear_i) begin
                wr_ptr_q <= {PTR_WIDTH{1'b0}};
                rd_ptr_q <= {PTR_WIDTH{1'b0}};
                count_q <= {(PTR_WIDTH+1){1'b0}};
                overflow_o <= 1'b0;
            end else begin
                if (push_valid && !do_push) begin
                    overflow_o <= 1'b1;
                end
                if (valid_count > 1) begin
                    overflow_o <= 1'b1;
                end

                if (do_push) begin
                    engine_id_mem[wr_ptr_q] <= push_engine_id;
                    nonce_mem[wr_ptr_q] <= push_nonce;
                    hash_mem[wr_ptr_q] <= push_hash;
                    if (wr_ptr_q == FIFO_DEPTH[PTR_WIDTH-1:0] - {{(PTR_WIDTH-1){1'b0}}, 1'b1}) begin
                        wr_ptr_q <= {PTR_WIDTH{1'b0}};
                    end else begin
                        wr_ptr_q <= wr_ptr_q + {{(PTR_WIDTH-1){1'b0}}, 1'b1};
                    end
                end

                if (do_pop) begin
                    if (rd_ptr_q == FIFO_DEPTH[PTR_WIDTH-1:0] - {{(PTR_WIDTH-1){1'b0}}, 1'b1}) begin
                        rd_ptr_q <= {PTR_WIDTH{1'b0}};
                    end else begin
                        rd_ptr_q <= rd_ptr_q + {{(PTR_WIDTH-1){1'b0}}, 1'b1};
                    end
                end

                case ({do_push, do_pop})
                    2'b10: count_q <= count_q + {{PTR_WIDTH{1'b0}}, 1'b1};
                    2'b01: count_q <= count_q - {{PTR_WIDTH{1'b0}}, 1'b1};
                    default: count_q <= count_q;
                endcase
            end
        end
    end
endmodule
