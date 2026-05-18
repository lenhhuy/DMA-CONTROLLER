// =============================================================================
// Testbench : tb_dma_arbiter
// Module    : dma_arbiter (Round Robin)
// Test cases:
//   TC1 – Chỉ 1 kênh yêu cầu → grant ngay cho kênh đó
//   TC2 – 2 kênh yêu cầu đồng thời → xoay vòng đúng thứ tự
//   TC3 – 4 kênh yêu cầu đồng thời → Round Robin quét đủ 4 kênh
//   TC4 – Con trỏ tiếp tục đúng sau khi kênh giải phóng
//   TC5 – Không kênh nào yêu cầu → grant = 0
//   TC6 – Kiểm tra không starvation: kênh sau cùng vẫn được phục vụ
// =============================================================================

// =============================================================================
// Testbench : tb_dma_arbiter
// Module    : dma_arbiter (Round Robin)
// Test cases:
//   TC1 - Chỉ 1 kênh yêu cầu → grant ngay cho kênh đó
//   TC2 - 2 kênh yêu cầu đồng thời → xoay vòng đúng thứ tự
//   TC3 - 4 kênh yêu cầu đồng thời → Round Robin quét đủ 4 kênh
//   TC4 - Con trỏ tiếp tục đúng sau khi kênh giải phóng
//   TC5 - Không kênh nào yêu cầu → grant = 0
//   TC6 - Kiểm tra không starvation: kênh sau cùng vẫn được phục vụ
// =============================================================================

`timescale 1ns / 1ps

module tb_dma_arbiter;

// ── DUT signals ──────────────────────────────────────────────────────────
    reg        clk, rst_n;
    reg  [3:0] req;
    wire [3:0] grant;
    wire       grant_valid;

// ── DUT ──────────────────────────────────────────────────────────────────
    dma_arbiter DUT (
        .clk(clk), .rst_n(rst_n),
        .req(req),
        .grant(grant),
        .grant_valid(grant_valid)
    );

// ── Clock 10 ns ──────────────────────────────────────────────────────────
    initial clk = 0;
    always #5 clk = ~clk;

    task reset_dut;
        begin
            rst_n = 0; req = 4'b0000;
            repeat(3) @(posedge clk); #1;
            rst_n = 1;
            @(posedge clk); #1;
        end
    endtask

    task tick(input integer n);
        begin
            repeat(n) @(posedge clk); #1;
        end
    endtask

    integer errors;

    initial begin
        $dumpfile("tb_dma_arbiter.vcd");
        $dumpvars(0, tb_dma_arbiter);
        errors = 0;

        // ══════════════════════════════════════════════════════════════════════
        // TC1: Chỉ 1 kênh yêu cầu
        // ══════════════════════════════════════════════════════════════════════
        $display("\n[TC1] Chi 1 kenh yeu cau");
        reset_dut;

        req = 4'b0001; tick(2);   // Chỉ CH0
        if (grant !== 4'b0001) begin
            $display("  FAIL: CH0 req -> grant expected 0001, got %b", grant);
            errors = errors + 1;
        end else $display("  PASS: CH0 -> grant = 0001");

        req = 4'b0000; tick(2);
        req = 4'b0100; tick(2);   // Chỉ CH2
        if (grant !== 4'b0100) begin
            $display("  FAIL: CH2 req -> grant expected 0100, got %b", grant);
            errors = errors + 1;
        end else $display("  PASS: CH2 -> grant = 0100");

        req = 4'b0000; tick(2);

        // ══════════════════════════════════════════════════════════════════════
        // TC2: 2 kênh yêu cầu đồng thời → xoay vòng
        // ══════════════════════════════════════════════════════════════════════
        $display("\n[TC2] 2 kenh yeu cau dong thoi: CH0 va CH2");
        reset_dut;

        req = 4'b0101;  // CH0 + CH2
        tick(1);
        $display("  Grant lan 1: %b", grant);

        begin : TC2_block // <--- SỬA LỖI: Đặt tên block cho TC2
            reg [3:0] first_grant;
            first_grant = grant;

            if (first_grant !== 4'b0001 && first_grant !== 4'b0100) begin
                $display("  FAIL: grant khong hop le: %b", first_grant);
                errors = errors + 1;
            end

            tick(1);
            // 1 chu ky → grant tiếp theo
            $display("  Grant lan 2: %b", grant);
            if (first_grant == 4'b0001 && grant !== 4'b0100) begin
                $display("  FAIL: sau CH0 phai la CH2, got %b", grant);
                errors = errors + 1;
            end else if (first_grant == 4'b0100 && grant !== 4'b0001) begin
                $display("  FAIL: sau CH2 phai la CH0, got %b", grant);
                errors = errors + 1;
            end else
                $display("  PASS: xoay vong dung: %b -> %b", first_grant, grant);
        end

        req = 4'b0000; tick(2);

        // ══════════════════════════════════════════════════════════════════════
        // TC3: 4 kênh yêu cầu đồng thời → Round Robin đủ 4 vòng
        // ══════════════════════════════════════════════════════════════════════
        $display("\n[TC3] 4 kenh yeu cau dong thoi -> Round Robin 4 vong");
        reset_dut;

        req = 4'b1111;  // Tất cả 4 kênh

        begin : TC3_block // <--- SỬA LỖI: Đặt tên block cho TC3
            reg [3:0] seen;
            reg [3:0] g;
            integer round;
            seen = 4'b0000;

            for (round = 0; round < 4; round = round + 1) begin
                tick(1);
                // 1 chu ky mỗi vòng
                g = grant;
                $display("  Vong %0d: grant = %b", round+1, g);
                if (g == 4'b0000) begin
                    $display("  FAIL: grant = 0 khi co request");
                    errors = errors + 1;
                end
                if (g != 4'b0001 && g != 4'b0010 && g != 4'b0100 && g != 4'b1000) begin
                    $display("  FAIL: grant khong phai one-hot: %b", g);
                    errors = errors + 1;
                end
                if (seen & g) begin
                    $display("  FAIL: kenh %b duoc grant 2 lan trong 4 vong", g);
                    errors = errors + 1;
                end
                seen = seen | g;
            end

            if (seen === 4'b1111)
                $display("  PASS: ca 4 kenh duoc phuc vu dung 1 lan");
            else begin
                $display("  FAIL: co kenh khong duoc phuc vu, seen = %b", seen);
                errors = errors + 1;
            end
        end

        req = 4'b0000;
        tick(2);

        // ══════════════════════════════════════════════════════════════════════
        // TC4: Con trỏ tiếp tục đúng sau khi kênh giải phóng
        // ══════════════════════════════════════════════════════════════════════
        $display("\n[TC4] Con tro tiep tuc sau khi kenh giai phong");
        reset_dut;

        // CH1 được grant, sau đó CH1 giải phóng, CH3 yêu cầu
        // Con trỏ phải ở CH2 sau khi CH1 xong → CH3 được phục vụ tiếp
        req = 4'b0010;
        tick(2);  // CH1
        if (grant !== 4'b0010) begin
            $display("  FAIL: CH1 expected");
            errors = errors + 1;
        end else $display("  CH1 grant OK");

        req = 4'b1000; tick(2);
        // CH1 xong, CH3 yêu cầu
        if (grant !== 4'b1000) begin
            $display("  FAIL: CH3 expected sau CH1 (next_ptr=2, quet den CH3)");
            errors = errors + 1;
        end else $display("  PASS: CH3 duoc grant dung sau CH1");

        req = 4'b0000; tick(2);

        // ══════════════════════════════════════════════════════════════════════
        // TC5: Không có kênh nào yêu cầu
        // ══════════════════════════════════════════════════════════════════════
        $display("\n[TC5] Khong co kenh yeu cau -> grant phai = 0");
        reset_dut;

        req = 4'b0000; tick(4);
        if (grant !== 4'b0000) begin
            $display("  FAIL: grant expected 0000, got %b", grant);
            errors = errors + 1;
        end else $display("  PASS: grant = 0000 khi khong co request");

        if (grant_valid !== 1'b0) begin
            $display("  FAIL: grant_valid expected 0");
            errors = errors + 1;
        end else $display("  PASS: grant_valid = 0");

        // ══════════════════════════════════════════════════════════════════════
        // TC6: Không starvation - CH3 luôn được phục vụ dù CH0 liên tục yêu cầu
        // ══════════════════════════════════════════════════════════════════════
        $display("\n[TC6] No starvation: CH0+CH3 yeu cau, CH3 phai duoc phuc vu");
        reset_dut;

        begin : TC6_block // <--- SỬA LỖI: Đặt tên block cho TC6
            integer ch3_served;
            integer cycle;
            ch3_served = 0;
            req = 4'b1001;  // CH0 + CH3 đồng thời
            for (cycle = 0; cycle < 8; cycle = cycle + 1) begin
                tick(2);
                if (grant === 4'b1000) ch3_served = ch3_served + 1;
            end

            $display("  CH3 duoc phuc vu %0d/4 vong", ch3_served);
            if (ch3_served == 0) begin
                $display("  FAIL: CH3 bi starvation (khong bao gio duoc grant)");
                errors = errors + 1;
            end else
                $display("  PASS: CH3 duoc phuc vu, khong co starvation");
        end

        // ── Kết quả ──────────────────────────────────────────────────────────
        $display("\n========================================");
        if (errors == 0)
            $display("  KET QUA: TAT CA TEST PASS [dma_arbiter]");
        else
            $display("  KET QUA: %0d TEST FAIL [dma_arbiter]", errors);
        $display("========================================\n");

        $finish;
    end

    initial begin #50000; $display("TIMEOUT"); $finish; end

endmodule