// =============================================================================
// Module  : dma_fifo
// Project : DMA Controller 4-Channel
// Brief   : Synchronous FIFO – Depth=16, Width=8
//           Mỗi kênh DMA sở hữu một FIFO riêng làm staging buffer,
//           tránh mất dữ liệu khi Arbiter chưa cấp grant.
//
// Ports
//   clk         – clock hệ thống (sườn lên)
//   rst_n       – reset đồng bộ, tích cực mức thấp
//   wr_en       – ghi 1 byte vào FIFO (từ ngoại vi)
//   rd_en       – đọc 1 byte ra (DMA đọc để ghi lên bus)
//   din[7:0]    – dữ liệu đầu vào
//   dout[7:0]   – dữ liệu đầu ra (registered)
//   full        – FIFO đầy, ngoại vi không được ghi thêm
//   empty       – FIFO rỗng, DMA không được đọc
//   almost_full – còn đúng 1 ô trống (cảnh báo sớm cho IRQ)
// =============================================================================

`timescale 1ns / 1ps

module dma_fifo #(
    parameter DEPTH = 16,   // Số entry (phải là lũy thừa của 2)
    parameter WIDTH = 8     // Độ rộng dữ liệu (bits)
)(
    input  wire             clk,
    input  wire             rst_n,
    // Write port (từ ngoại vi)
    input  wire             wr_en,
    input  wire [WIDTH-1:0] din,
    // Read port (từ DMA channel FSM)
    input  wire             rd_en,
    output reg  [WIDTH-1:0] dout,
    // Status
    output wire             full,
    output wire             empty,
    output wire             almost_full
);

    // ── Tham số nội bộ ──────────────────────────────────────────────────────
    localparam ADDR_W = $clog2(DEPTH);   // Số bit địa chỉ (4 bit cho depth=16)

    // ── Bộ nhớ và con trỏ ───────────────────────────────────────────────────
    reg [WIDTH-1:0]  mem [0:DEPTH-1];
    reg [ADDR_W:0]   wp;   // Write pointer – ADDR_W+1 bit để phân biệt full/empty
    reg [ADDR_W:0]   rp;   // Read pointer

    // ── Điều kiện biên ──────────────────────────────────────────────────────
    // Kỹ thuật dùng 1 bit extra: full khi bit MSB khác nhau, các bit thấp bằng nhau
    assign empty       = (wp == rp);
    assign full        = (wp[ADDR_W] != rp[ADDR_W]) && (wp[ADDR_W-1:0] == rp[ADDR_W-1:0]);
    assign almost_full = (wp[ADDR_W] != rp[ADDR_W]) && (wp[ADDR_W-1:0] == rp[ADDR_W-1:0] - 1'b1)
                       || ({1'b0, wp[ADDR_W-1:0]} == {1'b0, rp[ADDR_W-1:0]} + (DEPTH-1));
    // Cách đơn giản hơn cho almost_full: count == DEPTH-1
    // Dùng count register bên dưới sẽ rõ ràng hơn cho synthesis

    // ── Bộ đếm số phần tử ───────────────────────────────────────────────────
    reg [ADDR_W:0] count;

    always @(posedge clk) begin
        if (!rst_n) begin
            wp    <= 0;
            rp    <= 0;
            count <= 0;
            dout  <= 0;
        end else begin
            // Ghi: chỉ ghi khi không full (hoặc đồng thời read-write)
            if (wr_en && !full) begin
                mem[wp[ADDR_W-1:0]] <= din;
                wp <= wp + 1'b1;
            end

            // Đọc: chỉ đọc khi không empty
            if (rd_en && !empty) begin
                dout <= mem[rp[ADDR_W-1:0]];
                rp   <= rp + 1'b1;
            end

            // Cập nhật count
            case ({wr_en & !full, rd_en & !empty})
                2'b10:   count <= count + 1'b1;
                2'b01:   count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

    // Override almost_full dùng count để synthesis rõ ràng hơn
    // (ghi đè wire ở trên – trong thực tế chỉ dùng 1 cách)
    // Uncomment dòng dưới và xóa assign almost_full ở trên nếu muốn dùng count:
    // assign almost_full = (count == DEPTH - 1);

endmodule
