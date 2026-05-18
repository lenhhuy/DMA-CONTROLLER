// =============================================================================
// Testbench : tb_irq_controller
// Module    : irq_controller
// Test cases:
//   TC1 – Transfer Complete (TC) từ kênh 0 → IPR set, irq_out lên
//   TC2 – Bus Error (BE) từ kênh 2 → IPR set đúng bit
//   TC3 – CPU xóa ngắt qua ICR → IPR clear, irq_out xuống
//   TC4 – IMR mask ngắt → irq_out không lên dù IPR có sự kiện
//   TC5 – Nhiều nguồn ngắt cùng lúc → tất cả bit IPR đều set
//   TC6 – Đọc thanh ghi IMR và IPR qua CPU interface
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

    // ── Tasks ─────────────────────────────────────────────────────────────────
    task reset_dut;
        rst_n = 0; tc = 0; be = 0;
        reg_wr_en = 0; reg_addr = 0; reg_wr_data = 0;
        repeat(3) @(posedge clk); #1;
        rst_n = 1; @(posedge clk); #1;
    endtask

    // Phát pulse ngắt 1 chu kỳ từ kênh
    task pulse_tc(input [3:0] ch_mask);
        @(negedge clk); tc = ch_mask;
        @(posedge clk); #1; tc = 0;
    endtask

    task pulse_be(input [3:0] ch_mask);
        @(negedge clk); be = ch_mask;
        @(posedge clk); #1; be = 0;
    endtask

    // CPU ghi register
    task cpu_write(input [1:0] addr, input [7:0] data);
        @(negedge clk);
        reg_addr = addr; reg_wr_data = data; reg_wr_en = 1;
        @(posedge clk); #1;
        reg_wr_en = 0;
    endtask

    // CPU đọc register
    task cpu_read(input [1:0] addr);
        @(negedge clk);
        reg_addr = addr; reg_wr_en = 0;
        @(posedge clk); #1;
    endtask

    integer errors;

    // Địa chỉ register
    localparam ADDR_IMR = 2'h0;
    localparam ADDR_IPR = 2'h1;
    localparam ADDR_ICR = 2'h2;

    initial begin
        $dumpfile("tb_irq_controller.vcd");
        $dumpvars(0, tb_irq_controller);
        errors = 0;

        // ══════════════════════════════════════════════════════════════════════
        // TC1: Transfer Complete kênh 0 → IPR[0] set, irq_out = 1
        // ══════════════════════════════════════════════════════════════════════
        $display("\n[TC1] TC tu kenh 0 -> IPR[0] set, irq_out = 1");
        reset_dut;

        pulse_tc(4'b0001);  // TC từ CH0
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
        // TC2: Bus Error kênh 2 → IPR[6] set (be[2] → bit6)
        // ══════════════════════════════════════════════════════════════════════
        $display("\n[TC2] BE tu kenh 2 -> IPR[6] set");
        reset_dut;

        pulse_be(4'b0100);  // BE từ CH2
        @(posedge clk); #1;

        cpu_read(ADDR_IPR);
        $display("  IPR = %08b (ky vong: 01xxxxxx)", reg_rd_data);
        if (reg_rd_data[6] !== 1'b1) begin
            $display("  FAIL: IPR[6] phai = 1 (BE kenh 2)"); errors = errors + 1;
        end else $display("  PASS: IPR[6] = 1");

        // ══════════════════════════════════════════════════════════════════════
        // TC3: CPU xóa ngắt qua ICR → IPR clear, irq_out xuống 0
        // ══════════════════════════════════════════════════════════════════════
        $display("\n[TC3] CPU ghi ICR -> IPR clear, irq_out xuong 0");
        reset_dut;

        // Phát TC từ CH0 và CH1
        @(negedge clk); tc = 4'b0011;
        @(posedge clk); #1; tc = 0;
        @(posedge clk); #1;

        cpu_read(ADDR_IPR);
        $display("  IPR truoc ICR: %08b", reg_rd_data);

        // Xóa toàn bộ qua ICR
        cpu_write(ADDR_ICR, 8'hFF);
        @(posedge clk); #1;

        cpu_read(ADDR_IPR);
        $display("  IPR sau ICR:   %08b (ky vong: 00000000)", reg_rd_data);
        if (reg_rd_data !== 8'h00) begin
            $display("  FAIL: IPR phai = 0 sau ICR clear"); errors = errors + 1;
        end else $display("  PASS: IPR = 0 sau clear");

        if (irq_out !== 1'b0) begin
            $display("  FAIL: irq_out phai = 0"); errors = errors + 1;
        end else $display("  PASS: irq_out = 0");

        // ══════════════════════════════════════════════════════════════════════
        // TC4: IMR mask ngắt → irq_out KHÔNG lên dù có sự kiện
        // ══════════════════════════════════════════════════════════════════════
        $display("\n[TC4] IMR mask TC kenh 1 -> irq_out phai giu = 0");
        reset_dut;

        // Mask bit 1 (TC CH1)
        cpu_write(ADDR_IMR, 8'b00000010);

        // Phát TC từ CH1 (đã bị mask)
        pulse_tc(4'b0010);
        @(posedge clk); #1;

        cpu_read(ADDR_IPR);
        $display("  IPR = %08b (sự kien van duoc ghi nhan)", reg_rd_data);
        if (reg_rd_data[1] !== 1'b1) begin
            $display("  WARN: IPR[1] phai = 1 du bi mask (mask chi chan irq_out)");
        end

        if (irq_out !== 1'b0) begin
            $display("  FAIL: irq_out phai = 0 khi bi mask"); errors = errors + 1;
        end else $display("  PASS: irq_out = 0 (masked)");

        // Bỏ mask → irq_out lên ngay
        cpu_write(ADDR_IMR, 8'h00);
        @(posedge clk); #1;
        if (irq_out !== 1'b1) begin
            $display("  FAIL: irq_out phai len khi bo mask"); errors = errors + 1;
        end else $display("  PASS: irq_out = 1 sau khi bo mask");

        // ══════════════════════════════════════════════════════════════════════
        // TC5: Nhiều nguồn ngắt cùng lúc → tất cả bit IPR set
        // ══════════════════════════════════════════════════════════════════════
        $display("\n[TC5] TC tu tat ca 4 kenh dong thoi -> IPR[3:0] = 1111");
        reset_dut;

        @(negedge clk); tc = 4'b1111;  // TC từ CH0,1,2,3 cùng lúc
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
        $display("\n[TC6] CPU doc IMR sau khi ghi -> phai tra ve dung gia tri");
        reset_dut;

        cpu_write(ADDR_IMR, 8'hA5);
        cpu_read(ADDR_IMR);
        $display("  IMR doc duoc: %08b (ky vong: 10100101)", reg_rd_data);
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
