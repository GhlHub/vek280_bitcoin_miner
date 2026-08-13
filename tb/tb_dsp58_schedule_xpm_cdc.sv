`timescale 1ns/1ps

// Minimal global simulation unit required by the XPM library in a standalone
// xvlog/xelab flow.
module glbl;
    wire GSR = 1'b0;
    wire GTS = 1'b0;
endmodule

module tb_dsp58_schedule_xpm_cdc;
    reg clk_slow = 1'b0, clk_fast = 1'b0;
    reg rst_slow_n = 1'b0, rst_fast_n = 1'b0;
    reg req_valid = 1'b0, rsp_ready = 1'b1;
    reg [31:0] sigma1, w_m7, sigma0, w_m16;
    reg [4:0] req_engine;
    reg [5:0] req_round;
    wire req_ready, rsp_valid;
    wire [31:0] w_new;
    wire [4:0] rsp_engine;
    wire [5:0] rsp_round;
    reg [31:0] expected [0:31];
    reg [4:0] expected_engine [0:31];
    reg [5:0] expected_round [0:31];
    integer sent = 0, received = 0, errors = 0;

    always #2.0 clk_slow = ~clk_slow;
    always #0.666 clk_fast = ~clk_fast;

    dsp58_schedule_xpm_cdc dut (
        .clk_slow_i(clk_slow), .rst_slow_ni(rst_slow_n),
        .req_valid_i(req_valid), .req_ready_o(req_ready),
        .sigma1_i(sigma1), .w_m7_i(w_m7), .sigma0_i(sigma0),
        .w_m16_i(w_m16), .req_engine_i(req_engine),
        .req_round_i(req_round), .rsp_valid_o(rsp_valid),
        .rsp_ready_i(rsp_ready), .w_new_o(w_new),
        .rsp_engine_o(rsp_engine), .rsp_round_o(rsp_round),
        .clk_fast_i(clk_fast), .rst_fast_ni(rst_fast_n)
    );

    always @(posedge clk_slow) begin
        if (rsp_valid && rsp_ready) begin
            if (w_new !== expected[received] ||
                rsp_engine !== expected_engine[received] ||
                rsp_round !== expected_round[received]) begin
                $display("FAIL XPM CDC response %0d got %08h/%0d/%0d expected %08h/%0d/%0d",
                    received, w_new, rsp_engine, rsp_round,
                    expected[received], expected_engine[received],
                    expected_round[received]);
                errors = errors + 1;
            end
            received = received + 1;
        end
    end

    task automatic send(input integer n);
        begin
            sigma1 = 32'h11000000 + n;
            w_m7 = 32'h00200000 + (n * 5);
            sigma0 = 32'h22000000 + (n * 9);
            w_m16 = 32'h00003000 + n;
            req_engine = n[4:0];
            req_round = (n * 3) + 2;
            expected[sent] = sigma1 + w_m7 + sigma0 + w_m16;
            expected_engine[sent] = req_engine;
            expected_round[sent] = req_round;
            while (!req_ready) @(negedge clk_slow);
            req_valid = 1'b1;
            @(posedge clk_slow);
            @(negedge clk_slow);
            req_valid = 1'b0;
            sent = sent + 1;
        end
    endtask

    initial begin
        sigma1 = 0; w_m7 = 0; sigma0 = 0; w_m16 = 0;
        req_engine = 0; req_round = 0;
        repeat (6) @(posedge clk_slow);
        rst_slow_n = 1'b1;
        rst_fast_n = 1'b1;
        repeat (8) @(posedge clk_slow);
        for (integer n = 0; n < 16; n = n + 1)
            send(n);
        repeat (4) @(posedge clk_slow);
        rsp_ready = 1'b0;
        repeat (8) @(posedge clk_slow);
        rsp_ready = 1'b1;
        repeat (40) @(posedge clk_slow);
        if (received != sent)
            errors = errors + 1;
        if (errors == 0)
            $display("ALL XPM CDC TESTS PASSED (%0d responses)", received);
        else
            $display("FAIL XPM CDC: %0d errors, %0d/%0d responses", errors, received, sent);
        $finish;
    end
endmodule
