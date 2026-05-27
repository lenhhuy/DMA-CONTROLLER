// =============================================================================
// Testbench : tb_irq_controller
// Module    : irq_controller
// Fix       : Verilog-2001 compatible (begin..end trong task, old-style port)
// Test cases:
//   TC1 - TC từ kênh 0 → IPR[0] set, irq_out lên
//   TC2 - BE từ kênh 2 → IPR[6] set
//   TC3 - CPU xóa ngắt qua ICR → IPR clear, irq_out xuống
//   TC4 - IMR mask ngắt → irq_out không lên
//   TC5 - Nhiều nguồn ngắt cùng lúc → tất cả bit IPR set
//   TC6 - Đọc thanh ghi IMR qua CPU interface
// =============================================================================

`timescale 1ns / 1ps

module tb_irq_controller;

    // ── DUT signals ──────────────────────────────────────────────────────────
    reg        clk, rst_n;
    reg  [3:0] tc, be;
    reg  [1:0] reg_addr;
    reg        reg_wr_en;
    reg  [7:0] reg_wr_data;
    wire [7:0] reg_rd_data;
    wire       irq_out;

    // ── Biến phụ ở module level (Verilog-2001) ───────────────────────────────
    integer errors;

    // ── Địa chỉ register ─────────────────────────────────────────────────────
    localparam ADDR_IMR = 2'h0;
    localparam ADDR_IPR = 2'h1;
    localparam ADDR_ICR = 2'h2;

    // ── DUT ──────────────────────────────────────────────────────────────────
    irq_controller DUT (
        .clk(clk), .rst_n(rst_n),
        .tc(tc), .be(be),
        .reg_addr(reg_addr), .reg_wr_en(reg_wr_en),
        .reg_wr_data(reg_wr_data), .reg_rd_data(reg_rd_data),
        .irq_out(irq_out)
    );

    // ── Clock ─────────────────────────────────────────────────────────────────
    initial clk = 0;
    always #5 clk = ~clk;

    // ── Tasks (Verilog-2001: begin..end bắt buộc, old-style port) ────────────

    task reset_dut;
        begin
            rst_n = 0; tc = 0; be = 0;
            reg_wr_en = 0; reg_addr = 0; reg_wr_data = 0;
            repeat(3) @(posedge clk); #1;
            rst_n = 1; @(posedge clk); #1;
        end
    endtask

    task pulse_tc;
        input [3:0] ch_mask;
        begin
            @(negedge clk); tc = ch_mask;
            @(posedge clk); #1; tc = 0;
        end
    endtask

    task pulse_be;
        input [3:0] ch_mask;
        begin
            @(negedge clk); be = ch_mask;
            @(posedge clk); #1; be = 0;
        end
    endtask

    task cpu_write;
        input [1:0] addr;
        input [7:0] data;
        begin
            @(negedge clk);
            reg_addr = addr; reg_wr_data = data; reg_wr_en = 1;
            @(posedge clk); #1;
            reg_wr_en = 0;
        end
    endtask

    task cpu_read;
        input [1:0] addr;
        begin
            @(negedge clk);
            reg_addr = addr; reg_wr_en = 0;
            @(posedge clk); #1;
        end
    endtask

    // ── Test ─────────────────────────────────────────────────────────────────
    initial begin
        $dumpfile("tb_irq_controller.vcd");
        $dumpvars(0, tb_irq_controller);
        errors = 0;

        // ══════════════════════════════════════════════════════════════════════
        // TC1: TC kênh 0 → IPR[0] set, irq_out = 1
        // ══════════════════════════════════════════════════════════════════════
        $display("\n[TC1] TC tu kenh 0 -> IPR[0] set, irq_out = 1");
        reset_dut;
        pulse_tc(4'b0001);
        @(posedge clk); #1;
        cpu_read(ADDR_IPR);
        $display("  IPR = %08b (ky vong: xxxxxx01)", reg_rd_data);
        if (reg_rd_data[0] !== 1'b1) begin
            $display("  FAIL: IPR[0] phai = 1"); errors = errors + 1;
        end else $display("  PASS: IPR[0] = 1");
        if (irq_out !== 1'b1) begin
            $display("  FAIL: irq_out phai = 1"); errors = errors + 1;
        end else $display("  PASS: irq_out = 1");

        // ══════════════════════════════════════════════════════════════════════
        // TC2: BE kênh 2 → IPR[6] set
        // ══════════════════════════════════════════════════════════════════════
        $display("\n[TC2] BE tu kenh 2 -> IPR[6] set");
        reset_dut;
        pulse_be(4'b0100);
        @(posedge clk); #1;
        cpu_read(ADDR_IPR);
        $display("  IPR = %08b (ky vong: 01xxxxxx)", reg_rd_data);
        if (reg_rd_data[6] !== 1'b1) begin
            $display("  FAIL: IPR[6] phai = 1"); errors = errors + 1;
        end else $display("  PASS: IPR[6] = 1");

        // ══════════════════════════════════════════════════════════════════════
        // TC3: ICR clear → IPR = 0, irq_out xuống
        // ══════════════════════════════════════════════════════════════════════
        $display("\n[TC3] CPU ghi ICR -> IPR clear, irq_out xuong 0");
        reset_dut;
        @(negedge clk); tc = 4'b0011;
        @(posedge clk); #1; tc = 0;
        @(posedge clk); #1;
        cpu_read(ADDR_IPR);
        $display("  IPR truoc ICR: %08b", reg_rd_data);
        cpu_write(ADDR_ICR, 8'hFF);
        @(posedge clk); #1;
        cpu_read(ADDR_IPR);
        $display("  IPR sau ICR:   %08b (ky vong: 00000000)", reg_rd_data);
        if (reg_rd_data !== 8'h00) begin
            $display("  FAIL: IPR phai = 0"); errors = errors + 1;
        end else $display("  PASS: IPR = 0");
        if (irq_out !== 1'b0) begin
            $display("  FAIL: irq_out phai = 0"); errors = errors + 1;
        end else $display("  PASS: irq_out = 0");

        // ══════════════════════════════════════════════════════════════════════
        // TC4: IMR mask → irq_out không lên
        // ══════════════════════════════════════════════════════════════════════
        $display("\n[TC4] IMR mask TC kenh 1 -> irq_out = 0");
        reset_dut;
        cpu_write(ADDR_IMR, 8'b00000010);
        pulse_tc(4'b0010);
        @(posedge clk); #1;
        cpu_read(ADDR_IPR);
        $display("  IPR = %08b", reg_rd_data);
        if (irq_out !== 1'b0) begin
            $display("  FAIL: irq_out phai = 0 khi bi mask"); errors = errors + 1;
        end else $display("  PASS: irq_out = 0 (masked)");
        // Bỏ mask → irq_out lên
        cpu_write(ADDR_IMR, 8'h00);
        @(posedge clk); #1;
        if (irq_out !== 1'b1) begin
            $display("  FAIL: irq_out phai = 1 sau bo mask"); errors = errors + 1;
        end else $display("  PASS: irq_out = 1 sau bo mask");

        // ══════════════════════════════════════════════════════════════════════
        // TC5: 4 kênh TC cùng lúc → IPR[3:0] = 1111
        // ══════════════════════════════════════════════════════════════════════
        $display("\n[TC5] TC 4 kenh dong thoi -> IPR[3:0] = 1111");
        reset_dut;
        @(negedge clk); tc = 4'b1111;
        @(posedge clk); #1; tc = 0;
        @(posedge clk); #1;
        cpu_read(ADDR_IPR);
        $display("  IPR = %08b (ky vong: xxxx1111)", reg_rd_data);
        if (reg_rd_data[3:0] !== 4'b1111) begin
            $display("  FAIL: IPR[3:0] phai = 1111"); errors = errors + 1;
        end else $display("  PASS: IPR[3:0] = 1111");

        // ══════════════════════════════════════════════════════════════════════
        // TC6: Đọc IMR qua CPU interface
        // ══════════════════════════════════════════════════════════════════════
        $display("\n[TC6] CPU doc IMR -> tra ve dung gia tri");
        reset_dut;
        cpu_write(ADDR_IMR, 8'hA5);
        cpu_read(ADDR_IMR);
        $display("  IMR = %08b (ky vong: 10100101)", reg_rd_data);
        if (reg_rd_data !== 8'hA5) begin
            $display("  FAIL: IMR expected A5, got %02h", reg_rd_data);
            errors = errors + 1;
        end else $display("  PASS: IMR = A5");

        // ── Kết quả ──────────────────────────────────────────────────────────
        $display("\n========================================");
        if (errors == 0)
            $display("  KET QUA: TAT CA TEST PASS [irq_controller]");
        else
            $display("  KET QUA: %0d TEST FAIL [irq_controller]", errors);
        $display("========================================\n");
        $finish;
    end

    initial begin #50000; $display("TIMEOUT"); $finish; end

endmodule
