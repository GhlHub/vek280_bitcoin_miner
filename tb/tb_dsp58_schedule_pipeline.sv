`timescale 1ns/1ps

module tb_dsp58_schedule_pipeline;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg req_valid = 1'b0;
    wire req_ready;
    reg [31:0] sigma1, w_m7, sigma0, w_m16;
    reg [4:0] req_engine;
    reg [5:0] req_round;
    wire rsp_valid;
    reg rsp_ready = 1'b1;
    wire [31:0] w_new;
    wire [4:0] rsp_engine;
    wire [5:0] rsp_round;
    integer errors = 0;
    integer sent = 0;
    integer received = 0;
    reg [31:0] expected [0:31];
    reg [4:0] expected_engine [0:31];
    reg [5:0] expected_round [0:31];

    always #0.666 clk = ~clk;

    dsp58_schedule_pipeline dut (
        .clk_i(clk), .rst_ni(rst_n), .req_valid_i(req_valid),
        .req_ready_o(req_ready), .sigma1_i(sigma1), .w_m7_i(w_m7),
        .sigma0_i(sigma0), .w_m16_i(w_m16), .req_engine_i(req_engine),
        .req_round_i(req_round), .rsp_valid_o(rsp_valid),
        .rsp_ready_i(rsp_ready), .w_new_o(w_new),
        .rsp_engine_o(rsp_engine), .rsp_round_o(rsp_round)
    );

    task automatic drive_request(input integer n);
        begin
            sigma1 = 32'h10000000 + n;
            w_m7 = 32'h01020300 + (n * 3);
            sigma0 = 32'h20000000 + (n * 7);
            w_m16 = 32'h00112200 + n;
            req_engine = n[4:0];
            req_round = (n * 2) + 1;
            expected[sent] = sigma1 + w_m7 + sigma0 + w_m16;
            expected_engine[sent] = req_engine;
            expected_round[sent] = req_round;
            @(negedge clk);
            while (!req_ready)
                @(negedge clk);
            req_valid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            while (!req_ready)
                @(negedge clk);
            req_valid = 1'b0;
            sent = sent + 1;
        end
    endtask

    always @(posedge clk) begin
        #0.01;
        if (rsp_valid && rsp_ready) begin
            if (w_new !== expected[received] ||
                rsp_engine !== expected_engine[received] ||
                rsp_round !== expected_round[received]) begin
                $display("FAIL response %0d got %08h/%0d/%0d expected %08h/%0d/%0d",
                         received, w_new, rsp_engine, rsp_round,
                         expected[received], expected_engine[received],
                         expected_round[received]);
                errors = errors + 1;
            end
            received = received + 1;
        end
    end

    initial begin
        sigma1 = 0; w_m7 = 0; sigma0 = 0; w_m16 = 0;
        req_engine = 0; req_round = 0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        for (integer n = 0; n < 12; n = n + 1)
            drive_request(n);

        repeat (4) @(posedge clk);
        rsp_ready = 1'b0;
        repeat (4) @(posedge clk);
        rsp_ready = 1'b1;

        repeat (12) @(posedge clk);
        if (received != sent)
            errors = errors + 1;
        if (errors == 0)
            $display("ALL DSP SCHEDULE PIPELINE TESTS PASSED (%0d responses)", received);
        else
            $display("FAIL DSP SCHEDULE PIPELINE: %0d errors", errors);
        $finish;
    end
endmodule
