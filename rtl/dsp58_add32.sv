`timescale 1ns/1ps

// Explicit Versal DSP58 32-bit modular adder.  The X input is formed from the
// concatenated A:B path, placing b_i in P[31:0]; a_i is presented on C.
// All DSP pipeline registers are disabled so this replaces one combinational
// carry-chain adder without changing the SHA core's five-phase schedule.
module dsp58_add32 (
    input  wire [31:0] a_i,
    input  wire [31:0] b_i,
    output wire [31:0] sum_o
);
`ifdef SYNTHESIS
    wire [57:0] p;
    DSP58 #(
        .AREG(0), .BREG(0), .CREG(0), .DREG(0), .ADREG(0), .MREG(0), .PREG(0),
        .ACASCREG(0), .BCASCREG(0), .ALUMODEREG(0), .CARRYINREG(0),
        .CARRYINSELREG(0), .INMODEREG(0), .OPMODEREG(0),
        .USE_MULT("NONE"), .USE_SIMD("ONE58")
    ) u_dsp58 (
        .A({26'b0, b_i[31:24]}), .ACIN(34'b0), .B(b_i[23:0]), .BCIN(24'b0),
        .C({26'b0, a_i}), .D(27'b0), .PCIN(58'b0),
        .ALUMODE(4'b0000), .OPMODE(9'b000110011), .INMODE(5'b0),
        .CARRYIN(1'b0), .CARRYINSEL(3'b000), .CARRYCASCIN(1'b0),
        .CLK(1'b0), .ASYNC_RST(1'b0), .MULTSIGNIN(1'b0), .NEGATE(3'b0),
        .CEA1(1'b0), .CEA2(1'b0), .CEAD(1'b0), .CEALUMODE(1'b0),
        .CEB1(1'b0), .CEB2(1'b0), .CEC(1'b0), .CECARRYIN(1'b0),
        .CECTRL(1'b0), .CED(1'b0), .CEINMODE(1'b0), .CEM(1'b0), .CEP(1'b0),
        .RSTA(1'b0), .RSTALLCARRYIN(1'b0), .RSTALUMODE(1'b0), .RSTB(1'b0),
        .RSTC(1'b0), .RSTCTRL(1'b0), .RSTD(1'b0), .RSTINMODE(1'b0),
        .RSTM(1'b0), .RSTP(1'b0),
        .ACOUT(), .BCOUT(), .CARRYCASCOUT(), .CARRYOUT(), .MULTSIGNOUT(),
        .OVERFLOW(), .P(p), .PATTERNBDETECT(), .PATTERNDETECT(), .PCOUT(),
        .UNDERFLOW(), .XOROUT()
    );
    assign sum_o = p[31:0];
`else
    // Functional simulators do not load the Vivado UNISIM library.
    assign sum_o = a_i + b_i;
`endif
endmodule
