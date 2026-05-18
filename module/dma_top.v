// =============================================================================
// Module  : dma_top
// Project : DMA Controller 4-Channel
// Brief   : Top-level tích hợp toàn bộ hệ thống DMA 4 kênh.
//           Port count tối ưu cho Zynq Z-7010 (100 PL IO).
//
// Thay đổi so với v1:
//   - fifo_din_ch0/1/2/3 (32 pins) → fifo_din[7:0] bus chung (8 pins)  [-24]
//   - Bỏ data_bus output (internal flyby, không cần expose ra ngoài)    [ -8]
//   - Bỏ fifo_empty_flag (tín hiệu nội bộ, không cần ở top-level)      [ -4]
//   Tổng còn: 92 pins < 100 PL IO của Z-7010 ✓
// =============================================================================

`timescale 1ns / 1ps

module dma_top (
    input  wire        clk,
    input  wire        rst_n,

    // ── Cấu hình CPU → Kênh DMA ──────────────────────────────────────────────
    input  wire [1:0]  cfg_ch_sel,
    input  wire        cfg_wr_en,
    input  wire [2:0]  cfg_addr,
    input  wire [7:0]  cfg_wr_data,
    output reg  [7:0]  cfg_rd_data,

    // ── IRQ Controller register access ───────────────────────────────────────
    input  wire [1:0]  irq_reg_addr,
    input  wire        irq_reg_wr_en,
    input  wire [7:0]  irq_reg_wr_data,
    output wire [7:0]  irq_reg_rd_data,

    // ── Ngoại vi: DREQ/DACK mỗi kênh ────────────────────────────────────────
    input  wire [3:0]  dreq,
    output wire [3:0]  dack,

    // ── Bus Master: HLD/HLDA ──────────────────────────────────────────────────
    output wire        hld,
    input  wire        hlda,

    // ── Shared Address + Strobe Bus (Flyby) ──────────────────────────────────
    output wire [15:0] addr_bus,   // Địa chỉ bus
    output wire        mem_wr,     // Memory write strobe
    output wire        io_rd,      // I/O read strobe

    // ── FIFO input – bus chung cho cả 4 kênh ─────────────────────────────────
    // fifo_wr_en[i]=1 → ghi fifo_din vào FIFO kênh i
    input  wire [3:0]  fifo_wr_en,
    input  wire [7:0]  fifo_din,   // Bus dữ liệu dùng chung (tiết kiệm 24 pins)

    // ── Status ───────────────────────────────────────────────────────────────
    output wire [3:0]  ch_busy,
    output wire        irq_out,
    output wire [3:0]  fifo_full
);

    // =========================================================================
    // 1. CONFIGURATION REGISTERS (per-channel)
    // =========================================================================
    reg [15:0] ch_src_addr   [0:3];
    reg [15:0] ch_dst_addr   [0:3];
    reg [15:0] ch_byte_count [0:3];
    reg [1:0]  ch_mode       [0:3];
    reg [7:0]  ch_crc_exp    [0:3];
    reg [3:0]  ch_start;              // Pulse start mỗi kênh

    integer k;
    always @(posedge clk) begin
        if (!rst_n) begin
            for (k = 0; k < 4; k = k + 1) begin
                ch_src_addr[k]   <= 16'd0;
                ch_dst_addr[k]   <= 16'd0;
                ch_byte_count[k] <= 16'd0;
                ch_mode[k]       <= 2'd0;
                ch_crc_exp[k]    <= 8'd0;
            end
            ch_start <= 4'd0;
        end else begin
            ch_start <= 4'd0;  // Pulse: xóa sau 1 chu kỳ
            if (cfg_wr_en) begin
                case (cfg_addr)
                    3'd0: ch_src_addr  [cfg_ch_sel][7:0]  <= cfg_wr_data;
                    3'd1: ch_src_addr  [cfg_ch_sel][15:8] <= cfg_wr_data;
                    3'd2: ch_dst_addr  [cfg_ch_sel][7:0]  <= cfg_wr_data;
                    3'd3: ch_dst_addr  [cfg_ch_sel][15:8] <= cfg_wr_data;
                    3'd4: ch_byte_count[cfg_ch_sel][7:0]  <= cfg_wr_data;
                    3'd5: ch_byte_count[cfg_ch_sel][15:8] <= cfg_wr_data;
                    3'd6: begin
                        ch_mode[cfg_ch_sel] <= cfg_wr_data[1:0];
                        if (cfg_wr_data[2])
                            ch_start[cfg_ch_sel] <= 1'b1;  // start pulse
                    end
                    3'd7: ch_crc_exp[cfg_ch_sel] <= cfg_wr_data;
                    default: ;
                endcase
            end
        end
    end

    // =========================================================================
    // 2. FIFO x4
    // =========================================================================
    wire [7:0] fifo_dout   [0:3];
    wire [3:0] fifo_rd_en_w;
    wire [3:0] fifo_almost_full;
    wire [3:0] fifo_empty_int;   // Tín hiệu nội bộ, không expose ra port

    genvar gi;
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : FIFO_INST
            dma_fifo #(.DEPTH(16), .WIDTH(8)) u_fifo (
                .clk         (clk),
                .rst_n       (rst_n),
                .wr_en       (fifo_wr_en[gi]),
                .din         (fifo_din),        // Bus chung cho cả 4 kênh
                .rd_en       (fifo_rd_en_w[gi]),
                .dout        (fifo_dout[gi]),
                .full        (fifo_full[gi]),
                .empty       (fifo_empty_int[gi]),
                .almost_full (fifo_almost_full[gi])
            );
        end
    endgenerate

    // =========================================================================
    // 3. ARBITER
    // =========================================================================
    wire [3:0] req_w;
    wire [3:0] grant_w;
    wire       grant_valid_w;

    dma_arbiter u_arbiter (
        .clk         (clk),
        .rst_n       (rst_n),
        .req         (req_w),
        .grant       (grant_w),
        .grant_valid (grant_valid_w)
    );

    // =========================================================================
    // 4. DMA CHANNEL x4 + CRC8 x4
    // =========================================================================
    wire [3:0]  ch_tc, ch_be;
    wire [3:0]  ch_hld;
    wire [15:0] ch_addr_bus [0:3];
    wire [7:0]  ch_data_bus [0:3];
    wire        ch_mem_wr   [0:3];
    wire        ch_io_rd    [0:3];

    wire        crc_init_w  [0:3];
    wire        crc_en_w    [0:3];
    wire [7:0]  crc_data_w  [0:3];
    wire        crc_check_w [0:3];
    wire        crc_ok_w    [0:3];
    wire        crc_error_w [0:3];

    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : CH_INST
            dma_channel #(.TIMEOUT_CNT(16)) u_ch (
                .clk          (clk),
                .rst_n        (rst_n),
                .start        (ch_start[gi]),
                .src_addr     (ch_src_addr[gi]),
                .dst_addr     (ch_dst_addr[gi]),
                .byte_count   (ch_byte_count[gi]),
                .mode         (ch_mode[gi]),
                .crc_expected (ch_crc_exp[gi]),
                .req          (req_w[gi]),
                .grant        (grant_w[gi]),
                .hld          (ch_hld[gi]),
                .hlda         (hlda),
                .dreq         (dreq[gi]),
                .dack         (dack[gi]),
                .fifo_dout    (fifo_dout[gi]),
                .fifo_empty   (fifo_empty_int[gi]),
                .fifo_rd_en   (fifo_rd_en_w[gi]),
                .addr_bus     (ch_addr_bus[gi]),
                .data_bus     (ch_data_bus[gi]),
                .mem_wr       (ch_mem_wr[gi]),
                .io_rd        (ch_io_rd[gi]),
                .eop          (),
                .crc_init     (crc_init_w[gi]),
                .crc_en       (crc_en_w[gi]),
                .crc_data     (crc_data_w[gi]),
                .crc_check    (crc_check_w[gi]),
                .busy         (ch_busy[gi]),
                .tc           (ch_tc[gi]),
                .be           (ch_be[gi])
            );

            crc8_inline u_crc (
                .clk       (clk),
                .rst_n     (rst_n),
                .init      (crc_init_w[gi]),
                .en        (crc_en_w[gi]),
                .data_in   (crc_data_w[gi]),
                .crc_out   (),
                .check_en  (crc_check_w[gi]),
                .expected  (ch_crc_exp[gi]),
                .crc_ok    (crc_ok_w[gi]),
                .crc_error (crc_error_w[gi])
            );
        end
    endgenerate

    // =========================================================================
    // 5. IRQ CONTROLLER
    // =========================================================================
    // Bus Error bao gồm cả crc_error
    wire [3:0] be_combined;
    assign be_combined = ch_be | {crc_error_w[3], crc_error_w[2],
                                   crc_error_w[1], crc_error_w[0]};

    irq_controller u_irq (
        .clk          (clk),
        .rst_n        (rst_n),
        .tc           (ch_tc),
        .be           (be_combined),
        .reg_addr     (irq_reg_addr),
        .reg_wr_en    (irq_reg_wr_en),
        .reg_wr_data  (irq_reg_wr_data),
        .reg_rd_data  (irq_reg_rd_data),
        .irq_out      (irq_out)
    );

    // =========================================================================
    // 6. BUS MUX – chọn đầu ra của kênh được grant
    // =========================================================================
    // HLD = OR của 4 kênh (khi bất kỳ kênh nào đang yêu cầu bus)
    assign hld = |ch_hld;

    // Bus output: MUX dựa trên grant_w (one-hot)
    // Chỉ 1 kênh được phép drive bus tại một thời điểm
    reg [15:0] mux_addr;
    reg [7:0]  mux_data;
    reg        mux_mem_wr;
    reg        mux_io_rd;

    always @(*) begin
        mux_addr   = 16'd0;
        mux_data   = 8'd0;
        mux_mem_wr = 1'b0;
        mux_io_rd  = 1'b0;
        case (grant_w)
            4'b0001: begin mux_addr = ch_addr_bus[0]; mux_data = ch_data_bus[0];
                           mux_mem_wr = ch_mem_wr[0]; mux_io_rd = ch_io_rd[0]; end
            4'b0010: begin mux_addr = ch_addr_bus[1]; mux_data = ch_data_bus[1];
                           mux_mem_wr = ch_mem_wr[1]; mux_io_rd = ch_io_rd[1]; end
            4'b0100: begin mux_addr = ch_addr_bus[2]; mux_data = ch_data_bus[2];
                           mux_mem_wr = ch_mem_wr[2]; mux_io_rd = ch_io_rd[2]; end
            4'b1000: begin mux_addr = ch_addr_bus[3]; mux_data = ch_data_bus[3];
                           mux_mem_wr = ch_mem_wr[3]; mux_io_rd = ch_io_rd[3]; end
            default: ;
        endcase
    end

    assign addr_bus = mux_addr;
    assign mem_wr   = mux_mem_wr;
    assign io_rd    = mux_io_rd;

endmodule
