`timescale 1ns/1ps

module tb_sha256_cores;
    localparam [255:0] SHA256_IV = {
        32'h6a09e667, 32'hbb67ae85, 32'h3c6ef372, 32'ha54ff53a,
        32'h510e527f, 32'h9b05688c, 32'h1f83d9ab, 32'h5be0cd19
    };

    reg         clk;
    reg         rst_n;
    reg         start;
    reg [511:0] block;
    reg [255:0] h_in;
    wire        fabric_busy;
    wire        fabric_done;
    wire [255:0] fabric_digest;
    wire        dsp_busy;
    wire        dsp_done;
    wire [255:0] dsp_digest;

    integer failures;

    sha256_core_fabric u_fabric (
        .clk_i(clk),
        .rst_ni(rst_n),
        .start_i(start),
        .block_i(block),
        .h_i(h_in),
        .busy_o(fabric_busy),
        .done_o(fabric_done),
        .digest_o(fabric_digest)
    );

    sha256_core_dsp u_dsp (
        .clk_i(clk),
        .rst_ni(rst_n),
        .start_i(start),
        .block_i(block),
        .h_i(h_in),
        .busy_o(dsp_busy),
        .done_o(dsp_done),
        .digest_o(dsp_digest)
    );

    always #5 clk <= ~clk;

    function automatic [31:0] rotr(input [31:0] x, input integer n);
        rotr = (x >> n) | (x << (32 - n));
    endfunction

    function automatic [31:0] ch(input [31:0] x, input [31:0] y, input [31:0] z);
        ch = (x & y) ^ (~x & z);
    endfunction

    function automatic [31:0] maj(input [31:0] x, input [31:0] y, input [31:0] z);
        maj = (x & y) ^ (x & z) ^ (y & z);
    endfunction

    function automatic [31:0] big_sigma0(input [31:0] x);
        big_sigma0 = rotr(x, 2) ^ rotr(x, 13) ^ rotr(x, 22);
    endfunction

    function automatic [31:0] big_sigma1(input [31:0] x);
        big_sigma1 = rotr(x, 6) ^ rotr(x, 11) ^ rotr(x, 25);
    endfunction

    function automatic [31:0] small_sigma0(input [31:0] x);
        small_sigma0 = rotr(x, 7) ^ rotr(x, 18) ^ (x >> 3);
    endfunction

    function automatic [31:0] small_sigma1(input [31:0] x);
        small_sigma1 = rotr(x, 17) ^ rotr(x, 19) ^ (x >> 10);
    endfunction

    function automatic [31:0] k(input integer idx);
        begin
            case (idx)
                0:  k = 32'h428a2f98; 1:  k = 32'h71374491;
                2:  k = 32'hb5c0fbcf; 3:  k = 32'he9b5dba5;
                4:  k = 32'h3956c25b; 5:  k = 32'h59f111f1;
                6:  k = 32'h923f82a4; 7:  k = 32'hab1c5ed5;
                8:  k = 32'hd807aa98; 9:  k = 32'h12835b01;
                10: k = 32'h243185be; 11: k = 32'h550c7dc3;
                12: k = 32'h72be5d74; 13: k = 32'h80deb1fe;
                14: k = 32'h9bdc06a7; 15: k = 32'hc19bf174;
                16: k = 32'he49b69c1; 17: k = 32'hefbe4786;
                18: k = 32'h0fc19dc6; 19: k = 32'h240ca1cc;
                20: k = 32'h2de92c6f; 21: k = 32'h4a7484aa;
                22: k = 32'h5cb0a9dc; 23: k = 32'h76f988da;
                24: k = 32'h983e5152; 25: k = 32'ha831c66d;
                26: k = 32'hb00327c8; 27: k = 32'hbf597fc7;
                28: k = 32'hc6e00bf3; 29: k = 32'hd5a79147;
                30: k = 32'h06ca6351; 31: k = 32'h14292967;
                32: k = 32'h27b70a85; 33: k = 32'h2e1b2138;
                34: k = 32'h4d2c6dfc; 35: k = 32'h53380d13;
                36: k = 32'h650a7354; 37: k = 32'h766a0abb;
                38: k = 32'h81c2c92e; 39: k = 32'h92722c85;
                40: k = 32'ha2bfe8a1; 41: k = 32'ha81a664b;
                42: k = 32'hc24b8b70; 43: k = 32'hc76c51a3;
                44: k = 32'hd192e819; 45: k = 32'hd6990624;
                46: k = 32'hf40e3585; 47: k = 32'h106aa070;
                48: k = 32'h19a4c116; 49: k = 32'h1e376c08;
                50: k = 32'h2748774c; 51: k = 32'h34b0bcb5;
                52: k = 32'h391c0cb3; 53: k = 32'h4ed8aa4a;
                54: k = 32'h5b9cca4f; 55: k = 32'h682e6ff3;
                56: k = 32'h748f82ee; 57: k = 32'h78a5636f;
                58: k = 32'h84c87814; 59: k = 32'h8cc70208;
                60: k = 32'h90befffa; 61: k = 32'ha4506ceb;
                62: k = 32'hbef9a3f7; 63: k = 32'hc67178f2;
                default: k = 32'h00000000;
            endcase
        end
    endfunction

    function automatic [255:0] compress_ref(input [511:0] msg_block, input [255:0] h_state);
        reg [31:0] w [0:63];
        reg [31:0] a;
        reg [31:0] b;
        reg [31:0] c;
        reg [31:0] d;
        reg [31:0] e;
        reg [31:0] f;
        reg [31:0] g;
        reg [31:0] h;
        reg [31:0] h0;
        reg [31:0] h1;
        reg [31:0] h2;
        reg [31:0] h3;
        reg [31:0] h4;
        reg [31:0] h5;
        reg [31:0] h6;
        reg [31:0] h7;
        reg [31:0] t1;
        reg [31:0] t2;
        integer i;
        begin
            for (i = 0; i < 16; i = i + 1) begin
                w[i] = msg_block[511 - (i * 32) -: 32];
            end
            for (i = 16; i < 64; i = i + 1) begin
                w[i] = small_sigma1(w[i - 2]) + w[i - 7] + small_sigma0(w[i - 15]) + w[i - 16];
            end

            h0 = h_state[255:224];
            h1 = h_state[223:192];
            h2 = h_state[191:160];
            h3 = h_state[159:128];
            h4 = h_state[127:96];
            h5 = h_state[95:64];
            h6 = h_state[63:32];
            h7 = h_state[31:0];
            a = h0; b = h1; c = h2; d = h3;
            e = h4; f = h5; g = h6; h = h7;

            for (i = 0; i < 64; i = i + 1) begin
                t1 = h + big_sigma1(e) + ch(e, f, g) + k(i) + w[i];
                t2 = big_sigma0(a) + maj(a, b, c);
                h = g;
                g = f;
                f = e;
                e = d + t1;
                d = c;
                c = b;
                b = a;
                a = t1 + t2;
            end

            compress_ref = {h0 + a, h1 + b, h2 + c, h3 + d,
                            h4 + e, h5 + f, h6 + g, h7 + h};
        end
    endfunction

    function automatic [511:0] pad_single_block_0_to_55(input [447:0] msg, input integer bytes);
        reg [511:0] padded;
        integer i;
        begin
            padded = 512'h0;
            for (i = 0; i < bytes; i = i + 1) begin
                padded[511 - (i * 8) -: 8] = msg[447 - (i * 8) -: 8];
            end
            padded[511 - (bytes * 8) -: 8] = 8'h80;
            padded[63:0] = bytes * 8;
            pad_single_block_0_to_55 = padded;
        end
    endfunction

    task automatic run_block_case(
        input [1023:0] name,
        input [511:0]  block_i,
        input [255:0]  h_i,
        input [255:0]  expected_i
    );
        integer timeout;
        begin
            @(negedge clk);
            block = block_i;
            h_in = h_i;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            if (!(fabric_busy && dsp_busy)) begin
                $display("FAIL %0s: busy did not assert after start", name);
                failures = failures + 1;
            end

            timeout = 0;
            while (!(fabric_done && dsp_done) && timeout < 100) begin
                @(posedge clk);
                timeout = timeout + 1;
            end

            if (timeout >= 100) begin
                $display("FAIL %0s: timeout waiting for done", name);
                failures = failures + 1;
            end else begin
                if (fabric_digest !== expected_i) begin
                    $display("FAIL %0s fabric digest got %064h expected %064h",
                             name, fabric_digest, expected_i);
                    failures = failures + 1;
                end
                if (dsp_digest !== expected_i) begin
                    $display("FAIL %0s dsp digest got %064h expected %064h",
                             name, dsp_digest, expected_i);
                    failures = failures + 1;
                end
                if (fabric_digest !== dsp_digest) begin
                    $display("FAIL %0s fabric/dsp mismatch %064h %064h",
                             name, fabric_digest, dsp_digest);
                    failures = failures + 1;
                end
                if (fabric_digest === expected_i && dsp_digest === expected_i) begin
                    $display("PASS %0s %064h", name, expected_i);
                end
            end

            @(posedge clk);
        end
    endtask

    task automatic run_64_byte_message_case;
        reg [511:0] block0;
        reg [511:0] block1;
        reg [255:0] h_mid;
        reg [255:0] expected;
        begin
            block0 = 512'h000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f;
            block1 = 512'h80000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000200;
            h_mid = compress_ref(block0, SHA256_IV);
            expected = compress_ref(block1, h_mid);
            run_block_case("64-byte message block0", block0, SHA256_IV, h_mid);
            run_block_case("64-byte message block1", block1, h_mid, expected);
        end
    endtask

    task automatic run_bitcoin_header_case;
        reg [511:0] header_block0;
        reg [511:0] header_block1;
        reg [511:0] second_pass_block;
        reg [255:0] first_mid;
        reg [255:0] first_digest;
        reg [255:0] second_digest;
        begin
            header_block0 = 512'h000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f;
            header_block1 = 512'h404142434445464748494a4b4c4d4e4f800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000280;
            first_mid = compress_ref(header_block0, SHA256_IV);
            first_digest = compress_ref(header_block1, first_mid);
            second_pass_block = {first_digest, 8'h80, 184'h0, 64'd256};
            second_digest = compress_ref(second_pass_block, SHA256_IV);
            run_block_case("bitcoin header pass1 block0", header_block0, SHA256_IV, first_mid);
            run_block_case("bitcoin header pass1 block1", header_block1, first_mid, first_digest);
            run_block_case("bitcoin header pass2 block0", second_pass_block, SHA256_IV, second_digest);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        block = 512'h0;
        h_in = SHA256_IV;
        failures = 0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        run_block_case(
            "empty message",
            512'h80000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
            SHA256_IV,
            256'he3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        );

        run_block_case(
            "abc",
            pad_single_block_0_to_55({8'h61, 8'h62, 8'h63, 424'h0}, 3),
            SHA256_IV,
            256'hba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
        );

        run_64_byte_message_case();
        run_bitcoin_header_case();

        if (failures == 0) begin
            $display("ALL TESTS PASSED");
            $finish;
        end else begin
            $display("TESTS FAILED: %0d failure(s)", failures);
            $fatal(1);
        end
    end
endmodule
