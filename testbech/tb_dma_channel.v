// =============================================================================
// Testbench : tb_dma_channel
// Module    : dma_channel
// Fix       : Verilog-2001 compatible (begin..end trong task, khai bao reg
//             o module level, old-style task port)
// Test cases:
//   TC1 - Truyền bình thường: IDLE→REQUEST→WAIT_HLDA→TRANSFER→DONE
//   TC2 - TC pulse và EOP phát đúng khi BCR = 0
//   TC3 - Timeout HLDA → ERROR, BE pulse
//   TC4 - FIFO empty trong TRANSFER → chờ rồi tiếp tục
//   TC5 - Reset giữa chừng → trở về IDLE ngay
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

    // ── Biến phụ khai báo ở module level (Verilog-2001) ──────────────────────
    integer errors;
    integer tc_seen, be_seen, eop_seen;
    integer ii;

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

    // ── Tasks (Verilog-2001: begin..end bắt buộc, old-style port) ────────────

    task reset_dut;
        begin
            rst_n = 0;
            start = 0; grant = 0; hlda = 0; dreq = 0;
            fifo_dout = 0; fifo_empty = 1;
            src_addr = 16'h1000; dst_addr = 16'h2000;
            byte_count = 4; mode = 2'b00;
            crc_expected = 8'hEB;
            repeat(4) @(posedge clk); #1;
            rst_n = 1; @(posedge clk); #1;
        end
    endtask

    // Old-style task port declaration (Verilog-2001)
    task tick;
        input integer n;
        begin
            repeat(n) @(posedge clk); #1;
        end
    endtask

    task kick_channel;
        begin
            @(negedge clk); start = 1; dreq = 1;
            @(posedge clk); #1; start = 0;
        end
    endtask

    task grant_after_req;
        begin
            wait(req === 1'b1);
            @(posedge clk); #1;
            grant = 1;
            @(posedge clk); #1;
            grant = 0;
        end
    endtask

    task hlda_after_hld;
        begin
            wait(hld === 1'b1);
            @(posedge clk); #1;
            hlda = 1;
            @(posedge clk); #1;
            hlda = 0;
        end
    endtask

    // ── Test ─────────────────────────────────────────────────────────────────
    initial begin
        $dumpfile("tb_dma_channel.vcd");
        $dumpvars(0, tb_dma_channel);
        errors = 0;

        // ══════════════════════════════════════════════════════════════════════
        // TC1: Truyền bình thường 4 byte
        // ══════════════════════════════════════════════════════════════════════
        $display("\n[TC1] Truyen binh thuong 4 byte: IDLE->REQUEST->WAIT_HLDA->TRANSFER->DONE");
        reset_dut;
        byte_count = 4;
        fifo_empty = 0; fifo_dout = 8'hAB;
        kick_channel;

        fork
            grant_after_req;
            hlda_after_hld;
        join

        tc_seen = 0;
        for (ii = 0; ii < 30; ii = ii + 1) begin
            @(posedge clk); #1;
            if (tc === 1'b1) tc_seen = 1;
        end

        if (tc_seen)
            $display("  PASS: TC pulse nhan duoc sau transfer");
        else begin
            $display("  FAIL: Khong co TC pulse"); errors = errors + 1;
        end

        if (busy !== 1'b0) begin
            $display("  FAIL: busy phai = 0 sau DONE"); errors = errors + 1;
        end else $display("  PASS: busy = 0 sau DONE");

        // ══════════════════════════════════════════════════════════════════════
        // TC2: EOP phát đúng khi kết thúc transfer
        // ══════════════════════════════════════════════════════════════════════
        $display("\n[TC2] Kiem tra EOP pulse");
        reset_dut;
        byte_count = 3; dst_addr = 16'h3000;
        fifo_empty = 0; fifo_dout = 8'h11;
        kick_channel;

        fork
            grant_after_req;
            hlda_after_hld;
        join

        eop_seen = 0;
        for (ii = 0; ii < 30; ii = ii + 1) begin
            @(posedge clk); #1;
            if (eop === 1'b1) eop_seen = 1;
        end

        if (eop_seen) $display("  PASS: EOP pulse nhan duoc");
        else begin
            $display("  FAIL: Khong co EOP"); errors = errors + 1;
        end

        // ══════════════════════════════════════════════════════════════════════
        // TC3: Timeout HLDA → ERROR, BE
        // ══════════════════════════════════════════════════════════════════════
        $display("\n[TC3] Timeout HLDA -> ERROR, BE = 1");
        reset_dut;
        byte_count = 4; fifo_empty = 0;
        kick_channel;

        wait(req === 1'b1);
        @(posedge clk); #1;
        grant = 1; @(posedge clk); #1; grant = 0;
        // Không phản hồi HLDA

        be_seen = 0;
        for (ii = 0; ii < 30; ii = ii + 1) begin
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
        // TC4: FIFO empty trong TRANSFER → chờ rồi tiếp tục
        // ══════════════════════════════════════════════════════════════════════
        $display("\n[TC4] FIFO empty trong TRANSFER -> cho roi tiep tuc");
        reset_dut;
        byte_count = 4; fifo_empty = 1;
        kick_channel;

        fork
            grant_after_req;
            hlda_after_hld;
        join

        wait(hld === 1'b1 && dack === 1'b1);
        tick(2);

        fifo_empty = 0; fifo_dout = 8'h99;
        $display("  FIFO duoc cap du lieu sau 2 chu ky cho");

        tc_seen = 0;
        for (ii = 0; ii < 30; ii = ii + 1) begin
            @(posedge clk); #1;
            if (tc === 1'b1) tc_seen = 1;
        end

        if (tc_seen) $display("  PASS: TC nhan duoc sau khi FIFO co du lieu");
        else begin
            $display("  FAIL: Khong co TC"); errors = errors + 1;
        end

        // ══════════════════════════════════════════════════════════════════════
        // TC5: Reset giữa chừng → IDLE ngay
        // ══════════════════════════════════════════════════════════════════════
        $display("\n[TC5] Reset giua chung -> busy=0, hld=0, dack=0");
        reset_dut;
        byte_count = 16; fifo_empty = 0; fifo_dout = 8'hCC;
        kick_channel;

        fork
            grant_after_req;
            hlda_after_hld;
        join
        tick(2);

        $display("  Kich rst_n = 0 giua TRANSFER...");
        rst_n = 0;
        @(posedge clk); #1;
        rst_n = 1;
        @(posedge clk); #1;

        if (busy !== 1'b0) begin
            $display("  FAIL: busy phai = 0"); errors = errors + 1;
        end else $display("  PASS: busy = 0");

        if (hld !== 1'b0) begin
            $display("  FAIL: hld phai = 0"); errors = errors + 1;
        end else $display("  PASS: hld = 0");

        if (dack !== 1'b0) begin
            $display("  FAIL: dack phai = 0"); errors = errors + 1;
        end else $display("  PASS: dack = 0");

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
