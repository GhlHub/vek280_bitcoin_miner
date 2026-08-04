`timescale 1ns/1ps

module sha256_core_iterative (
    input  wire         clk_i,
    input  wire         rst_ni,
    input  wire         start_i,
    input  wire [511:0] block_i,
    input  wire [255:0] h_i,
    output wire         busy_o,
    output reg          done_o,
    output reg  [255:0] digest_o
);
    localparam [6:0] ROUNDS = 7'd64;

    reg [31:0] w_mem [0:15];
    reg [31:0] h0_q;
    reg [31:0] h1_q;
    reg [31:0] h2_q;
    reg [31:0] h3_q;
    reg [31:0] h4_q;
    reg [31:0] h5_q;
    reg [31:0] h6_q;
    reg [31:0] h7_q;
    reg [31:0] a_q;
    reg [31:0] b_q;
    reg [31:0] c_q;
    reg [31:0] d_q;
    reg [31:0] e_q;
    reg [31:0] f_q;
    reg [31:0] g_q;
    reg [31:0] h_q;
    reg [6:0]  round_q;
    reg        busy_q;

    wire [3:0] w_idx = round_q[3:0];
    wire [3:0] w_idx_m2 = round_q[3:0] - 4'd2;
    wire [3:0] w_idx_m7 = round_q[3:0] - 4'd7;
    wire [3:0] w_idx_m15 = round_q[3:0] - 4'd15;
    wire [3:0] w_idx_m16 = round_q[3:0] - 4'd0;
    wire [31:0] w_new;
    wire [31:0] w_round = (round_q < 16) ? w_mem[w_idx] : w_new;
    wire [31:0] t1;
    wire [31:0] t2;
    wire [31:0] a_next;
    wire [31:0] e_next;
    wire [31:0] digest_h0;
    wire [31:0] digest_h1;
    wire [31:0] digest_h2;
    wire [31:0] digest_h3;
    wire [31:0] digest_h4;
    wire [31:0] digest_h5;
    wire [31:0] digest_h6;
    wire [31:0] digest_h7;

    assign busy_o = busy_q;

    function automatic [31:0] rotr(input [31:0] x, input int unsigned n);
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

    function automatic [31:0] k(input [6:0] idx);
        case (idx)
            7'd0:  k = 32'h428a2f98; 7'd1:  k = 32'h71374491;
            7'd2:  k = 32'hb5c0fbcf; 7'd3:  k = 32'he9b5dba5;
            7'd4:  k = 32'h3956c25b; 7'd5:  k = 32'h59f111f1;
            7'd6:  k = 32'h923f82a4; 7'd7:  k = 32'hab1c5ed5;
            7'd8:  k = 32'hd807aa98; 7'd9:  k = 32'h12835b01;
            7'd10: k = 32'h243185be; 7'd11: k = 32'h550c7dc3;
            7'd12: k = 32'h72be5d74; 7'd13: k = 32'h80deb1fe;
            7'd14: k = 32'h9bdc06a7; 7'd15: k = 32'hc19bf174;
            7'd16: k = 32'he49b69c1; 7'd17: k = 32'hefbe4786;
            7'd18: k = 32'h0fc19dc6; 7'd19: k = 32'h240ca1cc;
            7'd20: k = 32'h2de92c6f; 7'd21: k = 32'h4a7484aa;
            7'd22: k = 32'h5cb0a9dc; 7'd23: k = 32'h76f988da;
            7'd24: k = 32'h983e5152; 7'd25: k = 32'ha831c66d;
            7'd26: k = 32'hb00327c8; 7'd27: k = 32'hbf597fc7;
            7'd28: k = 32'hc6e00bf3; 7'd29: k = 32'hd5a79147;
            7'd30: k = 32'h06ca6351; 7'd31: k = 32'h14292967;
            7'd32: k = 32'h27b70a85; 7'd33: k = 32'h2e1b2138;
            7'd34: k = 32'h4d2c6dfc; 7'd35: k = 32'h53380d13;
            7'd36: k = 32'h650a7354; 7'd37: k = 32'h766a0abb;
            7'd38: k = 32'h81c2c92e; 7'd39: k = 32'h92722c85;
            7'd40: k = 32'ha2bfe8a1; 7'd41: k = 32'ha81a664b;
            7'd42: k = 32'hc24b8b70; 7'd43: k = 32'hc76c51a3;
            7'd44: k = 32'hd192e819; 7'd45: k = 32'hd6990624;
            7'd46: k = 32'hf40e3585; 7'd47: k = 32'h106aa070;
            7'd48: k = 32'h19a4c116; 7'd49: k = 32'h1e376c08;
            7'd50: k = 32'h2748774c; 7'd51: k = 32'h34b0bcb5;
            7'd52: k = 32'h391c0cb3; 7'd53: k = 32'h4ed8aa4a;
            7'd54: k = 32'h5b9cca4f; 7'd55: k = 32'h682e6ff3;
            7'd56: k = 32'h748f82ee; 7'd57: k = 32'h78a5636f;
            7'd58: k = 32'h84c87814; 7'd59: k = 32'h8cc70208;
            7'd60: k = 32'h90befffa; 7'd61: k = 32'ha4506ceb;
            7'd62: k = 32'hbef9a3f7; 7'd63: k = 32'hc67178f2;
            default: k = 32'h00000000;
        endcase
    endfunction

    assign w_new = small_sigma1(w_mem[w_idx_m2]) +
                   w_mem[w_idx_m7] +
                   small_sigma0(w_mem[w_idx_m15]) +
                   w_mem[w_idx_m16];
    assign t1 = h_q + big_sigma1(e_q) + ch(e_q, f_q, g_q) + k(round_q) + w_round;
    assign t2 = big_sigma0(a_q) + maj(a_q, b_q, c_q);
    assign a_next = t1 + t2;
    assign e_next = d_q + t1;
    assign digest_h0 = h0_q + a_next;
    assign digest_h1 = h1_q + a_q;
    assign digest_h2 = h2_q + b_q;
    assign digest_h3 = h3_q + c_q;
    assign digest_h4 = h4_q + e_next;
    assign digest_h5 = h5_q + e_q;
    assign digest_h6 = h6_q + f_q;
    assign digest_h7 = h7_q + g_q;

    integer i;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            for (i = 0; i < 16; i = i + 1) begin
                w_mem[i] <= 32'h00000000;
            end
            h0_q <= 32'h00000000;
            h1_q <= 32'h00000000;
            h2_q <= 32'h00000000;
            h3_q <= 32'h00000000;
            h4_q <= 32'h00000000;
            h5_q <= 32'h00000000;
            h6_q <= 32'h00000000;
            h7_q <= 32'h00000000;
            a_q <= 32'h00000000;
            b_q <= 32'h00000000;
            c_q <= 32'h00000000;
            d_q <= 32'h00000000;
            e_q <= 32'h00000000;
            f_q <= 32'h00000000;
            g_q <= 32'h00000000;
            h_q <= 32'h00000000;
            round_q <= 7'd0;
            busy_q <= 1'b0;
            done_o <= 1'b0;
            digest_o <= 256'h0;
        end else begin
            done_o <= 1'b0;

            if (start_i && !busy_q) begin
                for (i = 0; i < 16; i = i + 1) begin
                    w_mem[i] <= block_i[511 - (i * 32) -: 32];
                end
                h0_q <= h_i[255:224];
                h1_q <= h_i[223:192];
                h2_q <= h_i[191:160];
                h3_q <= h_i[159:128];
                h4_q <= h_i[127:96];
                h5_q <= h_i[95:64];
                h6_q <= h_i[63:32];
                h7_q <= h_i[31:0];
                a_q <= h_i[255:224];
                b_q <= h_i[223:192];
                c_q <= h_i[191:160];
                d_q <= h_i[159:128];
                e_q <= h_i[127:96];
                f_q <= h_i[95:64];
                g_q <= h_i[63:32];
                h_q <= h_i[31:0];
                round_q <= 7'd0;
                busy_q <= 1'b1;
            end else if (busy_q) begin
                if (round_q >= 16) begin
                    w_mem[w_idx] <= w_new;
                end

                a_q <= a_next;
                b_q <= a_q;
                c_q <= b_q;
                d_q <= c_q;
                e_q <= e_next;
                f_q <= e_q;
                g_q <= f_q;
                h_q <= g_q;

                if (round_q == ROUNDS - 1) begin
                    digest_o <= {digest_h0, digest_h1, digest_h2, digest_h3,
                                 digest_h4, digest_h5, digest_h6, digest_h7};
                    busy_q <= 1'b0;
                    done_o <= 1'b1;
                end else begin
                    round_q <= round_q + 7'd1;
                end
            end
        end
    end
endmodule
