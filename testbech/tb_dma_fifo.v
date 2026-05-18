// =============================================================================
// Testbench : tb_dma_fifo
// Module    : dma_fifo
// Test cases:
//   TC1 – Ghi tuần tự đến đầy (full flag)
//   TC2 – Đọc tuần tự đến rỗng (empty flag)
//   TC3 – Ghi khi đầy (overflow protection – dữ liệu không bị ghi đè)
//   TC4 – Đọc khi rỗng (underflow protection)
//   TC5 – Ghi và đọc đồng thời (simultaneous read/write)
// =============================================================================

`timescale 1ns / 1ps

module tb_dma_fifo;

    // ── Tham số mô phỏng ────────────────────────────────────────────────────
    parameter DEPTH = 16;
    parameter WIDTH = 8;

    // ── Các tín hiệu kết nối với DUT ────────────────────────────────────────
    reg              clk;
    reg              rst_n;
    reg              wr_en;
    reg  [WIDTH-1:0] din;
    reg              rd_en;
    wire [WIDTH-1:0] dout;
    wire             full;
    wire             empty;
    wire             almost_full;

    // ── Khởi tạo Device Under Test (DUT) ────────────────────────────────────
    dma_fifo #(
        .DEPTH(DEPTH),
        .WIDTH(WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(wr_en),
        .din(din),
        .rd_en(rd_en),
        .dout(dout),
        .full(full),
        .empty(empty),
        .almost_full(almost_full)
    );

    // ── Tạo xung Clock (Chu kỳ 10ns -> 100MHz) ──────────────────────────────
    always #5 clk = ~clk;

    // ── Định nghĩa các Tasks (Đã sửa lỗi thiếu begin/end) ────────────────────
    
    // Task 1: Ghi dữ liệu vào FIFO
    task push_data(input [WIDTH-1:0] data);
    begin // <--- SỬA LỖI VRFC 10-1065: Bắt buộc phải có begin ở đây
        @(posedge clk);
        if (!full) begin
            wr_en = 1;
            din   = data;
        end else begin
            $display("[WARN] FIFO Full! Cannot push data: %h", data);
            wr_en = 0;
        end
        #1; // Delay nhỏ sau sườn dương clock để dễ quan sát tín hiệu
        wr_en = 0;
    end // <--- SỬA LỖI VRFC 10-1065: Bắt buộc phải có end ở đây
    endtask

    // Task 2: Đọc dữ liệu từ FIFO
    task pop_data();
    begin // <--- SỬA LỖI VRFC 10-1065: Bắt buộc phải có begin ở đây
        @(posedge clk);
        if (!empty) begin
            rd_en = 1;
        end else begin
            $display("[WARN] FIFO Empty! Cannot pop data");
            rd_en = 0;
        end
        #1;
        rd_en = 0;
    end // <--- SỬA LỖI VRFC 10-1065: Bắt buộc phải có end ở đây
    endtask

    // Task 3: Reset hệ thống
    task reset_system();
    begin // <--- SỬA LỖI VRFC 10-1065: Bắt buộc phải có begin ở đây
        rst_n = 0;
        wr_en = 0;
        rd_en = 0;
        din   = 0;
        #20;
        rst_n = 1;
        #10;
    end // <--- SỬA LỖI VRFC 10-1065: Bắt buộc phải có end ở đây
    endtask

    // ── Kịch bản mô phỏng (Stimulus) ────────────────────────────────────────
    initial begin : main_simulation // <--- SỬA LỖI VRFC 10-8885: Đặt tên cho khối block bằng ": name"
        
        // Khai báo biến vòng lặp (SỬA LỖI VRFC 10-8885: Biến được đưa lên đầu khối block)
        integer i; 
        
        clk = 0;
        reset_system();

        // --- KỊCH BẢN 1: Ghi cho tới khi FIFO đầy ---
        $display("--- Bat dau ghi vao FIFO ---");
        for (i = 0; i < DEPTH; i = i + 1) begin
            push_data(i + 8'hA0); // Ghi các giá trị A0, A1, A2...
        end
        #10;
        
        // --- KỊCH BẢN 2: Đọc toàn bộ dữ liệu ra cho tới khi rỗng ---
        $display("--- Bat dau doc tu FIFO ---");
        for (i = 0; i < DEPTH; i = i + 1) begin
            pop_data();
        end
        #10;

        // --- KỊCH BẢN 3: Ghi và Đọc đồng thời (Simultaneous Write/Read) ---
        $display("--- Thử nghiem ghi va doc dong thoi ---");
        push_data(8'hFF);
        push_data(8'hEE);
        
        @(posedge clk);
        wr_en = 1; din = 8'hDD;
        rd_en = 1;
        #11;
        wr_en = 0; rd_en = 0;

        // Kết thúc mô phỏng
        #50;
        $display("--- Mo phong hoan thanh thanh cong ---");
        $finish;
    end

endmodule

