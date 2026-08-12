`timescale 1ns/1ps

// One-outstanding-transaction AXI4-Lite bridge for the 125 MHz control domain
// and the 250 MHz miner domain. Request and response payloads are held stable
// while a toggle handshake crosses the clock boundary.
module axi_lite_cdc_bridge #(
    parameter int unsigned ADDR_WIDTH = 12
) (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 s_axi_aclk CLK",
       X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET s_axi_aresetn, FREQ_HZ 124998749" *)
    input wire s_axi_aclk,
    input wire s_axi_aresetn,
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 m_axi_aclk CLK",
       X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF M_AXI, ASSOCIATED_RESET m_axi_aresetn, FREQ_HZ 249997498" *)
    input wire m_axi_aclk,
    input wire m_axi_aresetn,

    input wire [ADDR_WIDTH-1:0] s_axi_awaddr,
    input wire s_axi_awvalid,
    output wire s_axi_awready,
    input wire [31:0] s_axi_wdata,
    input wire [3:0] s_axi_wstrb,
    input wire s_axi_wvalid,
    output wire s_axi_wready,
    output reg [1:0] s_axi_bresp,
    output reg s_axi_bvalid,
    input wire s_axi_bready,
    input wire [ADDR_WIDTH-1:0] s_axi_araddr,
    input wire s_axi_arvalid,
    output wire s_axi_arready,
    output reg [31:0] s_axi_rdata,
    output reg [1:0] s_axi_rresp,
    output reg s_axi_rvalid,
    input wire s_axi_rready,

    output reg [ADDR_WIDTH-1:0] m_axi_awaddr,
    output reg m_axi_awvalid,
    input wire m_axi_awready,
    output reg [31:0] m_axi_wdata,
    output reg [3:0] m_axi_wstrb,
    output reg m_axi_wvalid,
    input wire m_axi_wready,
    input wire [1:0] m_axi_bresp,
    input wire m_axi_bvalid,
    output reg m_axi_bready,
    output reg [ADDR_WIDTH-1:0] m_axi_araddr,
    output reg m_axi_arvalid,
    input wire m_axi_arready,
    input wire [31:0] m_axi_rdata,
    input wire [1:0] m_axi_rresp,
    input wire m_axi_rvalid,
    output reg m_axi_rready
);
    reg write_req_toggle_q;
    reg read_req_toggle_q;
    reg write_rsp_toggle_q;
    reg read_rsp_toggle_q;
    reg write_busy_q;
    reg read_busy_q;
    reg [ADDR_WIDTH-1:0] write_addr_q;
    reg [31:0] write_data_q;
    reg [3:0] write_strb_q;
    reg [ADDR_WIDTH-1:0] read_addr_q;
    reg [1:0] write_rsp_q;
    reg [31:0] read_rsp_data_q;
    reg [1:0] read_rsp_q;

    (* ASYNC_REG = "TRUE" *) reg write_req_sync1_q, write_req_sync2_q;
    (* ASYNC_REG = "TRUE" *) reg read_req_sync1_q, read_req_sync2_q;
    (* ASYNC_REG = "TRUE" *) reg write_rsp_sync1_q, write_rsp_sync2_q;
    (* ASYNC_REG = "TRUE" *) reg read_rsp_sync1_q, read_rsp_sync2_q;
    reg write_req_seen_q;
    reg read_req_seen_q;
    reg write_rsp_seen_q;
    reg read_rsp_seen_q;
    reg write_active_q;
    reg read_active_q;

    assign s_axi_awready = !write_busy_q && !read_busy_q && !s_axi_bvalid && !s_axi_rvalid && s_axi_wvalid;
    assign s_axi_wready = !write_busy_q && !read_busy_q && !s_axi_bvalid && !s_axi_rvalid && s_axi_awvalid;
    assign s_axi_arready = !write_busy_q && !read_busy_q && !s_axi_bvalid && !s_axi_rvalid;

    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            write_req_toggle_q <= 1'b0;
            read_req_toggle_q <= 1'b0;
            write_busy_q <= 1'b0;
            read_busy_q <= 1'b0;
            write_addr_q <= {ADDR_WIDTH{1'b0}};
            write_data_q <= 32'h0;
            write_strb_q <= 4'h0;
            read_addr_q <= {ADDR_WIDTH{1'b0}};
            write_rsp_sync1_q <= 1'b0;
            write_rsp_sync2_q <= 1'b0;
            read_rsp_sync1_q <= 1'b0;
            read_rsp_sync2_q <= 1'b0;
            write_rsp_seen_q <= 1'b0;
            read_rsp_seen_q <= 1'b0;
            s_axi_bresp <= 2'b00;
            s_axi_bvalid <= 1'b0;
            s_axi_rdata <= 32'h0;
            s_axi_rresp <= 2'b00;
            s_axi_rvalid <= 1'b0;
        end else begin
            write_rsp_sync1_q <= write_rsp_toggle_q;
            write_rsp_sync2_q <= write_rsp_sync1_q;
            read_rsp_sync1_q <= read_rsp_toggle_q;
            read_rsp_sync2_q <= read_rsp_sync1_q;

            if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 1'b0;
            if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 1'b0;

            if (s_axi_awvalid && s_axi_wvalid && s_axi_awready && s_axi_wready) begin
                write_addr_q <= s_axi_awaddr;
                write_data_q <= s_axi_wdata;
                write_strb_q <= s_axi_wstrb;
                write_req_toggle_q <= ~write_req_toggle_q;
                write_busy_q <= 1'b1;
            end
            if (s_axi_arvalid && s_axi_arready) begin
                read_addr_q <= s_axi_araddr;
                read_req_toggle_q <= ~read_req_toggle_q;
                read_busy_q <= 1'b1;
            end
            if (write_busy_q && (write_rsp_sync2_q != write_rsp_seen_q)) begin
                write_rsp_seen_q <= write_rsp_sync2_q;
                write_busy_q <= 1'b0;
                s_axi_bresp <= write_rsp_q;
                s_axi_bvalid <= 1'b1;
            end
            if (read_busy_q && (read_rsp_sync2_q != read_rsp_seen_q)) begin
                read_rsp_seen_q <= read_rsp_sync2_q;
                read_busy_q <= 1'b0;
                s_axi_rdata <= read_rsp_data_q;
                s_axi_rresp <= read_rsp_q;
                s_axi_rvalid <= 1'b1;
            end
        end
    end

    always @(posedge m_axi_aclk or negedge m_axi_aresetn) begin
        if (!m_axi_aresetn) begin
            write_req_sync1_q <= 1'b0;
            write_req_sync2_q <= 1'b0;
            read_req_sync1_q <= 1'b0;
            read_req_sync2_q <= 1'b0;
            write_req_seen_q <= 1'b0;
            read_req_seen_q <= 1'b0;
            write_rsp_toggle_q <= 1'b0;
            read_rsp_toggle_q <= 1'b0;
            write_rsp_q <= 2'b00;
            read_rsp_data_q <= 32'h0;
            read_rsp_q <= 2'b00;
            write_active_q <= 1'b0;
            read_active_q <= 1'b0;
            m_axi_awaddr <= {ADDR_WIDTH{1'b0}};
            m_axi_awvalid <= 1'b0;
            m_axi_wdata <= 32'h0;
            m_axi_wstrb <= 4'h0;
            m_axi_wvalid <= 1'b0;
            m_axi_bready <= 1'b0;
            m_axi_araddr <= {ADDR_WIDTH{1'b0}};
            m_axi_arvalid <= 1'b0;
            m_axi_rready <= 1'b0;
        end else begin
            write_req_sync1_q <= write_req_toggle_q;
            write_req_sync2_q <= write_req_sync1_q;
            read_req_sync1_q <= read_req_toggle_q;
            read_req_sync2_q <= read_req_sync1_q;

            if (!write_active_q && !read_active_q && (write_req_sync2_q != write_req_seen_q)) begin
                write_req_seen_q <= write_req_sync2_q;
                m_axi_awaddr <= write_addr_q;
                m_axi_wdata <= write_data_q;
                m_axi_wstrb <= write_strb_q;
                m_axi_awvalid <= 1'b1;
                m_axi_wvalid <= 1'b1;
                write_active_q <= 1'b1;
            end
            if (!write_active_q && !read_active_q && (read_req_sync2_q != read_req_seen_q)) begin
                read_req_seen_q <= read_req_sync2_q;
                m_axi_araddr <= read_addr_q;
                m_axi_arvalid <= 1'b1;
                read_active_q <= 1'b1;
            end
            if (m_axi_awvalid && m_axi_awready) m_axi_awvalid <= 1'b0;
            if (m_axi_wvalid && m_axi_wready) m_axi_wvalid <= 1'b0;
            m_axi_bready <= write_active_q && !m_axi_awvalid && !m_axi_wvalid;
            if (m_axi_bvalid && m_axi_bready) begin
                write_rsp_q <= m_axi_bresp;
                write_rsp_toggle_q <= ~write_rsp_toggle_q;
                write_active_q <= 1'b0;
                m_axi_bready <= 1'b0;
            end
            if (m_axi_arvalid && m_axi_arready) begin
                m_axi_arvalid <= 1'b0;
                m_axi_rready <= 1'b1;
            end
            if (m_axi_rvalid && m_axi_rready) begin
                read_rsp_data_q <= m_axi_rdata;
                read_rsp_q <= m_axi_rresp;
                read_rsp_toggle_q <= ~read_rsp_toggle_q;
                read_active_q <= 1'b0;
                m_axi_rready <= 1'b0;
            end
        end
    end
endmodule
