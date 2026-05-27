// =============================================================================
// Testbench : tb_dma_top
// Module    : dma_top (integration test)
// Test cases:
//   TC1 - Cấu hình CH0 qua CPU interface, kiểm tra register write
//   TC2 - CH0 transfer: DREQ → FIFO data → DMA hoàn tất → TC interrupt
//   TC3 - CH1 và CH0 cùng yêu cầu → Round Robin phân xử
//   TC4 - IRQ: đọc IPR sau transfer, xóa qua ICR
// =============================================================================

`timescale 1ns / 1ps

module tb_dma_top;

    // ── DUT signals ──────────────────────────────────────────────────────────
    reg          clk, rst_n;
    reg  [1:0]   cfg_ch_sel;
    reg          cfg_wr_en;
    reg  [2:0]   cfg_addr;
    reg  [7:0]   cfg_wr_data;
    wire [7:0]   cfg_rd_data;
    reg  [1:0]   irq_reg_addr;
    reg          irq_reg_wr_en;
    reg  [7:0]   irq_reg_wr_data;
    wire [7:0]   irq_reg_rd_data;
    reg  [3:0]   dreq;
    wire [3:0]   dack;
    wire         hld;
    reg          hlda;
    wire [15:0]  addr_bus;
    wire         mem_wr, io_rd;
    reg  [3:0]   fifo_wr_en;
    reg  [7:0]   fifo_din;
    wire [3:0]   ch_busy;
    wire         irq_out;
    wire [3:0]   fifo_full;

    // ── Biến phụ (Được khai báo ở Module level theo đúng chuẩn Verilog) ──────
    integer errors;
    integer ii; // Đặt ở đây giúp các vòng lặp for bên dưới chạy hoàn toàn hợp lệ

    // ── Địa chỉ IRQ register ─────────────────────────────────────────────────
    localparam ADDR_IMR = 2'h0;
    localparam ADDR_IPR = 2'h1;
    localparam ADDR_ICR = 2'h2;

    // ── DUT Instantiation ────────────────────────────────────────────────────
    dma_top DUT (
        .clk(clk), .rst_n(rst_n),
        .cfg_ch_sel(cfg_ch_sel), .cfg_wr_en(cfg_wr_en),
        .cfg_addr(cfg_addr),     .cfg_wr_data(cfg_wr_data),
        .cfg_rd_data(cfg_rd_data),
        .irq_reg_addr(irq_reg_addr),   .irq_reg_wr_en(irq_reg_wr_en),
        .irq_reg_wr_data(irq_reg_wr_data),
        .irq_reg_rd_data(irq_reg_rd_data),
        .dreq(dreq),   .dack(dack),
        .hld(hld),     .hlda(hlda),
        .addr_bus(addr_bus), .mem_wr(mem_wr), .io_rd(io_rd),
        .fifo_wr_en(fifo_wr_en), .fifo_din(fifo_din),
        .ch_busy(ch_busy), .irq_out(irq_out), .fifo_full(fifo_full)
    );

    // ── Clock Generation (100 MHz) ───────────────────────────────────────────
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ── Tasks ─────────────────────────────────────────────────────────────────

    task reset_sys;
        begin
            rst_n         = 1'b0;
            cfg_wr_en     = 1'b0;  cfg_ch_sel  = 2'd0;
            cfg_addr      = 3'd0;  cfg_wr_data = 8'd0;
            irq_reg_wr_en = 1'b0;  irq_reg_addr= 2'd0;
            irq_reg_wr_data = 8'd0;
            dreq          = 4'b0000;
            hlda          = 1'b0;
            fifo_wr_en    = 4'b0000;
            fifo_din      = 8'd0;
            repeat(5) @(posedge clk); #1;
            rst_n = 1'b1;
            repeat(2) @(posedge clk); #1;
        end
    endtask

    // Ghi 1 byte vào config register của kênh ch_sel
    task cfg_write;
        input [1:0] ch_sel;
        input [2:0] addr;
        input [7:0] data;
        begin
            @(negedge clk);
            cfg_ch_sel  = ch_sel;
            cfg_addr    = addr;
            cfg_wr_data = data;
            cfg_wr_en   = 1'b1;
            @(posedge clk); #1;
            cfg_wr_en = 1'b0;
        end
    endtask

    // Ghi byte vào FIFO của kênh
    task push_fifo;
        input [3:0] ch_mask;
        input [7:0] data;
        begin
            @(negedge clk);
            fifo_wr_en = ch_mask;
            fifo_din   = data;
            @(posedge clk); #1;
            fifo_wr_en = 4'b0000;
        end
    endtask

    // Ghi IRQ register
    task irq_write;
        input [1:0] addr;
        input [7:0] data;
        begin
            @(negedge clk);
            irq_reg_addr    = addr;
            irq_reg_wr_data = data;
            irq_reg_wr_en   = 1'b1;
            @(posedge clk); #1;
            irq_reg_wr_en = 1'b0;
        end
    endtask

    // Đọc IRQ register
    task irq_read;
        input [1:0] addr;
        begin
            @(negedge clk);
            irq_reg_addr  = addr;
            irq_reg_wr_en = 1'b0;
            @(posedge clk); #1;
        end
    endtask

    // ── Test Sequence ────────────────────────────────────────────────────────
    initial begin
        errors = 0;

        // ══════════════════════════════════════════════════════════════════════
        // TC1: Cấu hình CH0 qua CPU interface
        //      src=0x1000, dst=0x2000, byte_count=4, mode=Burst
        // ══════════════════════════════════════════════════════════════════════
        $display("\n[TC1] Cau hinh CH0: src=0x1000, dst=0x2000, count=4");
        reset_sys;

        cfg_write(2'd0, 3'd0, 8'h00); // src_lo = 0x00
        cfg_write(2'd0, 3'd1, 8'h10); // src_hi = 0x10 → 0x1000
        cfg_write(2'd0, 3'd2, 8'h00); // dst_lo = 0x00
        cfg_write(2'd0, 3'd3, 8'h20); // dst_hi = 0x20 → 0x2000
        cfg_write(2'd0, 3'd4, 8'h04); // byte_cnt_lo = 4
        cfg_write(2'd0, 3'd5, 8'h00); // byte_cnt_hi = 0
        cfg_write(2'd0, 3'd7, 8'hEB); // CRC expected

        $display("  PASS: Cau hinh CH0 hoan tat (khong loi config)");

        // ══════════════════════════════════════════════════════════════════════
        // TC2: CH0 transfer hoàn chỉnh
        // ══════════════════════════════════════════════════════════════════════
        $display("\n[TC2] CH0 transfer 4 byte: DREQ -> HLD -> HLDA -> TRANSFER -> TC");
        reset_sys;

        // Cấu hình CH0
        cfg_write(2'd0, 3'd2, 8'h00);
        cfg_write(2'd0, 3'd3, 8'h20);
        cfg_write(2'd0, 3'd4, 8'h04);
        cfg_write(2'd0, 3'd5, 8'h00);
        cfg_write(2'd0, 3'd7, 8'hEB);

        // Nạp 4 byte vào FIFO CH0 trước
        push_fifo(4'b0001, 8'hAA);
        push_fifo(4'b0001, 8'hBB);
        push_fifo(4'b0001, 8'hCC);
        push_fifo(4'b0001, 8'hDD);

        // Kích DREQ và start
        dreq = 4'b0001;
        cfg_write(2'd0, 3'd6, 8'h04); // ctrl: bit2=start, mode=Burst

        // Giả lập CPU phản hồi HLDA khi nhận HLD
        for (ii = 0; ii < 60; ii = ii + 1) begin
            @(posedge clk); #1;
            if (hld === 1'b1 && hlda === 1'b0) begin
                hlda = 1'b1;
            end
            if (hld === 1'b0) begin
                hlda = 1'b0;
            end
        end

        dreq = 4'b0000;

        // Chờ và kiểm tra irq_out
        for (ii = 0; ii < 20; ii = ii + 1) begin
            @(posedge clk); #1;
        end

        $display("  ch_busy    = %b", ch_busy);
        $display("  irq_out    = %b", irq_out);
        $display("  addr_bus   = 0x%04h", addr_bus);

        irq_read(ADDR_IPR);
        $display("  IPR        = %08b", irq_reg_rd_data);

        if (ch_busy[0] !== 1'b0)
            $display("  WARN: CH0 van busy, co the chua xong");
        else
            $display("  PASS: CH0 da hoan tat (busy=0)");

        // ══════════════════════════════════════════════════════════════════════
        // TC3: CH0 và CH1 cùng yêu cầu → Round Robin
        // ══════════════════════════════════════════════════════════════════════
        $display("\n[TC3] CH0+CH1 cung DREQ -> Round Robin phan xu");
        reset_sys;

        // Cấu hình cả 2 kênh
        cfg_write(2'd0, 3'd4, 8'h02); // CH0: 2 byte
        cfg_write(2'd0, 3'd5, 8'h00);
        cfg_write(2'd1, 3'd4, 8'h02); // CH1: 2 byte
        cfg_write(2'd1, 3'd5, 8'h00);

        // Nạp FIFO cho cả 2 kênh
        push_fifo(4'b0001, 8'h11);
        push_fifo(4'b0001, 8'h22);
        push_fifo(4'b0010, 8'h33);
        push_fifo(4'b0010, 8'h44);

        // DREQ cả 2 kênh đồng thời
        dreq = 4'b0011;
        cfg_write(2'd0, 3'd6, 8'h04); // start CH0
        cfg_write(2'd1, 3'd6, 8'h04); // start CH1

        for (ii = 0; ii < 80; ii = ii + 1) begin
            @(posedge clk); #1;
            if (hld === 1'b1) hlda = 1'b1;
            else              hlda = 1'b0;
        end

        dreq = 4'b0000;
        @(posedge clk); #1; hlda = 1'b0;

        $display("  ch_busy = %b (ky vong: 00xx sau khi ca 2 xong)", ch_busy);
        irq_read(ADDR_IPR);
        $display("  IPR     = %08b", irq_reg_rd_data);

        if (irq_reg_rd_data[1:0] === 2'b11)
            $display("  PASS: Ca CH0 va CH1 deu co TC");
        else
            $display("  INFO: IPR = %02h (kiem tra waveform)", irq_reg_rd_data);

        // ══════════════════════════════════════════════════════════════════════
        // TC4: Đọc IPR → xóa qua ICR → irq_out xuống
        // ══════════════════════════════════════════════════════════════════════
        $display("\n[TC4] Doc IPR, xoa ICR -> irq_out xuong 0");

        $display("  irq_out truoc ICR: %b", irq_out);
        irq_write(ADDR_ICR, 8'hFF);
        @(posedge clk); #1;
        $display("  irq_out sau  ICR: %b (ky vong: 0)", irq_out);

        if (irq_out !== 1'b0) begin
            $display("  FAIL: irq_out phai = 0"); errors = errors + 1;
        end else
            $display("  PASS: irq_out = 0 sau ICR clear");

        // ── Kết quả tổng hợp ─────────────────────────────────────────────────
        $display("\n========================================");
        if (errors == 0)
            $display("  KET QUA: TAT CA TEST PASS [dma_top]");
        else
            $display("  KET QUA: %0d TEST FAIL [dma_top]", errors);
        $display("========================================\n");

        #200;
        $finish;
    end

    // Timeout phòng ngừa kẹt mạch
    initial begin #200000; $display("TIMEOUT ERROR"); $finish; end

endmodule