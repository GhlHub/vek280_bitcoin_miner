`timescale 1ns/1ps

module irq_or4 (
    input  wire irq0_i,
    input  wire irq1_i,
    input  wire irq2_i,
    input  wire irq3_i,
    output wire irq_o
);
    assign irq_o = irq0_i | irq1_i | irq2_i | irq3_i;
endmodule
