`timescale 1ns/1ps

module bitcoin_miner_axi #(
    parameter int unsigned NUM_ENGINES = 128,
    parameter int unsigned CLUSTER_SIZE = 16,
    parameter int unsigned CLUSTER_FIFO_DEPTH = 2,
    parameter int unsigned AXI_ADDR_WIDTH = 12
) (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 s_axi_aclk CLK",
       X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET s_axi_aresetn, FREQ_HZ 249997498" *)
    input  wire                       s_axi_aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 s_axi_aresetn RST",
       X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire                       s_axi_aresetn,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR",
       X_INTERFACE_PARAMETER = "PROTOCOL AXI4LITE, ADDR_WIDTH 12, DATA_WIDTH 32, HAS_BURST 0, HAS_LOCK 0, HAS_PROT 0, HAS_CACHE 0, HAS_QOS 0, HAS_REGION 0, HAS_WSTRB 1, HAS_BRESP 1, HAS_RRESP 1, SUPPORTS_NARROW_BURST 0, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1" *)
    input  wire [AXI_ADDR_WIDTH-1:0]  s_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
    input  wire                       s_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
    output reg                        s_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
    input  wire [31:0]                s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
    input  wire [3:0]                 s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
    input  wire                       s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
    output reg                        s_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
    output reg  [1:0]                 s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
    output reg                        s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
    input  wire                       s_axi_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
    input  wire [AXI_ADDR_WIDTH-1:0]  s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
    input  wire                       s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
    output reg                        s_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
    output reg  [31:0]                s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
    output reg  [1:0]                 s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
    output reg                        s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
    input  wire                       s_axi_rready,
    (* X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 irq_o INTERRUPT",
       X_INTERFACE_PARAMETER = "SENSITIVITY LEVEL_HIGH" *)
    output wire                       irq_o
);
    localparam [11:0] ADDR_CONTROL       = 12'h000;
    localparam [11:0] ADDR_STATUS        = 12'h004;
    localparam [11:0] ADDR_NUM_ENGINES   = 12'h008;
    localparam [11:0] ADDR_MIDSTATE_BASE = 12'h020;
    localparam [11:0] ADDR_TAIL_BASE     = 12'h040;
    localparam [11:0] ADDR_TARGET_BASE   = 12'h060;
    localparam [11:0] ADDR_NONCE_START   = 12'h080;
    localparam [11:0] ADDR_NONCE_COUNT   = 12'h084;
    localparam [11:0] ADDR_RESULT_NONCE  = 12'h090;
    localparam [11:0] ADDR_RESULT_ENGINE = 12'h094;
    localparam [11:0] ADDR_RESULT_STATUS = 12'h098;
    localparam [11:0] ADDR_RESULT_HASH   = 12'h0a0;
    localparam int unsigned NUM_CLUSTERS = (NUM_ENGINES + CLUSTER_SIZE - 1) / CLUSTER_SIZE;

    reg [255:0] midstate_q;
    reg [127:0] header_tail_q;
    reg [255:0] target_q;
    reg [31:0]  nonce_start_q;
    reg [31:0]  nonce_count_q;
    reg         running_q;
    reg         nonce_done_q;
    reg         overflow_q;
    reg         result_valid_q;
    reg [31:0]  result_nonce_q;
    reg [31:0]  result_engine_q;
    reg [255:0] result_hash_q;

    reg start_pulse_q;
    reg stop_pulse_q;
    reg [NUM_ENGINES-1:0]    engine_start_q;
    reg [NUM_ENGINES*32-1:0] engine_nonce_start_q;
    reg [NUM_ENGINES*32-1:0] engine_nonce_count_q;

    wire [NUM_ENGINES-1:0] engine_busy;
    wire [NUM_ENGINES-1:0] engine_done;
    wire [NUM_ENGINES-1:0] engine_result_valid;
    wire [NUM_ENGINES*32-1:0] engine_result_nonce;
    wire [NUM_ENGINES*256-1:0] engine_result_hash;
    wire [NUM_CLUSTERS-1:0] cluster_valid;
    wire [NUM_CLUSTERS-1:0] cluster_overflow;
    wire [NUM_CLUSTERS-1:0] cluster_pop;
    wire [NUM_CLUSTERS*32-1:0] cluster_engine_id;
    wire [NUM_CLUSTERS*32-1:0] cluster_nonce;
    wire [NUM_CLUSTERS*256-1:0] cluster_hash;

    integer i;
    integer cluster_hit_idx_next;
    reg write_fire;
    reg read_fire;
    reg [11:0] wr_addr;
    reg [11:0] rd_addr;
    reg [NUM_CLUSTERS-1:0] cluster_pop_q;

    assign irq_o = result_valid_q | overflow_q | nonce_done_q;
    assign cluster_pop = cluster_pop_q;

    function automatic [31:0] apply_wstrb(
        input [31:0] old_data,
        input [31:0] new_data,
        input [3:0]  strobe
    );
        integer byte_idx;
        begin
            apply_wstrb = old_data;
            for (byte_idx = 0; byte_idx < 4; byte_idx = byte_idx + 1) begin
                if (strobe[byte_idx]) begin
                    apply_wstrb[byte_idx*8 +: 8] = new_data[byte_idx*8 +: 8];
                end
            end
        end
    endfunction

    function automatic [31:0] read_reg(input [11:0] addr);
        integer idx;
        begin
            read_reg = 32'h00000000;
            if ((addr >= ADDR_MIDSTATE_BASE) && (addr < ADDR_MIDSTATE_BASE + 12'h020)) begin
                idx = ({20'h0, addr} - {20'h0, ADDR_MIDSTATE_BASE}) >> 2;
                read_reg = midstate_q[255 - (idx * 32) -: 32];
            end else if ((addr >= ADDR_TAIL_BASE) && (addr < ADDR_TAIL_BASE + 12'h010)) begin
                idx = ({20'h0, addr} - {20'h0, ADDR_TAIL_BASE}) >> 2;
                read_reg = header_tail_q[127 - (idx * 32) -: 32];
            end else if ((addr >= ADDR_TARGET_BASE) && (addr < ADDR_TARGET_BASE + 12'h020)) begin
                idx = ({20'h0, addr} - {20'h0, ADDR_TARGET_BASE}) >> 2;
                read_reg = target_q[255 - (idx * 32) -: 32];
            end else if ((addr >= ADDR_RESULT_HASH) && (addr < ADDR_RESULT_HASH + 12'h020)) begin
                idx = ({20'h0, addr} - {20'h0, ADDR_RESULT_HASH}) >> 2;
                read_reg = result_hash_q[255 - (idx * 32) -: 32];
            end else begin
                case (addr)
                    ADDR_CONTROL:       read_reg = 32'h00000000;
                    ADDR_STATUS:        read_reg = {28'h0, overflow_q, nonce_done_q, result_valid_q, running_q};
                    ADDR_NUM_ENGINES:   read_reg = NUM_ENGINES[31:0];
                    ADDR_NONCE_START:   read_reg = nonce_start_q;
                    ADDR_NONCE_COUNT:   read_reg = nonce_count_q;
                    ADDR_RESULT_NONCE:  read_reg = result_nonce_q;
                    ADDR_RESULT_ENGINE: read_reg = result_engine_q;
                    ADDR_RESULT_STATUS: read_reg = {30'h0, overflow_q, result_valid_q};
                    default:            read_reg = 32'h00000000;
                endcase
            end
        end
    endfunction

    function automatic [31:0] engine_work_count(
        input [31:0] count,
        input [31:0] engine_index
    );
        begin
            engine_work_count = (count > engine_index) ?
                                (((count - 32'd1 - engine_index) / NUM_ENGINES) + 32'd1) :
                                32'd0;
        end
    endfunction

    genvar gen_idx;
    generate
        for (gen_idx = 0; gen_idx < NUM_ENGINES; gen_idx = gen_idx + 1) begin : g_engines
            bitcoin_hash_engine #(
                .NONCE_STRIDE(NUM_ENGINES)
            ) u_engine (
                .clk_i(s_axi_aclk),
                .rst_ni(s_axi_aresetn),
                .start_i(engine_start_q[gen_idx]),
                .stop_i(stop_pulse_q),
                .midstate_i(midstate_q),
                .header_tail_i(header_tail_q),
                .target_i(target_q),
                .nonce_start_i(engine_nonce_start_q[gen_idx*32 +: 32]),
                .nonce_count_i(engine_nonce_count_q[gen_idx*32 +: 32]),
                .busy_o(engine_busy[gen_idx]),
                .done_o(engine_done[gen_idx]),
                .result_valid_o(engine_result_valid[gen_idx]),
                .result_nonce_o(engine_result_nonce[gen_idx*32 +: 32]),
                .result_hash_o(engine_result_hash[gen_idx*256 +: 256])
            );
        end
    endgenerate

    genvar cluster_idx;
    genvar local_idx;
    generate
        for (cluster_idx = 0; cluster_idx < NUM_CLUSTERS; cluster_idx = cluster_idx + 1) begin : g_clusters
            wire [CLUSTER_SIZE-1:0] local_valid;
            wire [CLUSTER_SIZE*32-1:0] local_nonce;
            wire [CLUSTER_SIZE*256-1:0] local_hash;

            for (local_idx = 0; local_idx < CLUSTER_SIZE; local_idx = local_idx + 1) begin : g_cluster_inputs
                localparam int unsigned ENGINE_INDEX = (cluster_idx * CLUSTER_SIZE) + local_idx;
                if (ENGINE_INDEX < NUM_ENGINES) begin : g_active_engine
                    assign local_valid[local_idx] = engine_result_valid[ENGINE_INDEX];
                    assign local_nonce[local_idx*32 +: 32] = engine_result_nonce[ENGINE_INDEX*32 +: 32];
                    assign local_hash[local_idx*256 +: 256] = engine_result_hash[ENGINE_INDEX*256 +: 256];
                end else begin : g_inactive_engine
                    assign local_valid[local_idx] = 1'b0;
                    assign local_nonce[local_idx*32 +: 32] = 32'h0;
                    assign local_hash[local_idx*256 +: 256] = 256'h0;
                end
            end

            bitcoin_result_cluster_fifo #(
                .CLUSTER_INDEX(cluster_idx),
                .CLUSTER_SIZE(CLUSTER_SIZE),
                .FIFO_DEPTH(CLUSTER_FIFO_DEPTH)
            ) u_result_fifo (
                .clk_i(s_axi_aclk),
                .rst_ni(s_axi_aresetn),
                .clear_i(stop_pulse_q || start_pulse_q || (write_fire && (wr_addr == ADDR_CONTROL) && s_axi_wdata[2])),
                .pop_i(cluster_pop[cluster_idx]),
                .engine_valid_i(local_valid),
                .engine_nonce_i(local_nonce),
                .engine_hash_i(local_hash),
                .valid_o(cluster_valid[cluster_idx]),
                .engine_id_o(cluster_engine_id[cluster_idx*32 +: 32]),
                .nonce_o(cluster_nonce[cluster_idx*32 +: 32]),
                .hash_o(cluster_hash[cluster_idx*256 +: 256]),
                .overflow_o(cluster_overflow[cluster_idx])
            );
        end
    endgenerate

    always @(*) begin
        write_fire = s_axi_awvalid && s_axi_wvalid && !s_axi_bvalid;
        read_fire = s_axi_arvalid && !s_axi_rvalid;
        wr_addr = {s_axi_awaddr[11:2], s_axi_awaddr[1:0] & 2'b00};
        rd_addr = {s_axi_araddr[11:2], s_axi_araddr[1:0] & 2'b00};
        cluster_hit_idx_next = -1;
        for (i = 0; i < NUM_CLUSTERS; i = i + 1) begin
            if ((cluster_hit_idx_next < 0) && cluster_valid[i]) begin
                cluster_hit_idx_next = i;
            end
        end
    end

    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            s_axi_awready <= 1'b0;
            s_axi_wready <= 1'b0;
            s_axi_bresp <= 2'b00;
            s_axi_bvalid <= 1'b0;
            s_axi_arready <= 1'b0;
            s_axi_rdata <= 32'h0;
            s_axi_rresp <= 2'b00;
            s_axi_rvalid <= 1'b0;
            midstate_q <= 256'h0;
            header_tail_q <= 128'h0;
            target_q <= 256'hffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
            nonce_start_q <= 32'h0;
            nonce_count_q <= 32'h0;
            running_q <= 1'b0;
            nonce_done_q <= 1'b0;
            overflow_q <= 1'b0;
            result_valid_q <= 1'b0;
            result_nonce_q <= 32'h0;
            result_engine_q <= 32'h0;
            result_hash_q <= 256'h0;
            start_pulse_q <= 1'b0;
            stop_pulse_q <= 1'b0;
            engine_start_q <= {NUM_ENGINES{1'b0}};
            engine_nonce_start_q <= {NUM_ENGINES*32{1'b0}};
            engine_nonce_count_q <= {NUM_ENGINES*32{1'b0}};
            cluster_pop_q <= {NUM_CLUSTERS{1'b0}};
        end else begin
            s_axi_awready <= write_fire;
            s_axi_wready <= write_fire;
            s_axi_arready <= read_fire;
            start_pulse_q <= 1'b0;
            stop_pulse_q <= 1'b0;
            engine_start_q <= {NUM_ENGINES{1'b0}};
            cluster_pop_q <= {NUM_CLUSTERS{1'b0}};

            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end

            if (write_fire) begin
                s_axi_bresp <= 2'b00;
                s_axi_bvalid <= 1'b1;

                if ((wr_addr >= ADDR_MIDSTATE_BASE) && (wr_addr < ADDR_MIDSTATE_BASE + 12'h020)) begin
                    i = ({20'h0, wr_addr} - {20'h0, ADDR_MIDSTATE_BASE}) >> 2;
                    midstate_q[255 - (i * 32) -: 32] <= apply_wstrb(midstate_q[255 - (i * 32) -: 32], s_axi_wdata, s_axi_wstrb);
                end else if ((wr_addr >= ADDR_TAIL_BASE) && (wr_addr < ADDR_TAIL_BASE + 12'h010)) begin
                    i = ({20'h0, wr_addr} - {20'h0, ADDR_TAIL_BASE}) >> 2;
                    header_tail_q[127 - (i * 32) -: 32] <= apply_wstrb(header_tail_q[127 - (i * 32) -: 32], s_axi_wdata, s_axi_wstrb);
                end else if ((wr_addr >= ADDR_TARGET_BASE) && (wr_addr < ADDR_TARGET_BASE + 12'h020)) begin
                    i = ({20'h0, wr_addr} - {20'h0, ADDR_TARGET_BASE}) >> 2;
                    target_q[255 - (i * 32) -: 32] <= apply_wstrb(target_q[255 - (i * 32) -: 32], s_axi_wdata, s_axi_wstrb);
                end else begin
                    case (wr_addr)
                        ADDR_CONTROL: begin
                            if (s_axi_wdata[0]) begin
                                start_pulse_q <= 1'b1;
                                running_q <= 1'b1;
                                nonce_done_q <= 1'b0;
                                overflow_q <= 1'b0;
                                result_valid_q <= 1'b0;
                                for (i = 0; i < NUM_ENGINES; i = i + 1) begin
                                    engine_nonce_start_q[i*32 +: 32] <= nonce_start_q + i[31:0];
                                    engine_nonce_count_q[i*32 +: 32] <= engine_work_count(nonce_count_q, i[31:0]);
                                    engine_start_q[i] <= (engine_work_count(nonce_count_q, i[31:0]) != 32'd0);
                                end
                            end
                            if (s_axi_wdata[1]) begin
                                stop_pulse_q <= 1'b1;
                                running_q <= 1'b0;
                                nonce_done_q <= 1'b1;
                            end
                            if (s_axi_wdata[2]) begin
                                result_valid_q <= 1'b0;
                                overflow_q <= 1'b0;
                                nonce_done_q <= 1'b0;
                            end
                        end
                        ADDR_NONCE_START: begin
                            nonce_start_q <= apply_wstrb(nonce_start_q, s_axi_wdata, s_axi_wstrb);
                        end
                        ADDR_NONCE_COUNT: begin
                            nonce_count_q <= apply_wstrb(nonce_count_q, s_axi_wdata, s_axi_wstrb);
                        end
                        ADDR_RESULT_STATUS: begin
                            if (s_axi_wdata[0]) begin
                                result_valid_q <= 1'b0;
                            end
                            if (s_axi_wdata[1]) begin
                                overflow_q <= 1'b0;
                            end
                        end
                        default: begin
                        end
                    endcase
                end
            end

            if (read_fire) begin
                s_axi_rdata <= read_reg(rd_addr);
                s_axi_rresp <= 2'b00;
                s_axi_rvalid <= 1'b1;
            end

            if (|cluster_overflow) begin
                overflow_q <= 1'b1;
            end

            if (!result_valid_q && (cluster_hit_idx_next >= 0)) begin
                result_valid_q <= 1'b1;
                result_engine_q <= cluster_engine_id[cluster_hit_idx_next*32 +: 32];
                result_nonce_q <= cluster_nonce[cluster_hit_idx_next*32 +: 32];
                result_hash_q <= cluster_hash[cluster_hit_idx_next*256 +: 256];
                cluster_pop_q[cluster_hit_idx_next] <= 1'b1;
            end

            if (running_q && ((engine_busy == {NUM_ENGINES{1'b0}}) || (engine_done == {NUM_ENGINES{1'b1}})) && !start_pulse_q) begin
                running_q <= 1'b0;
                nonce_done_q <= 1'b1;
            end
        end
    end
endmodule
