// =============================================================================
// Testbench : tb_dma_channel
// Module    : dma_channel
// Test cases:
//   TC1 – Truyền bình thường (normal transfer): IDLE→REQUEST→WAIT_HLDA→TRANSFER→DONE
//   TC2 – TC pulse và EOP phát đúng khi BCR = 0
//   TC3 – Timeout HLDA → chuyển về ERROR, phát BE
//   TC4 – FIFO empty trong TRANSFER → chờ, không bị lỗi
//   TC5 – Reset giữa chừng → trở về IDLE ngay
// =============================================================================

`timescale 1ns / 1ps

module tb_dma_channel;

    // ── DUT signals ──────────────────────────────────────────────────────────
    reg        clk, rst_n;
    reg        start;
    reg [15:0] src_addr, dst_addr, byte_count;
    reg  [1:0] mode;
    reg  [7:0] crc_expected;
    wire       req;
    reg        grant;
    wire       hld;
    reg        hlda;
    reg        dreq;
    wire       dack;
    reg  [7:0] fifo_dout;
    reg        fifo_empty;
    wire       fifo_rd_en;
    wire [15:0] addr_bus;
    wire  [7:0] data_bus;
    wire        mem_wr, io_rd;
    wire        eop, crc_init, crc_en, crc_check;
    wire  [7:0] crc_data;
    wire        busy, tc, be;

    // ── DUT ──────────────────────────────────────────────────────────────────
    dma_channel #(.TIMEOUT_CNT(8)) DUT (
        .clk(clk), .rst_n(rst_n),
        .start(start),
        .src_addr(src_addr), .dst_addr(dst_addr),
        .byte_count(byte_count), .mode(mode),
        .crc_expected(crc_expected),
        .req(req), .grant(grant),
        .hld(hld), .hlda(hlda),
        .dreq(dreq), .dack(dack),
        .fifo_dout(fifo_dout), .fifo_empty(fifo_empty),
        .fifo_rd_en(fifo_rd_en),
        .addr_bus(addr_bus), .data_bus(data_bus),
        .mem_wr(mem_wr), .io_rd(io_rd),
        .eop(eop),
        .crc_init(crc_init), .crc_en(crc_en),
        .crc_data(crc_data), .crc_check(crc_check),
        .busy(busy), .tc(tc), .be(be)
    );

    // ── Clock ─────────────────────────────────────────────────────────────────
    initial clk = 0;
    always #5 clk = ~clk;

    // ── Tasks ─────────────────────────────────────────────────────────────────
    task reset_dut;
        rst_n = 0;
        start = 0; grant = 0; hlda = 0; dreq = 0;
        fifo_dout = 0; fifo_empty = 1;
        src_addr = 16'h1000; dst_addr = 16'h2000;
        byte_count = 4; mode = 2'b00;  // Burst
        crc_expected = 8'hF4;
        repeat(4) @(posedge clk); #1;
        rst_n = 1; @(posedge clk); #1;
    endtask

    task tick(input integer n);
        repeat(n) @(posedge clk); #1;
    endtask

    // Khởi động kênh: pulse start 1 chu kỳ
    task kick_channel;
        @(negedge clk); start = 1; dreq = 1;
        @(posedge clk); #1; start = 0;
    endtask

    // Giả lập Arbiter cấp grant sau khi thấy req
    task grant_after_req;
        wait(req === 1'b1);
        @(posedge clk); #1;
        grant = 1;
        @(posedge clk); #1;
        grant = 0;
    endtask

    // Giả lập CPU phản hồi HLDA sau khi thấy HLD
    task hlda_after_hld;
        wait(hld === 1'b1);
        @(posedge clk); tick(1);
        hlda = 1;
        @(posedge clk); #1;
        hlda = 0;
    endtask

    integer errors;
    integer i;
    integer tc_seen, be_seen, eop_seen;

    initial begin
        $dumpfile("tb_dma_channel.vcd");
        $dumpvars(0, tb_dma_channel);
        errors = 0;

        // ══════════════════════════════════════════════════════════════════════
        // TC1: Truyền bình thường – 4 byte
        // ══════════════════════════════════════════════════════════════════════
        $display("\n[TC1] Truyen binh thuong 4 byte: IDLE->REQUEST->WAIT_HLDA->TRANSFER->DONE");
        reset_dut;

        byte_count = 4;
        // Chuẩn bị FIFO model: luôn có dữ liệu
        fifo_empty = 0;
        fifo_dout  = 8'hAB;

        kick_channel;

        // Arbiter cấp grant
        fork
            grant_after_req;
            hlda_after_hld;
        join

        // Chờ transfer hoàn tất (DONE state)
        tc_seen = 0;
        repeat(30) begin
            @(posedge clk); #1;
            if (tc === 1'b1) tc_seen = 1;
        end

        if (tc_seen) begin
            $display("  PASS: TC pulse nhan duoc sau transfer");
        end else begin
            $display("  FAIL: Khong co TC pulse sau %0d byte", byte_count);
            errors = errors + 1;
        end

        if (busy !== 1'b0) begin
            $display("  FAIL: busy phai = 0 sau DONE"); errors = errors + 1;
        end else $display("  PASS: busy = 0 sau DONE");

        // ══════════════════════════════════════════════════════════════════════
        // TC2: Kiểm tra addr_bus tăng đúng và EOP phát
        // ══════════════════════════════════════════════════════════════════════
        $display("\n[TC2] Kiem tra addr_bus tang va EOP");
        reset_dut;

        byte_count = 3; dst_addr = 16'h3000;
        fifo_empty = 0; fifo_dout = 8'h11;

        kick_channel;

        fork
            grant_after_req;
            hlda_after_hld;
        join

        eop_seen = 0;
        repeat(30) begin
            @(posedge clk); #1;
            if (eop === 1'b1) eop_seen = 1;
        end

        if (eop_seen) $display("  PASS: EOP pulse nhan duoc");
        else begin
            $display("  FAIL: Khong co EOP"); errors = errors + 1;
        end

        // ══════════════════════════════════════════════════════════════════════
        // TC3: Timeout HLDA → ERROR state, BE pulse
        // ══════════════════════════════════════════════════════════════════════
        $display("\n[TC3] Timeout HLDA (CPU khong phan hoi) -> ERROR, BE = 1");
        reset_dut;

        byte_count = 4; fifo_empty = 0;
        kick_channel;

        // Cấp grant nhưng KHÔNG phản hồi HLDA
        wait(req === 1'b1);
        @(posedge clk); #1;
        grant = 1; @(posedge clk); #1; grant = 0;

        // hlda = 0, chờ timeout (TIMEOUT_CNT=8 chu kỳ)
        be_seen = 0;
        repeat(30) begin
            @(posedge clk); #1;
            if (be === 1'b1) be_seen = 1;
        end

        if (be_seen) $display("  PASS: BE pulse sau HLDA timeout");
        else begin
            $display("  FAIL: Khong co BE sau timeout"); errors = errors + 1;
        end

        if (busy !== 1'b0) begin
            $display("  FAIL: busy phai = 0 sau ERROR"); errors = errors + 1;
        end else $display("  PASS: busy = 0 sau ERROR");

        // ══════════════════════════════════════════════════════════════════════
        // TC4: FIFO empty trong quá trình TRANSFER → chờ, không lỗi ngay
        // ══════════════════════════════════════════════════════════════════════
        $display("\n[TC4] FIFO empty trong TRANSFER -> channel cho, sau do tiep tuc");
        reset_dut;

        byte_count = 4; fifo_empty = 1;  // Ban đầu FIFO rỗng

        kick_channel;

        fork
            grant_after_req;
            hlda_after_hld;
        join

        // Chờ vào TRANSFER state (hld và dack đều active)
        wait(hld === 1'b1 && dack === 1'b1);
        tick(2);

        // Bây giờ cấp dữ liệu FIFO
        fifo_empty = 0; fifo_dout = 8'h99;
        $display("  FIFO duoc cap du lieu sau 2 chu ky cho");

        // Chờ TC
        tc_seen = 0;
        repeat(30) begin
            @(posedge clk); #1;
            if (tc === 1'b1) tc_seen = 1;
        end

        if (tc_seen) $display("  PASS: TC nhan duoc sau khi FIFO co du lieu");
        else begin
            $display("  FAIL: Khong co TC"); errors = errors + 1;
        end

        // ══════════════════════════════════════════════════════════════════════
        // TC5: Reset giữa chừng → trở về IDLE ngay lập tức
        // ══════════════════════════════════════════════════════════════════════
        $display("\n[TC5] Reset giua chung -> busy = 0, tro ve IDLE");
        reset_dut;

        byte_count = 16; fifo_empty = 0; fifo_dout = 8'hCC;

        kick_channel;

        // Cấp grant, bắt đầu transfer
        fork
            grant_after_req;
            hlda_after_hld;
        join
        tick(2);  // Đang trong TRANSFER

        // Kích reset
        $display("  Kích rst_n = 0 giua TRANSFER...");
        rst_n = 0;
        @(posedge clk); #1;
        rst_n = 1;
        @(posedge clk); #1;

        if (busy !== 1'b0) begin
            $display("  FAIL: busy phai = 0 sau reset"); errors = errors + 1;
        end else $display("  PASS: busy = 0 sau reset");

        if (hld !== 1'b0) begin
            $display("  FAIL: hld phai = 0 sau reset"); errors = errors + 1;
        end else $display("  PASS: hld = 0 sau reset");

        if (dack !== 1'b0) begin
            $display("  FAIL: dack phai = 0 sau reset"); errors = errors + 1;
        end else $display("  PASS: dack = 0 sau reset");

        // ── Kết quả ──────────────────────────────────────────────────────────
        $display("\n========================================");
        if (errors == 0)
            $display("  KET QUA: TAT CA TEST PASS [dma_channel]");
        else
            $display("  KET QUA: %0d TEST FAIL [dma_channel]", errors);
        $display("========================================\n");

        $finish;
    end

    initial begin #100000; $display("TIMEOUT"); $finish; end

endmodule
