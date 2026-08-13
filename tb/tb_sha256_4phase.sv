`timescale 1ns/1ps

module tb_sha256_4phase;
    reg clk = 1'b0, rst_n = 1'b0, start = 1'b0;
    wire base_busy, base_done, fast_busy, fast_done;
    wire [255:0] base_digest, fast_digest;
    integer base_cycles = 0, fast_cycles = 0;
    reg base_seen = 1'b0, fast_seen = 1'b0;
    localparam [511:0] BLOCK = {32'h61626380, 416'h0, 64'h18};
    localparam [255:0] IV = 256'h6a09e667bb67ae853c6ef372a54ff53a510e527f9b05688c1f83d9ab5be0cd19;
    localparam [255:0] EXPECTED = 256'hba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad;

    always #2 clk = ~clk;
    sha256_core_iterative #(.EXPLICIT_DSP_SCHEDULE(1'b1)) u_base (
        .clk_i(clk), .rst_ni(rst_n), .start_i(start), .block_i(BLOCK), .h_i(IV),
        .busy_o(base_busy), .done_o(base_done), .digest_o(base_digest));
    sha256_core_4phase u_fast (
        .clk_i(clk), .rst_ni(rst_n), .start_i(start), .block_i(BLOCK), .h_i(IV),
        .busy_o(fast_busy), .done_o(fast_done), .digest_o(fast_digest));
    always @(posedge clk) begin
        if (base_busy) base_cycles = base_cycles + 1;
        if (fast_busy) fast_cycles = fast_cycles + 1;
        if (base_done) base_seen = 1'b1;
        if (fast_done) fast_seen = 1'b1;
    end
    initial begin
        repeat (4) @(posedge clk); rst_n = 1'b1;
        @(negedge clk); start = 1'b1;
        @(negedge clk); start = 1'b0;
        wait (base_seen && fast_seen);
        if (base_digest !== EXPECTED || fast_digest !== EXPECTED)
            $display("FAIL four-phase digest base=%064h four=%064h", base_digest, fast_digest);
        else if (fast_cycles >= base_cycles)
            $display("FAIL four-phase did not reduce cycles base=%0d four=%0d", base_cycles, fast_cycles);
        else
            $display("PASS four-phase digest base=%0d cycles four=%0d cycles", base_cycles, fast_cycles);
        $finish;
    end
endmodule
