// =============================================================================
// Module  : crc8_inline
// Project : DMA Controller 4-Channel
// Brief   : Tính CRC-8 song song (parallel) cho mỗi byte trong 1 clock cycle.
//           Đa thức sinh: G(x) = x^8 + x^2 + x + 1  →  0x07
//           Hoạt động inline: tính CRC đồng thời với quá trình truyền dữ liệu,
//           không gây thêm latency.
//
// Ports
//   clk         – clock hệ thống
//   rst_n       – reset đồng bộ tích cực thấp
//   init        – xóa CRC về 0xFF (bắt đầu frame mới, pulse 1 chu kỳ)
//   en          – cho phép cập nhật CRC (=1 khi byte hợp lệ đi qua)
//   data_in     – byte dữ liệu đang được truyền
//   crc_out     – giá trị CRC tích lũy hiện tại
//   check_en    – pulse 1 chu kỳ khi kết thúc transfer để so sánh CRC
//   expected    – giá trị CRC mong đợi (CPU nạp trước khi bắt đầu kênh)
//   crc_ok      – 1 nếu CRC khớp (assert cùng chu kỳ check_en+1)
//   crc_error   – 1 nếu CRC không khớp → kết nối tới IRQ Controller (be)
// =============================================================================

`timescale 1ns / 1ps

module crc8_inline (
    input  wire       clk,
    input  wire       rst_n,

    // Điều khiển
    input  wire       init,          // Khởi tạo CRC (bắt đầu transfer mới)
    input  wire       en,            // Enable: byte hợp lệ đang đi qua
    input  wire [7:0] data_in,       // Byte dữ liệu

    // Output CRC
    output reg  [7:0] crc_out,       // CRC tích lũy

    // Kiểm tra cuối frame
    input  wire       check_en,      // Pulse khi BCR=0 (transfer xong)
    input  wire [7:0] expected,      // CRC mong đợi (từ CPU config register)
    output reg        crc_ok,        // CRC khớp
    output reg        crc_error      // CRC lỗi → IRQ
);

    // ── Hàm tính CRC-8 parallel ──────────────────────────────────────────────
    // Đa thức: x^8 + x^2 + x + 1 (0x07)
    // Phương trình cập nhật CRC được dẫn xuất bằng cách khai triển
    // phép XOR từng bit theo đa thức sinh.
    //
    // Ký hiệu: crc[7:0] = CRC hiện tại, d[7:0] = byte mới
    //          new_crc[i] = hàm XOR của các bit crc và d
    //
    // Bảng bit (tính bằng phần mềm sinh mã từ đa thức 0x07, init=0xFF):
    function [7:0] crc8_next;
        input [7:0] crc;
        input [7:0] d;
        reg [7:0] c;
        begin
            c = crc ^ d;   // XOR với byte mới trước
            crc8_next[0] = c[0]^c[2]^c[3]^c[4]^c[6]^c[7];
            crc8_next[1] = c[0]^c[1]^c[2]^c[3]^c[5]^c[6];
            crc8_next[2] = c[0]^c[1]^c[3]^c[4]^c[7];
            crc8_next[3] = c[1]^c[2]^c[4]^c[5];
            crc8_next[4] = c[2]^c[3]^c[5]^c[6];
            crc8_next[5] = c[3]^c[4]^c[6]^c[7];
            crc8_next[6] = c[0]^c[2]^c[3]^c[4]^c[5]^c[7];
            crc8_next[7] = c[1]^c[3]^c[4]^c[5]^c[6];
        end
    endfunction

    // ── Sequential logic ─────────────────────────────────────────────────────
    always @(posedge clk) begin
        if (!rst_n) begin
            crc_out   <= 8'hFF;
            crc_ok    <= 1'b0;
            crc_error <= 1'b0;
        end else begin
            // Xóa cờ kết quả mỗi chu kỳ (pulse output)
            crc_ok    <= 1'b0;
            crc_error <= 1'b0;

            if (init) begin
                // Khởi tạo CRC = 0xFF (standard init value cho CRC-8/SMBUS)
                crc_out <= 8'hFF;
            end else if (en) begin
                // Cập nhật CRC parallel theo byte mới
                crc_out <= crc8_next(crc_out, data_in);
            end

            // Kiểm tra cuối frame
            if (check_en) begin
                if (crc_out == expected) begin
                    crc_ok    <= 1'b1;
                    crc_error <= 1'b0;
                end else begin
                    crc_ok    <= 1'b0;
                    crc_error <= 1'b1;
                end
            end
        end
    end

endmodule
