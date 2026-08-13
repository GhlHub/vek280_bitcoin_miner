`timescale 1ns/1ps

// CDC wrapper for the fast schedule service using AMD's XPM asynchronous
// FIFO.  XPM supplies the CDC synchronizers and implementation mapping; this
// wrapper keeps the 250 MHz and 750 MHz interfaces independent.
module dsp58_schedule_xpm_cdc #(
    parameter int unsigned ENGINE_TAG_WIDTH = 5,
    parameter int unsigned ROUND_TAG_WIDTH = 6,
    parameter int unsigned FIFO_DEPTH = 16
) (
    input wire clk_slow_i, input wire rst_slow_ni,
    input wire req_valid_i, output wire req_ready_o,
    input wire [31:0] sigma1_i, input wire [31:0] w_m7_i,
    input wire [31:0] sigma0_i, input wire [31:0] w_m16_i,
    input wire [ENGINE_TAG_WIDTH-1:0] req_engine_i,
    input wire [ROUND_TAG_WIDTH-1:0] req_round_i,
    output wire rsp_valid_o, input wire rsp_ready_i,
    output wire [31:0] w_new_o,
    output wire [ENGINE_TAG_WIDTH-1:0] rsp_engine_o,
    output wire [ROUND_TAG_WIDTH-1:0] rsp_round_o,
    input wire clk_fast_i, input wire rst_fast_ni
);
    localparam int unsigned REQ_WIDTH = 32 * 4 + ENGINE_TAG_WIDTH + ROUND_TAG_WIDTH;
    localparam int unsigned RSP_WIDTH = 32 + ENGINE_TAG_WIDTH + ROUND_TAG_WIDTH;
    localparam int unsigned ADDR_WIDTH = $clog2(FIFO_DEPTH);

    wire [REQ_WIDTH-1:0] req_fifo_din;
    wire [REQ_WIDTH-1:0] req_fifo_dout;
    wire req_fifo_full, req_fifo_empty;
    wire req_fifo_wr_en = req_valid_i && !req_fifo_full;
    wire req_fifo_rd_en;
    wire req_fifo_wr_rst_busy, req_fifo_rd_rst_busy;
    wire [RSP_WIDTH-1:0] rsp_fifo_din;
    wire [RSP_WIDTH-1:0] rsp_fifo_dout;
    wire rsp_fifo_full, rsp_fifo_empty;
    wire rsp_fifo_wr_en;
    wire rsp_fifo_rd_en;
    wire rsp_fifo_wr_rst_busy, rsp_fifo_rd_rst_busy;
    wire req_valid_fast, req_ready_fast;
    wire [31:0] sigma1_fast, w_m7_fast, sigma0_fast, w_m16_fast;
    wire [ENGINE_TAG_WIDTH-1:0] engine_fast;
    wire [ROUND_TAG_WIDTH-1:0] round_fast;
    wire pipe_rsp_valid, pipe_rsp_ready;
    wire [31:0] pipe_w_new;
    wire [ENGINE_TAG_WIDTH-1:0] pipe_engine;
    wire [ROUND_TAG_WIDTH-1:0] pipe_round;

    assign req_fifo_din = {sigma1_i, w_m7_i, sigma0_i, w_m16_i,
                           req_engine_i, req_round_i};
    assign req_ready_o = !req_fifo_full && !req_fifo_wr_rst_busy;
    assign req_fifo_rd_en = !req_fifo_empty && !req_fifo_rd_rst_busy &&
                            req_ready_fast;
    assign rsp_valid_o = !rsp_fifo_empty && !rsp_fifo_rd_rst_busy;
    assign rsp_fifo_rd_en = rsp_ready_i && rsp_valid_o;
    assign {w_new_o, rsp_engine_o, rsp_round_o} = rsp_fifo_dout;

    xpm_fifo_async #(
        .CDC_SYNC_STAGES(3), .DOUT_RESET_VALUE("0"),
        .ECC_MODE("no_ecc"), .FIFO_MEMORY_TYPE("distributed"),
        .FIFO_READ_LATENCY(0), .FIFO_WRITE_DEPTH(FIFO_DEPTH),
        .FULL_RESET_VALUE(0), .PROG_EMPTY_THRESH(5),
        .PROG_FULL_THRESH(FIFO_DEPTH-5), .RD_DATA_COUNT_WIDTH(1),
        .READ_DATA_WIDTH(REQ_WIDTH), .READ_MODE("fwft"),
        .RELATED_CLOCKS(0), .USE_ADV_FEATURES("0000"),
        .WAKEUP_TIME(0), .WRITE_DATA_WIDTH(REQ_WIDTH)
    ) u_req_fifo (
        .almost_empty(), .almost_full(), .data_valid(), .dbiterr(),
        .dout(req_fifo_dout), .empty(req_fifo_empty), .full(req_fifo_full),
        .overflow(), .prog_empty(), .prog_full(), .rd_data_count(),
        .rd_rst_busy(req_fifo_rd_rst_busy), .sbiterr(),
        .underflow(), .wr_ack(), .wr_data_count(),
        .wr_rst_busy(req_fifo_wr_rst_busy), .din(req_fifo_din),
        .injectdbiterr(1'b0), .injectsbiterr(1'b0),
        .rd_clk(clk_fast_i), .rd_en(req_fifo_rd_en),
        .rst(!(rst_slow_ni && rst_fast_ni)), .sleep(1'b0),
        .wr_clk(clk_slow_i), .wr_en(req_fifo_wr_en)
    );

    assign req_valid_fast = !req_fifo_empty && !req_fifo_rd_rst_busy;

    assign {sigma1_fast, w_m7_fast, sigma0_fast, w_m16_fast,
            engine_fast, round_fast} = req_fifo_dout;
    assign pipe_rsp_ready = !rsp_fifo_full && !rsp_fifo_wr_rst_busy;

    dsp58_schedule_pipeline #(
        .ENGINE_TAG_WIDTH(ENGINE_TAG_WIDTH), .ROUND_TAG_WIDTH(ROUND_TAG_WIDTH)
    ) u_pipeline (
        .clk_i(clk_fast_i), .rst_ni(rst_fast_ni),
        .req_valid_i(req_valid_fast), .req_ready_o(req_ready_fast),
        .sigma1_i(sigma1_fast), .w_m7_i(w_m7_fast),
        .sigma0_i(sigma0_fast), .w_m16_i(w_m16_fast),
        .req_engine_i(engine_fast), .req_round_i(round_fast),
        .rsp_valid_o(pipe_rsp_valid), .rsp_ready_i(pipe_rsp_ready),
        .w_new_o(pipe_w_new), .rsp_engine_o(pipe_engine),
        .rsp_round_o(pipe_round)
    );

    assign rsp_fifo_wr_en = pipe_rsp_valid && pipe_rsp_ready;
    assign rsp_fifo_din = {pipe_w_new, pipe_engine, pipe_round};

    xpm_fifo_async #(
        .CDC_SYNC_STAGES(3), .DOUT_RESET_VALUE("0"),
        .ECC_MODE("no_ecc"), .FIFO_MEMORY_TYPE("distributed"),
        .FIFO_READ_LATENCY(0), .FIFO_WRITE_DEPTH(FIFO_DEPTH),
        .FULL_RESET_VALUE(0), .PROG_EMPTY_THRESH(5),
        .PROG_FULL_THRESH(FIFO_DEPTH-5), .RD_DATA_COUNT_WIDTH(1),
        .READ_DATA_WIDTH(RSP_WIDTH), .READ_MODE("fwft"),
        .RELATED_CLOCKS(0), .USE_ADV_FEATURES("0000"),
        .WAKEUP_TIME(0), .WRITE_DATA_WIDTH(RSP_WIDTH)
    ) u_rsp_fifo (
        .almost_empty(), .almost_full(), .data_valid(), .dbiterr(),
        .dout(rsp_fifo_dout), .empty(rsp_fifo_empty), .full(rsp_fifo_full),
        .overflow(), .prog_empty(), .prog_full(), .rd_data_count(),
        .rd_rst_busy(rsp_fifo_rd_rst_busy), .sbiterr(),
        .underflow(), .wr_ack(), .wr_data_count(),
        .wr_rst_busy(rsp_fifo_wr_rst_busy), .din(rsp_fifo_din),
        .injectdbiterr(1'b0), .injectsbiterr(1'b0),
        .rd_clk(clk_slow_i), .rd_en(rsp_fifo_rd_en),
        .rst(!(rst_slow_ni && rst_fast_ni)), .sleep(1'b0),
        .wr_clk(clk_fast_i), .wr_en(rsp_fifo_wr_en)
    );
endmodule
