`timescale 1ns/1ps

// Single-context proof core for the fast schedule service.  The SHA state
// remains in the slow clock domain; only expanded W[t] generation is supplied
// by the tagged 750 MHz service.
module sha256_core_interleaved_proto (
    input wire clk_i, input wire rst_ni, input wire start_i,
    input wire [511:0] block_i, input wire [255:0] h_i,
    output wire busy_o, output reg done_o, output reg [255:0] digest_o,
    output reg sched_req_valid_o, input wire sched_req_ready_i,
    output reg [31:0] sched_sigma1_o, output reg [31:0] sched_w_m7_o,
    output reg [31:0] sched_sigma0_o, output reg [31:0] sched_w_m16_o,
    output reg [4:0] sched_engine_o, output reg [5:0] sched_round_o,
    input wire sched_rsp_valid_i, output wire sched_rsp_ready_o,
    input wire [31:0] sched_w_new_i,
    input wire [4:0] sched_rsp_engine_i, input wire [5:0] sched_rsp_round_i
);
    localparam [2:0] PH_LAUNCH = 3'd0, PH_WAIT = 3'd1,
                     PH_CALC = 3'd2, PH_UPDATE = 3'd3;
    reg busy_q;
    reg [2:0] phase_q;
    reg [6:0] round_q;
    reg [31:0] w_mem [0:15];
    reg [31:0] h0_q, h1_q, h2_q, h3_q, h4_q, h5_q, h6_q, h7_q;
    reg [31:0] a_q, b_q, c_q, d_q, e_q, f_q, g_q, h_q;
    reg [31:0] t1_a_q, t1_b_q, t1_c_q, t1_q, t2_q, w_new_q;
    integer i;

    assign busy_o = busy_q;
    assign sched_rsp_ready_o = busy_q && (phase_q == PH_WAIT);

    function automatic [31:0] rotr(input [31:0] x, input integer n);
        rotr = (x >> n) | (x << (32 - n));
    endfunction
    function automatic [31:0] ch(input [31:0] x, input [31:0] y, input [31:0] z);
        ch = (x & y) ^ (~x & z);
    endfunction
    function automatic [31:0] maj(input [31:0] x, input [31:0] y, input [31:0] z);
        maj = (x & y) ^ (x & z) ^ (y & z);
    endfunction
    function automatic [31:0] small_sigma0(input [31:0] x);
        small_sigma0 = rotr(x, 7) ^ rotr(x, 18) ^ (x >> 3);
    endfunction
    function automatic [31:0] small_sigma1(input [31:0] x);
        small_sigma1 = rotr(x, 17) ^ rotr(x, 19) ^ (x >> 10);
    endfunction
    function automatic [31:0] big_sigma0(input [31:0] x);
        big_sigma0 = rotr(x, 2) ^ rotr(x, 13) ^ rotr(x, 22);
    endfunction
    function automatic [31:0] big_sigma1(input [31:0] x);
        big_sigma1 = rotr(x, 6) ^ rotr(x, 11) ^ rotr(x, 25);
    endfunction
    function automatic [31:0] k(input [6:0] n);
        case (n)
            0:k=32'h428a2f98; 1:k=32'h71374491; 2:k=32'hb5c0fbcf;
            3:k=32'he9b5dba5; 4:k=32'h3956c25b; 5:k=32'h59f111f1;
            6:k=32'h923f82a4; 7:k=32'hab1c5ed5; 8:k=32'hd807aa98;
            9:k=32'h12835b01; 10:k=32'h243185be; 11:k=32'h550c7dc3;
            12:k=32'h72be5d74; 13:k=32'h80deb1fe; 14:k=32'h9bdc06a7;
            15:k=32'hc19bf174; 16:k=32'he49b69c1; 17:k=32'hefbe4786;
            18:k=32'h0fc19dc6; 19:k=32'h240ca1cc; 20:k=32'h2de92c6f;
            21:k=32'h4a7484aa; 22:k=32'h5cb0a9dc; 23:k=32'h76f988da;
            24:k=32'h983e5152; 25:k=32'ha831c66d; 26:k=32'hb00327c8;
            27:k=32'hbf597fc7; 28:k=32'hc6e00bf3; 29:k=32'hd5a79147;
            30:k=32'h06ca6351; 31:k=32'h14292967; 32:k=32'h27b70a85;
            33:k=32'h2e1b2138; 34:k=32'h4d2c6dfc; 35:k=32'h53380d13;
            36:k=32'h650a7354; 37:k=32'h766a0abb; 38:k=32'h81c2c92e;
            39:k=32'h92722c85; 40:k=32'ha2bfe8a1; 41:k=32'ha81a664b;
            42:k=32'hc24b8b70; 43:k=32'hc76c51a3; 44:k=32'hd192e819;
            45:k=32'hd6990624; 46:k=32'hf40e3585; 47:k=32'h106aa070;
            48:k=32'h19a4c116; 49:k=32'h1e376c08; 50:k=32'h2748774c;
            51:k=32'h34b0bcb5; 52:k=32'h391c0cb3; 53:k=32'h4ed8aa4a;
            54:k=32'h5b9cca4f; 55:k=32'h682e6ff3; 56:k=32'h748f82ee;
            57:k=32'h78a5636f; 58:k=32'h84c87814; 59:k=32'h8cc70208;
            60:k=32'h90befffa; 61:k=32'ha4506ceb; 62:k=32'hbef9a3f7;
            63:k=32'hc67178f2; default:k=0;
        endcase
    endfunction

    wire [3:0] wi = round_q[3:0];
    wire [3:0] wi_m2 = round_q[3:0] - 4'd2;
    wire [3:0] wi_m7 = round_q[3:0] - 4'd7;
    wire [3:0] wi_m15 = round_q[3:0] - 4'd15;
    wire [3:0] wi_m16 = round_q[3:0];
    wire [31:0] a_next = t1_q + t2_q;
    wire [31:0] e_next = d_q + t1_q;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            busy_q <= 1'b0; phase_q <= PH_LAUNCH; round_q <= 0;
            done_o <= 1'b0; digest_o <= 0; sched_req_valid_o <= 1'b0;
        end else begin
            done_o <= 1'b0;
            if (sched_req_valid_o && sched_req_ready_i)
                sched_req_valid_o <= 1'b0;

            if (start_i && !busy_q) begin
                for (i = 0; i < 16; i = i + 1)
                    w_mem[i] <= block_i[511 - (i * 32) -: 32];
                h0_q <= h_i[255:224]; h1_q <= h_i[223:192];
                h2_q <= h_i[191:160]; h3_q <= h_i[159:128];
                h4_q <= h_i[127:96]; h5_q <= h_i[95:64];
                h6_q <= h_i[63:32]; h7_q <= h_i[31:0];
                a_q <= h_i[255:224]; b_q <= h_i[223:192];
                c_q <= h_i[191:160]; d_q <= h_i[159:128];
                e_q <= h_i[127:96]; f_q <= h_i[95:64];
                g_q <= h_i[63:32]; h_q <= h_i[31:0];
                round_q <= 0; phase_q <= PH_LAUNCH; busy_q <= 1'b1;
            end else if (busy_q) begin
                case (phase_q)
                    PH_LAUNCH: begin
                        t1_a_q <= h_q + big_sigma1(e_q);
                        t1_b_q <= ch(e_q, f_q, g_q) + k(round_q);
                        t2_q <= big_sigma0(a_q) + maj(a_q, b_q, c_q);
                        if (round_q < 16) begin
                            t1_c_q <= w_mem[wi];
                            phase_q <= PH_CALC;
                        end else begin
                            sched_sigma1_o <= small_sigma1(w_mem[wi_m2]);
                            sched_w_m7_o <= w_mem[wi_m7];
                            sched_sigma0_o <= small_sigma0(w_mem[wi_m15]);
                            sched_w_m16_o <= w_mem[wi_m16];
                            sched_engine_o <= 0; sched_round_o <= round_q;
                            sched_req_valid_o <= 1'b1;
                            phase_q <= PH_WAIT;
                        end
                    end
                    PH_WAIT: begin
                        if (sched_rsp_valid_i && sched_rsp_ready_o &&
                            sched_rsp_engine_i == 0 && sched_rsp_round_i == round_q) begin
                            w_new_q <= sched_w_new_i;
                            t1_c_q <= sched_w_new_i;
                            phase_q <= PH_CALC;
                        end
                    end
                    PH_CALC: begin
                        t1_q <= t1_a_q + t1_b_q + t1_c_q;
                        phase_q <= PH_UPDATE;
                    end
                    PH_UPDATE: begin
                        if (round_q >= 16)
                            w_mem[wi] <= w_new_q;
                        a_q <= a_next; b_q <= a_q; c_q <= b_q; d_q <= c_q;
                        e_q <= e_next; f_q <= e_q; g_q <= f_q; h_q <= g_q;
                        if (round_q == 63) begin
                            digest_o <= {h0_q + a_next, h1_q + a_q,
                                h2_q + b_q, h3_q + c_q, h4_q + e_next,
                                h5_q + e_q, h6_q + f_q, h7_q + g_q};
                            busy_q <= 1'b0; done_o <= 1'b1; phase_q <= PH_LAUNCH;
                        end else begin
                            round_q <= round_q + 1'b1;
                            phase_q <= PH_LAUNCH;
                        end
                    end
                    default: phase_q <= PH_LAUNCH;
                endcase
            end
        end
    end
endmodule
