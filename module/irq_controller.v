// =============================================================================
// Module  : irq_controller
// Project : DMA Controller 4-Channel
// Brief   : Tập trung xử lý ngắt từ 4 kênh DMA.
//           Hai nguồn ngắt mỗi kênh: Transfer Complete (TC) & Bus Error (BE).
//           Tổng cộng 8 bit nguồn ngắt (bit[7:4]=BE, bit[3:0]=TC).
//
// Registers (CPU truy cập qua reg_addr + reg_wr_data / reg_rd_data)
//   Addr 0x0 – IMR  (Interrupt Mask Register)    : 1=masked (chặn ngắt)
//   Addr 0x1 – IPR  (Interrupt Pending Register)  : 1=có sự kiện, read-only
//   Addr 0x2 – ICR  (Interrupt Clear Register)    : ghi 1 để xóa bit trong IPR
//
// Output
//   irq_out  – OR của (IPR AND NOT IMR), kết nối tới CPU INT line
// =============================================================================

`timescale 1ns / 1ps

module irq_controller (
    input  wire       clk,
    input  wire       rst_n,

    // Nguồn ngắt từ 4 kênh DMA
    input  wire [3:0] tc,           // Transfer Complete: tc[i] = kênh i hoàn tất
    input  wire [3:0] be,           // Bus Error:         be[i] = kênh i lỗi bus

    // Giao diện CPU (register access)
    input  wire [1:0] reg_addr,     // 0=IMR, 1=IPR, 2=ICR
    input  wire       reg_wr_en,    // CPU ghi vào register
    input  wire [7:0] reg_wr_data,  // Dữ liệu CPU ghi
    output reg  [7:0] reg_rd_data,  // Dữ liệu CPU đọc về

    // Output ngắt tổng
    output wire       irq_out       // Kết nối tới CPU INT pin
);

    // ── Registers nội bộ ────────────────────────────────────────────────────
    // Bit mapping: [7:4] = BE kênh 3,2,1,0 | [3:0] = TC kênh 3,2,1,0
    // Cụ thể: bit7=BE3, bit6=BE2, bit5=BE1, bit4=BE0, bit3=TC3, bit2=TC2, bit1=TC1, bit0=TC0

    reg [7:0] imr;  // Interrupt Mask Register
    reg [7:0] ipr;  // Interrupt Pending Register

    // Vector nguồn ngắt tức thời
    wire [7:0] irq_src = {be[3], be[2], be[1], be[0],
                           tc[3], tc[2], tc[1], tc[0]};

    // ── IPR: set khi có nguồn ngắt, clear khi CPU ghi ICR ───────────────────
    always @(posedge clk) begin
        if (!rst_n) begin
            ipr <= 8'h00;
        end else begin
            // Set bit nếu có sự kiện (mức cao 1 chu kỳ từ channel FSM)
            // Clear bit nếu CPU ghi ICR (ghi 1 vào bit tương ứng)
            if (reg_wr_en && reg_addr == 2'h2) begin
                // ICR write: xóa các bit được ghi = 1
                ipr <= (ipr | irq_src) & ~reg_wr_data;
            end else begin
                ipr <= ipr | irq_src;
            end
        end
    end

    // ── IMR: CPU ghi trực tiếp ───────────────────────────────────────────────
    always @(posedge clk) begin
        if (!rst_n) begin
            imr <= 8'h00;  // Mặc định không mask bất kỳ ngắt nào
        end else if (reg_wr_en && reg_addr == 2'h0) begin
            imr <= reg_wr_data;
        end
    end

    // ── Đọc register ────────────────────────────────────────────────────────
    always @(*) begin
        case (reg_addr)
            2'h0:    reg_rd_data = imr;
            2'h1:    reg_rd_data = ipr;
            default: reg_rd_data = 8'h00;
        endcase
    end

    // ── IRQ output ──────────────────────────────────────────────────────────
    // Có ngắt khi bất kỳ bit nào trong IPR active mà không bị mask
    assign irq_out = |(ipr & ~imr);

endmodule
