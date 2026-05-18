// =============================================================================
// Module  : dma_arbiter
// Project : DMA Controller 4-Channel
// Brief   : Bus Arbiter Round Robin thuần túy (không Fixed Priority).
//           Sau khi kênh i được grant, lần tiếp theo bắt đầu tìm từ i+1.
//           Đảm bảo fairness — mọi kênh đều được phục vụ, không starvation.
//
// Ports
//   clk         – clock hệ thống
//   rst_n       – reset đồng bộ tích cực thấp
//   req[3:0]    – yêu cầu từ 4 kênh (1 = kênh đang yêu cầu bus)
//   grant[3:0]  – cấp quyền cho kênh thắng (one-hot)
//   grant_valid – có ít nhất một grant đang active
// =============================================================================

`timescale 1ns / 1ps

module dma_arbiter (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [3:0] req,        // Yêu cầu từ 4 kênh
    output reg  [3:0] grant,      // Grant (one-hot)
    output wire       grant_valid // Có kênh nào được grant không
);

    // ── Con trỏ Round Robin ──────────────────────────────────────────────────
    // next_ptr: kênh tiếp theo được xét ưu tiên trong vòng hiện tại
    reg [1:0] next_ptr;

    // ── Round Robin combinational logic ──────────────────────────────────────
    // Xoay vòng bắt đầu từ next_ptr, cấp grant cho kênh đầu tiên có req
    reg [3:0] next_grant;
    integer   i;
    integer   idx;
    always @(*) begin
        next_grant = 4'b0000;
        for (i = 0; i < 4; i = i + 1) begin
            idx = (next_ptr + i) & 2'h3;   // (next_ptr + i) mod 4
            if (req[idx] && next_grant == 4'b0000)
                next_grant[idx] = 1'b1;
        end
    end

    // ── Register grant + cập nhật con trỏ ───────────────────────────────────
    always @(posedge clk) begin
        if (!rst_n) begin
            grant    <= 4'b0000;
            next_ptr <= 2'd0;
        end else begin
            grant <= next_grant;

            // Cập nhật next_ptr: kênh vừa được grant + 1 (mod 4)
            if (next_grant != 4'b0000) begin
                case (next_grant)
                    4'b0001: next_ptr <= 2'd1;
                    4'b0010: next_ptr <= 2'd2;
                    4'b0100: next_ptr <= 2'd3;
                    4'b1000: next_ptr <= 2'd0;
                    default: next_ptr <= next_ptr;
                endcase
            end
        end
    end

    assign grant_valid = |grant;

endmodule
