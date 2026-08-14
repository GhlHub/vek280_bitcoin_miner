`timescale 1ns/1ps

module tb_sha256_interleaved_proto;
    reg clk_slow = 1'b0, clk_fast = 1'b0, rst_n = 1'b0, start = 1'b0;
    wire busy, done;
    wire req_valid, req_ready, rsp_valid, rsp_ready;
    wire [31:0] sigma1, w_m7, sigma0, w_m16, w_new;
    wire [4:0] req_engine, rsp_engine;
    wire [5:0] req_round, rsp_round;
    reg [255:0] digest;
    reg [31:0] expected_w [0:63];
    integer schedule_errors = 0;
    integer cycles = 0;

    localparam [511:0] ABC_BLOCK = {32'h61626380, 416'h0, 64'h18};
    localparam [255:0] SHA256_ABC = 256'hba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad;
    localparam [255:0] SHA256_IV = 256'h6a09e667bb67ae853c6ef372a54ff53a510e527f9b05688c1f83d9ab5be0cd19;

    always #2.0 clk_slow = ~clk_slow;
    always #0.666 clk_fast = ~clk_fast;

    function automatic [31:0] rotr(input [31:0] x, input integer n);
        rotr = (x >> n) | (x << (32 - n));
    endfunction

    sha256_core_interleaved_proto u_core (
        .clk_i(clk_slow), .rst_ni(rst_n), .start_i(start),
        .block_i(ABC_BLOCK), .h_i(SHA256_IV), .busy_o(busy),
        .done_o(done), .digest_o(digest),
        .sched_req_valid_o(req_valid), .sched_req_ready_i(req_ready),
        .sched_sigma1_o(sigma1), .sched_w_m7_o(w_m7),
        .sched_sigma0_o(sigma0), .sched_w_m16_o(w_m16),
        .sched_engine_o(req_engine), .sched_round_o(req_round),
        .sched_rsp_valid_i(rsp_valid), .sched_rsp_ready_o(rsp_ready),
        .sched_w_new_i(w_new), .sched_rsp_engine_i(rsp_engine),
        .sched_rsp_round_i(rsp_round)
    );

    dsp58_schedule_xpm_cdc u_service (
        .clk_slow_i(clk_slow), .rst_slow_ni(rst_n),
        .req_valid_i(req_valid), .req_ready_o(req_ready),
        .sigma1_i(sigma1), .w_m7_i(w_m7), .sigma0_i(sigma0),
        .w_m16_i(w_m16), .req_engine_i(req_engine),
        .req_round_i(req_round), .rsp_valid_o(rsp_valid),
        .rsp_ready_i(rsp_ready), .w_new_o(w_new),
        .rsp_engine_o(rsp_engine), .rsp_round_o(rsp_round),
        .clk_fast_i(clk_fast), .rst_fast_ni(rst_n)
    );

    always @(posedge clk_slow) begin
        if (busy)
            cycles = cycles + 1;
        if (req_valid && req_ready && req_round >= 16) begin
            if (sigma1 !== (rotr(expected_w[req_round-2], 17) ^
                            rotr(expected_w[req_round-2], 19) ^
                            (expected_w[req_round-2] >> 10)) ||
                w_m7 !== expected_w[req_round-7] ||
                sigma0 !== (rotr(expected_w[req_round-15], 7) ^
                            rotr(expected_w[req_round-15], 18) ^
                            (expected_w[req_round-15] >> 3)) ||
                w_m16 !== expected_w[req_round-16]) begin
                $display("FAIL schedule operands round %0d", req_round);
                schedule_errors = schedule_errors + 1;
            end
        end
        if (rsp_valid && rsp_ready && rsp_round >= 16 &&
            w_new !== expected_w[rsp_round]) begin
            $display("FAIL schedule result round %0d got %08h expected %08h",
                rsp_round, w_new, expected_w[rsp_round]);
            schedule_errors = schedule_errors + 1;
        end
    end

    initial begin
        repeat (8) @(posedge clk_slow);
        rst_n = 1'b1;
        repeat (8) @(posedge clk_slow);
        for (integer n = 0; n < 16; n = n + 1)
            expected_w[n] = ABC_BLOCK[511 - (n * 32) -: 32];
        for (integer n = 16; n < 64; n = n + 1)
            expected_w[n] = (rotr(expected_w[n-2], 17) ^ rotr(expected_w[n-2], 19) ^
                (expected_w[n-2] >> 10)) + expected_w[n-7] +
                (rotr(expected_w[n-15], 7) ^ rotr(expected_w[n-15], 18) ^
                (expected_w[n-15] >> 3)) + expected_w[n-16];
        @(negedge clk_slow);
        start = 1'b1;
        @(negedge clk_slow);
        start = 1'b0;
        wait (done);
        if (schedule_errors != 0)
            $display("Schedule errors: %0d", schedule_errors);
        if (digest !== SHA256_ABC) begin
            $display("FAIL interleaved SHA digest %064h expected %064h after %0d cycles",
                digest, SHA256_ABC, cycles);
        end else begin
            $display("PASS interleaved SHA abc %064h after %0d slow cycles",
                digest, cycles);
        end
        $finish;
    end
endmodule
