// =============================================================================
// Testbench : tb_crc8_inline
// Module    : crc8_inline
// Fix       : Khai bao reg o module level (Verilog-2001 compatible, Vivado)
// Test cases:
//   TC1 - CRC của chuỗi đã biết → so sánh với giá trị tính trước
//   TC2 - CRC khớp với expected → crc_ok = 1, crc_error = 0
//   TC3 - CRC không khớp → crc_error = 1 (phát hiện lỗi dữ liệu)
//   TC4 - init xóa CRC về FF, tính lại từ đầu
//   TC5 - en = 0 → CRC không thay đổi (gate đúng)
// =============================================================================

`timescale 1ns / 1ps

module tb_crc8_inline;

    // ── DUT signals ──────────────────────────────────────────────────────────
    reg        clk, rst_n;
    reg        init, en;
    reg  [7:0] data_in;
    wire [7:0] crc_out;
    reg        check_en;
    reg  [7:0] expected;
    wire       crc_ok, crc_error;

    // ── Biến phụ khai báo ở module level (Verilog-2001) ──────────────────────
    reg [7:0] computed;
    reg [7:0] wrong_exp;
    reg [7:0] crc_snap;
    integer   errors;

    // ── DUT ──────────────────────────────────────────────────────────────────
    crc8_inline DUT (
        .clk(clk), .rst_n(rst_n),
        .init(init), .en(en), .data_in(data_in),
        .crc_out(crc_out),
        .check_en(check_en), .expected(expected),
        .crc_ok(crc_ok), .crc_error(crc_error)
    );

    // ── Clock ─────────────────────────────────────────────────────────────────
    initial clk = 0;
    always #5 clk = ~clk;

    // ── Tasks ─────────────────────────────────────────────────────────────────
    task reset_dut;
        begin
            rst_n = 0; init = 0; en = 0;
            data_in = 0; check_en = 0; expected = 0;
            repeat(3) @(posedge clk); #1;
            rst_n = 1; @(posedge clk); #1;
        end
    endtask

    task crc_init;
        begin
            @(negedge clk); init = 1; en = 0;
            @(posedge clk); #1; init = 0;
        end
    endtask

    task feed_byte;
        input [7:0] b;
        begin
            @(negedge clk); en = 1; data_in = b; init = 0;
            @(posedge clk); #1; en = 0;
        end
    endtask

    task do_check;
        input [7:0] exp;
        begin
            @(negedge clk);
            check_en = 1; expected = exp; en = 0;
            @(posedge clk); #1;
            check_en = 0;
        end
    endtask

    // ── Test ─────────────────────────────────────────────────────────────────
    initial begin
        $dumpfile("tb_crc8_inline.vcd");
        $dumpvars(0, tb_crc8_inline);
        errors = 0;

        // ══════════════════════════════════════════════════════════════════════
        // TC1: CRC('123') = 0xEB
        // ══════════════════════════════════════════════════════════════════════
        $display("\n[TC1] CRC '123' (0x31 0x32 0x33) -> ky vong 0xEB");
        reset_dut;
        crc_init;
        feed_byte(8'h31);
        feed_byte(8'h32);
        feed_byte(8'h33);
        @(posedge clk); #1;
        $display("  CRC tinh duoc: %02h (ky vong: EB)", crc_out);
        if (crc_out !== 8'hEB) begin
            $display("  FAIL: CRC sai"); errors = errors + 1;
        end else $display("  PASS: CRC = EB");

        // ══════════════════════════════════════════════════════════════════════
        // TC2: CRC khớp expected → crc_ok = 1
        // ══════════════════════════════════════════════════════════════════════
        $display("\n[TC2] CRC khop expected -> crc_ok = 1");
        reset_dut;
        crc_init;
        feed_byte(8'hAA);
        feed_byte(8'hBB);
        feed_byte(8'hCC);
        @(posedge clk); #1;
        computed = crc_out;
        $display("  CRC tinh duoc: %02h", computed);
        do_check(computed);
        if (crc_ok !== 1'b1) begin
            $display("  FAIL: crc_ok phai = 1"); errors = errors + 1;
        end else $display("  PASS: crc_ok = 1");
        if (crc_error !== 1'b0) begin
            $display("  FAIL: crc_error phai = 0"); errors = errors + 1;
        end else $display("  PASS: crc_error = 0");

        // ══════════════════════════════════════════════════════════════════════
        // TC3: CRC không khớp → crc_error = 1
        // ══════════════════════════════════════════════════════════════════════
        $display("\n[TC3] CRC khong khop -> crc_error = 1");
        reset_dut;
        crc_init;
        feed_byte(8'h11);
        feed_byte(8'h22);
        feed_byte(8'h33);
        @(posedge clk); #1;
        wrong_exp = crc_out + 1;
        do_check(wrong_exp);
        if (crc_error !== 1'b1) begin
            $display("  FAIL: crc_error phai = 1"); errors = errors + 1;
        end else $display("  PASS: crc_error = 1");
        if (crc_ok !== 1'b0) begin
            $display("  FAIL: crc_ok phai = 0"); errors = errors + 1;
        end else $display("  PASS: crc_ok = 0");

        // ══════════════════════════════════════════════════════════════════════
        // TC4: init reset CRC về 0xFF
        // ══════════════════════════════════════════════════════════════════════
        $display("\n[TC4] init -> CRC reset ve 0xFF, tinh lai tu dau");
        reset_dut;
        crc_init;
        feed_byte(8'hDE);
        feed_byte(8'hAD);
        @(posedge clk); #1;
        $display("  CRC truoc init: %02h", crc_out);
        @(negedge clk); init = 1;
        @(posedge clk); #1; init = 0;
        $display("  CRC sau init (ky vong FF): %02h", crc_out);
        if (crc_out !== 8'hFF) begin
            $display("  FAIL: init khong reset ve FF"); errors = errors + 1;
        end else $display("  PASS: crc_out = FF sau init");
        feed_byte(8'h31);
        feed_byte(8'h32);
        feed_byte(8'h33);
        @(posedge clk); #1;
        $display("  CRC sau init + '123': %02h (ky vong: EB)", crc_out);
        if (crc_out !== 8'hEB) begin
            $display("  FAIL: tinh lai sau init sai"); errors = errors + 1;
        end else $display("  PASS: tinh lai dung sau init");

        // ══════════════════════════════════════════════════════════════════════
        // TC5: en = 0 → CRC không thay đổi
        // ══════════════════════════════════════════════════════════════════════
        $display("\n[TC5] en = 0 -> CRC giu nguyen");
        reset_dut;
        crc_init;
        feed_byte(8'h55);
        @(posedge clk); #1;
        crc_snap = crc_out;
        $display("  CRC sau 0x55: %02h", crc_snap);
        @(negedge clk); en = 0; data_in = 8'hFF;
        repeat(4) @(posedge clk); #1;
        $display("  CRC sau 4 chu ky (en=0): %02h", crc_out);
        if (crc_out !== crc_snap) begin
            $display("  FAIL: CRC thay doi khi en=0"); errors = errors + 1;
        end else $display("  PASS: CRC khong thay doi khi en=0");

        // ── Kết quả ──────────────────────────────────────────────────────────
        $display("\n========================================");
        if (errors == 0)
            $display("  KET QUA: TAT CA TEST PASS [crc8_inline]");
        else
            $display("  KET QUA: %0d TEST FAIL [crc8_inline]", errors);
        $display("========================================\n");
        $finish;
    end

    initial begin #50000; $display("TIMEOUT"); $finish; end

endmodule
