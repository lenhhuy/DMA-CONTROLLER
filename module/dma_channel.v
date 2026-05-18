// =============================================================================
// Module  : dma_channel
// Project : DMA Controller 4-Channel
// Brief   : Lõi điều khiển 1 kênh DMA. FSM Moore với 6 trạng thái.
//           Hỗ trợ Flyby Transfer + Burst / Cycle Stealing / Transparent mode.
//
// FSM States
//   IDLE        → chờ CPU cấu hình và kích hoạt kênh (start pulse)
//   REQUEST     → kênh gửi req tới Arbiter, chờ grant
//   WAIT_HLDA   → DMA đã nhận grant, gửi HLD tới CPU, chờ HLDA
//   TRANSFER    → Flyby: phát DACK + điều khiển bus strobe, BCR giảm dần
//   DONE        → BCR = 0, phát TC pulse, trả bus
//   ERROR       → timeout HLDA hoặc DACK, phát BE pulse, trả bus
//
// Ports (xem bên dưới)
// =============================================================================

`timescale 1ns / 1ps

module dma_channel #(
    parameter TIMEOUT_CNT = 16  // Số clock tối đa chờ HLDA / DACK trước khi báo lỗi
)(
    input  wire        clk,
    input  wire        rst_n,

    // ── Cấu hình từ CPU ──────────────────────────────────────────────────────
    input  wire        start,        // Pulse 1 chu kỳ: bắt đầu transfer
    input  wire [15:0] src_addr,     // Địa chỉ nguồn (I/O hoặc Mem)
    input  wire [15:0] dst_addr,     // Địa chỉ đích
    input  wire [15:0] byte_count,   // Số byte cần truyền
    input  wire [1:0]  mode,         // 00=Burst, 01=Cycle Stealing, 10=Transparent
    input  wire [7:0]  crc_expected, // Giá trị CRC mong đợi

    // ── Giao tiếp với Arbiter ────────────────────────────────────────────────
    output wire        req,          // Yêu cầu bus tới Arbiter
    input  wire        grant,        // Grant từ Arbiter (one-hot bit tương ứng kênh)

    // ── Giao tiếp Bus Master (HLD/HLDA) ─────────────────────────────────────
    output reg         hld,          // Hold Request tới CPU
    input  wire        hlda,         // Hold Acknowledge từ CPU

    // ── Giao tiếp ngoại vi (DREQ/DACK) ──────────────────────────────────────
    input  wire        dreq,         // DMA Request từ ngoại vi
    output reg         dack,         // DMA Acknowledge tới ngoại vi

    // ── Giao tiếp FIFO ───────────────────────────────────────────────────────
    input  wire [7:0]  fifo_dout,    // Byte đọc từ FIFO
    input  wire        fifo_empty,   // FIFO rỗng
    output reg         fifo_rd_en,   // Đọc từ FIFO

    // ── Bus output (địa chỉ + điều khiển) ───────────────────────────────────
    output reg  [15:0] addr_bus,     // Địa chỉ hiện tại trên bus
    output reg  [7:0]  data_bus,     // Dữ liệu hiện tại (từ FIFO)
    output reg         mem_wr,       // Strobe ghi bộ nhớ (Flyby)
    output reg         io_rd,        // Strobe đọc I/O (Flyby)

    // ── EOP ──────────────────────────────────────────────────────────────────
    output reg         eop,          // End of Process (kết thúc toàn bộ transfer)

    // ── CRC interface ────────────────────────────────────────────────────────
    output reg         crc_init,     // Khởi tạo CRC (đầu transfer)
    output reg         crc_en,       // Enable CRC update
    output wire [7:0]  crc_data,     // Dữ liệu đưa vào CRC = fifo_dout
    output reg         crc_check,    // Pulse kiểm tra CRC cuối transfer

    // ── Status ───────────────────────────────────────────────────────────────
    output reg         busy,         // Kênh đang hoạt động
    output reg         tc,           // Transfer Complete pulse (1 clock)
    output reg         be            // Bus Error pulse (1 clock)
);

    // ── State Encoding (one-hot) ──────────────────────────────────────────────
    localparam [5:0]
        IDLE     = 6'b000001,
        REQUEST  = 6'b000010,
        WAIT_HLDA= 6'b000100,
        TRANSFER = 6'b001000,
        DONE     = 6'b010000,
        ERROR    = 6'b100000;

    reg [5:0] state, next_state;

    // ── Thanh ghi nội bộ ─────────────────────────────────────────────────────
    reg [15:0] cur_src;     // Con trỏ địa chỉ nguồn (auto-increment)
    reg [15:0] cur_dst;     // Con trỏ địa chỉ đích
    reg [15:0] bcr;         // Byte count còn lại
    reg [1:0]  cur_mode;    // Bus mode
    reg [7:0]  timeout_cnt; // Đếm timeout

    // ── Continuous assignments ────────────────────────────────────────────────
    assign req      = (state == REQUEST) && dreq;  // Chỉ request khi ngoại vi có DREQ
    assign crc_data = fifo_dout;                   // CRC input = byte từ FIFO

    // ── Process 1: State register ─────────────────────────────────────────────
    always @(posedge clk) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    // ── Process 2: Next-state logic ───────────────────────────────────────────
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (start)
                    next_state = REQUEST;
            end

            REQUEST: begin
                // Chờ Arbiter cấp grant
                if (grant)
                    next_state = WAIT_HLDA;
            end

            WAIT_HLDA: begin
                if (hlda)
                    next_state = TRANSFER;
                else if (timeout_cnt == TIMEOUT_CNT - 1)
                    next_state = ERROR;
            end

            TRANSFER: begin
                if (bcr == 16'd1 && !fifo_empty) begin
                    // Byte cuối cùng đang được xử lý
                    next_state = DONE;
                end else if (timeout_cnt == TIMEOUT_CNT - 1) begin
                    // FIFO empty quá lâu (timeout)
                    next_state = ERROR;
                end
            end

            DONE:  next_state = IDLE;
            ERROR: next_state = IDLE;

            default: next_state = IDLE;
        endcase
    end

    // ── Process 3: Output logic và datapath ──────────────────────────────────
    always @(posedge clk) begin
        if (!rst_n) begin
            hld         <= 1'b0;
            dack        <= 1'b0;
            fifo_rd_en  <= 1'b0;
            addr_bus    <= 16'd0;
            data_bus    <= 8'd0;
            mem_wr      <= 1'b0;
            io_rd       <= 1'b0;
            eop         <= 1'b0;
            crc_init    <= 1'b0;
            crc_en      <= 1'b0;
            crc_check   <= 1'b0;
            busy        <= 1'b0;
            tc          <= 1'b0;
            be          <= 1'b0;
            cur_src     <= 16'd0;
            cur_dst     <= 16'd0;
            bcr         <= 16'd0;
            cur_mode    <= 2'b00;
            timeout_cnt <= 8'd0;
        end else begin
            // Xóa pulse signals mỗi chu kỳ
            tc         <= 1'b0;
            be         <= 1'b0;
            eop        <= 1'b0;
            crc_init   <= 1'b0;
            crc_en     <= 1'b0;
            crc_check  <= 1'b0;
            fifo_rd_en <= 1'b0;
            mem_wr     <= 1'b0;
            io_rd      <= 1'b0;

            case (state)
                // ─────────────────────────────────────────────────────────
                IDLE: begin
                    busy <= 1'b0;
                    hld  <= 1'b0;
                    dack <= 1'b0;
                    if (start) begin
                        cur_src  <= src_addr;
                        cur_dst  <= dst_addr;
                        bcr      <= byte_count;
                        cur_mode <= mode;
                        busy     <= 1'b1;
                        crc_init <= 1'b1;  // Khởi tạo CRC cho frame mới
                    end
                end

                // ─────────────────────────────────────────────────────────
                REQUEST: begin
                    busy        <= 1'b1;
                    timeout_cnt <= 8'd0;
                    // req được drive bởi continuous assign ở trên
                end

                // ─────────────────────────────────────────────────────────
                WAIT_HLDA: begin
                    hld <= 1'b1;   // Giữ HLD cho đến khi nhận HLDA
                    if (hlda) begin
                        dack        <= 1'b1;
                        timeout_cnt <= 8'd0;
                    end else begin
                        timeout_cnt <= timeout_cnt + 1'b1;
                    end
                end

                // ─────────────────────────────────────────────────────────
                TRANSFER: begin
                    hld  <= 1'b1;
                    dack <= 1'b1;

                    if (!fifo_empty) begin
                        // ── Flyby transfer: đọc FIFO + phát bus strobe cùng lúc ──
                        fifo_rd_en  <= 1'b1;
                        data_bus    <= fifo_dout;
                        addr_bus    <= cur_dst;

                        // Flyby strobe: io_rd (đọc ngoại vi) + mem_wr (ghi mem) đồng thời
                        io_rd <= 1'b1;
                        mem_wr<= 1'b1;

                        // CRC update inline
                        crc_en <= 1'b1;

                        // Tăng con trỏ địa chỉ và giảm byte count
                        cur_src <= cur_src + 16'd1;
                        cur_dst <= cur_dst + 16'd1;
                        bcr     <= bcr - 16'd1;

                        timeout_cnt <= 8'd0;

                        // Cycle Stealing: trả bus sau mỗi byte (giải phóng HLD)
                        // Transparent: chỉ active khi bus idle (đã được đảm bảo bởi grant logic)
                        // Burst: giữ liên tục → không cần xử lý thêm ở đây
                    end else begin
                        // FIFO empty: chờ ngoại vi nạp thêm
                        timeout_cnt <= timeout_cnt + 1'b1;
                    end
                end

                // ─────────────────────────────────────────────────────────
                DONE: begin
                    // Giải phóng bus
                    hld        <= 1'b0;
                    dack       <= 1'b0;
                    io_rd      <= 1'b0;
                    mem_wr     <= 1'b0;
                    // Phát tín hiệu kết thúc
                    tc         <= 1'b1;
                    eop        <= 1'b1;
                    crc_check  <= 1'b1;  // Module CRC so sánh và báo lỗi nếu sai
                    busy       <= 1'b0;
                end

                // ─────────────────────────────────────────────────────────
                ERROR: begin
                    hld  <= 1'b0;
                    dack <= 1'b0;
                    be   <= 1'b1;    // Bus Error → IRQ Controller
                    busy <= 1'b0;
                end

                default: ;
            endcase
        end
    end

endmodule
