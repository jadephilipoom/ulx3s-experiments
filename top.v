module top(input wire clk_25mhz,
           input [6:0] btn,
           input ftdi_txd,
           output ftdi_rxd,
           output [7:0] led);

    assign i_clk = clk_25mhz;

    // Set up reset button.
    assign i_rst = btn[1];

    // Set up LED array.
    // - 0, 4: red
    // - 1, 5: orange
    // - 2, 6: green
    // - 3, 7: blue
    reg [7:0] o_led;
    assign led = o_led;

   // Set up basic state machine.
    localparam STATE_INIT = 2'd0; // Initializing; program not yet loaded.
    localparam STATE_EXEC = 2'd1; // Executing the program.
    localparam STATE_DONE = 2'd2; // Program exited (terminal state).
    reg [2:0] state = STATE_INIT;
    reg [2:0] next_state = STATE_INIT;

    // Error flags.
    localparam ERRBIT_CNT = 2'd0;  // Error from the cycle counter.
    localparam ERRBIT_SER = 2'd2;  // Error from the serial module.
    localparam ERRBIT_CPU = 2'd1;  // Error from the CPU module.
    localparam ERRBIT_MEM = 2'd3;  // Error from the memory module.
    reg [3:0] errs = 0;

    assign uart_rx_en = (state == STATE_INIT);
    wire [7:0] uart_rx_data;
    wire uart_rx_data_valid;
    wire uart_rx_err;
    uart_rx uart_rx(
        .i_clk(i_clk),
        .i_en(uart_rx_en),
        .i_rst(i_rst),
        .i_rx(ftdi_txd),
        .o_data(uart_rx_data),
        .o_data_valid(uart_rx_data_valid),
        .o_err(uart_rx_err),
    );

    assign uart_tx_en = (state == STATE_DONE);
    reg [7:0] uart_tx_data;
    reg uart_tx_data_valid;
    reg set_uart_tx_data_valid;
    reg clr_uart_tx_data_valid;
    wire uart_tx_ready;
    wire uart_tx_err;
    uart_tx uart_tx(
        .i_clk(i_clk),
        .i_en(uart_tx_en),
        .i_rst(i_rst),
        .i_data(uart_tx_data),
        .i_data_valid(uart_tx_data_valid),
        .o_tx(ftdi_rxd),
        .o_ready(uart_tx_ready),
        .o_err(uart_tx_err),
    );

    // Set up cycle counter.
    reg [63:0] cycle_count = 0;
    reg inc_cycle_count;
    reg cycle_count_err;
    localparam MAX_CYCLE_COUNT = 64'h3ffffff; // 64'hffffffffffffffff;

    // Set up memory.
    reg [31:0] loaded_bytes;
    reg load_mem_byte;
    localparam MEM_BYTES = 32'd32;
    reg [7:0] mem [0:MEM_BYTES-1];
    reg mem_read_err;
    reg mem_write_err;

    // CPU interface.
    assign cpu_en = (state == STATE_EXEC);
    reg [31:0] cpu_mem_rdata;
    reg cpu_mem_rdata_valid;
    reg cpu_readmem;
    reg cpu_writeback;
    wire [31:0] cpu_mem_wdata;
    wire cpu_mem_wdata_valid;
    wire cpu_mem_rdata_ready;
    wire [31:0] cpu_mem_raddr;
    wire [31:0] cpu_mem_waddr;
    wire [31:0] cpu_errs;
    wire [31:0] cpu_pc;
    reg [31:0] cpu_stop_pc; // Saves the final PC on exit.
    reg [31:0] cpu_errcode; // Saves the error code after a failure.
    reg cpu_done;
    cpu cpu(
        .i_clk(i_clk),
        .i_en(cpu_en),
        .i_rst(i_rst),
        .i_mem_rdata(cpu_mem_rdata),
        .i_mem_rdata_valid(cpu_mem_rdata_valid),
        .o_mem_wdata(cpu_mem_wdata),
        .o_mem_wdata_valid(cpu_mem_wdata_valid),
        .o_mem_rdata_ready(cpu_mem_rdata_ready),
        .o_mem_raddr(cpu_mem_raddr),
        .o_mem_waddr(cpu_mem_waddr),
        .o_pc(cpu_pc),
        .o_errs(cpu_errs),
        .o_done(cpu_done),
    );

    // Tracking for printing message at the end of exec. Cycle count is printed
    // in hex between prefix and suffix.
    reg [31:0] done_msg_bytes_sent;
    reg [7:0] done_msg_prefix_chars [0:16];
    reg [7:0] done_msg_suffix_chars [0:1];
    reg [6:0] cycle_count_bit_offset;
    reg decrement_bit_offset;
    reg clr_done_msg_bytes_sent;
    reg inc_done_msg_bytes_sent;
    initial begin
        done_msg_bytes_sent = 0;
        cycle_count_bit_offset = 6'd60;
        done_msg_prefix_chars[ 0] = 8'h64; // 'd'
        done_msg_prefix_chars[ 1] = 8'h6f; // 'o'
        done_msg_prefix_chars[ 2] = 8'h6e; // 'n'
        done_msg_prefix_chars[ 3] = 8'h65; // 'e'
        done_msg_prefix_chars[ 4] = 8'h21; // '!'
        done_msg_prefix_chars[ 5] = 8'h0d; // '\r'
        done_msg_prefix_chars[ 6] = 8'h0a; // '\n'
        done_msg_prefix_chars[ 7] = 8'h63; // 'c'
        done_msg_prefix_chars[ 8] = 8'h79; // 'y'
        done_msg_prefix_chars[ 9] = 8'h63; // 'c'
        done_msg_prefix_chars[10] = 8'h6c; // 'l'
        done_msg_prefix_chars[11] = 8'h65; // 'e'
        done_msg_prefix_chars[12] = 8'h73; // 's'
        done_msg_prefix_chars[13] = 8'h3a; // ':'
        done_msg_prefix_chars[14] = 8'h20; // ' '
        done_msg_prefix_chars[15] = 8'h30; // '0'
        done_msg_prefix_chars[16] = 8'h78; // 'x'

        done_msg_suffix_chars[ 0] = 8'h0d; // '\r'
        done_msg_suffix_chars[ 1] = 8'h0a; // '\n'
    end

    // Tracking for printing the memdump.
    reg [31:0] memdump_line_offset;
    reg [31:0] memdump_byte_offset;
    reg inc_memdump_byte_offset;
    reg inc_memdump_line_offset;
    reg clr_memdump_byte_offset;
    reg clr_memdump_line_offset;

    // Tracking for printing the error code.
    reg [31:0] errcode_msg_byte_offset;
    reg inc_errcode_msg_byte_offset;
    reg clr_errcode_msg_byte_offset;

    // Tracking for printing the PC.
    reg [31:0] stop_pc_msg_byte_offset;
    reg inc_stop_pc_msg_byte_offset;
    reg clr_stop_pc_msg_byte_offset;

    // Function for converting a nibble to ASCII hex.
    function [7:0] ascii_hex_nibble(input [3:0] n);
        begin
            ascii_hex_nibble = ((n < 4'd10) ? 8'h30 : 8'h57) + {4'd0, n};
        end
    endfunction

    // This section takes in state and produces logic output that will be
    // consumed by the sequential section below. Variables should not be
    // updated in any other blocks.
    always @(*) begin
        // Because this block uses blocking operations, we can set a bunch of
        // default values in the beginning and override them conditionally
        // later.
        o_led[7:0] = 0;
        decrement_bit_offset = 0;
        load_mem_byte = 0;
        clr_done_msg_bytes_sent = 0;
        inc_done_msg_bytes_sent = 0;
        set_uart_tx_data_valid = 0;
        clr_uart_tx_data_valid = 0;
        inc_cycle_count = 0;
        clr_memdump_byte_offset = 0;
        clr_memdump_line_offset = 0;
        inc_memdump_byte_offset = 0;
        inc_memdump_line_offset = 0;
        clr_errcode_msg_byte_offset = 0;
        inc_errcode_msg_byte_offset = 0;
        clr_stop_pc_msg_byte_offset = 0;
        inc_stop_pc_msg_byte_offset = 0;
        cpu_readmem = 0;
        cpu_writeback = 0;
        cycle_count_err = 0;
        mem_read_err = 0;
        mem_write_err = 0;
        uart_tx_data = 0;
        next_state = state;
        case(state)
            STATE_INIT: begin
                o_led[1] = 1;
                clr_uart_tx_data_valid = 1;

                // If we got all the bytes we need, transition to the exec state.
                if (loaded_bytes >= MEM_BYTES) begin
                    next_state = STATE_EXEC;
                end else if (uart_rx_en && uart_rx_data_valid) begin
                    // If a new byte is ready from the serial receiver, write
                    // it into memory.
                    load_mem_byte = 1;
                end
            end
            STATE_EXEC: begin
                o_led[3] = 1;
                inc_cycle_count = 1;

                // Send data from memory to CPU.
                if (cpu_en && cpu_mem_rdata_ready) begin
                    if (cpu_mem_raddr < MEM_BYTES && (cpu_mem_raddr % 4 == 0)) begin
                        cpu_readmem = 1;
                    end else begin
                        mem_read_err = 1;
                    end
                end

                // Send data from CPU to memory.
                if (cpu_en && cpu_mem_wdata_valid) begin
                    if (cpu_mem_waddr < MEM_BYTES && (cpu_mem_waddr % 4 == 0)) begin
                        cpu_writeback = 1;
                    end else begin
                        mem_write_err = 1;
                    end
                end

                // Check if the cycle counter will overflow.
                if (cycle_count == MAX_CYCLE_COUNT) begin
                    cycle_count_err = 1;
                end

                // If the CPU is done, transition to the done state and print a message.
                if (cpu_en && cpu_done) begin
                    next_state = STATE_DONE;
                    uart_tx_data = done_msg_prefix_chars[0];
                    set_uart_tx_data_valid = 1;
                    clr_done_msg_bytes_sent = 1;
                end
            end
            STATE_DONE: begin
                o_led[0] = (errs != 0); // Red LED on if errors.
                o_led[2] = (errs == 0); // Green LED on if no errors.
                // Set additional LEDs to error flags.
                o_led[4] = errs[0];
                o_led[5] = errs[1];
                o_led[6] = errs[2];
                o_led[7] = errs[3];
                // If the UART transmitter is ready and there is still
                // something to print from the "done" message or memdump, then
                // send the next byte.
                if (uart_tx_ready && uart_tx_data_valid && (btn[6:1] == 0)) begin
                    inc_done_msg_bytes_sent = 1;
                    // Done message and cycle count
                    if (done_msg_bytes_sent < 17) begin
                        uart_tx_data = done_msg_prefix_chars[done_msg_bytes_sent];
                    end else if (done_msg_bytes_sent < 33) begin
                        uart_tx_data = ascii_hex_nibble(cycle_count[cycle_count_bit_offset +: 4]);
                        decrement_bit_offset = 1;
                    end else if (done_msg_bytes_sent < 35) begin
                        uart_tx_data = done_msg_suffix_chars[done_msg_bytes_sent - 33];
                    end else if (stop_pc_msg_byte_offset < 15) begin
                        inc_stop_pc_msg_byte_offset = 1;
                        if (stop_pc_msg_byte_offset == 0) begin
                            uart_tx_data = 8'h70; // 'p'
                        end else if (stop_pc_msg_byte_offset == 1) begin
                            uart_tx_data = 8'h63; // 'c'
                        end else if (stop_pc_msg_byte_offset == 2) begin
                            uart_tx_data = 8'h3a; // ':'
                        end else if (stop_pc_msg_byte_offset == 3) begin
                            uart_tx_data = 8'h20; // ' '
                        end else if (stop_pc_msg_byte_offset == 4) begin
                            uart_tx_data = 8'h30; // '0'
                        end else if (stop_pc_msg_byte_offset == 5) begin
                            uart_tx_data = 8'h78; // 'x'
                        end else if (stop_pc_msg_byte_offset < 13) begin
                            uart_tx_data = ascii_hex_nibble(cpu_stop_pc[(28 - (stop_pc_msg_byte_offset - 13)*4) +: 4]);
                        end else if (stop_pc_msg_byte_offset == 13) begin
                            uart_tx_data = 8'h0d; // '\r'
                        end else if (stop_pc_msg_byte_offset == 14) begin
                            uart_tx_data = 8'h0a; // '\n'
                        end else begin
                            // Shouldn't get here but if we do make it visible by printing -
                            uart_tx_data = 8'h2d; // '-'
                        end
                    end else if (errcode_msg_byte_offset < 18) begin
                        inc_errcode_msg_byte_offset = 1;
                        if (errcode_msg_byte_offset == 0) begin
                            uart_tx_data = 8'h65; // 'e'
                        end else if (errcode_msg_byte_offset == 1) begin
                            uart_tx_data = 8'h72; // 'r'
                        end else if (errcode_msg_byte_offset == 2) begin
                            uart_tx_data = 8'h72; // 'r'
                        end else if (errcode_msg_byte_offset == 3) begin
                            uart_tx_data = 8'h63; // 'c'
                        end else if (errcode_msg_byte_offset == 4) begin
                            uart_tx_data = 8'h6f; // 'o'
                        end else if (errcode_msg_byte_offset == 5) begin
                            uart_tx_data = 8'h64; // 'd'
                        end else if (errcode_msg_byte_offset == 6) begin
                            uart_tx_data = 8'h65; // 'e'
                        end else if (errcode_msg_byte_offset == 7) begin
                            uart_tx_data = 8'h3a; // ':'
                        end else if (errcode_msg_byte_offset == 8) begin
                            uart_tx_data = 8'h20; // ' '
                        end else if (errcode_msg_byte_offset < 16) begin
                            uart_tx_data = ascii_hex_nibble(cpu_errcode[(28 - (errcode_msg_byte_offset - 16)*4) +: 4]);
                        end else if (errcode_msg_byte_offset == 16) begin
                            uart_tx_data = 8'h0d; // '\r'
                        end else if (errcode_msg_byte_offset == 17) begin
                            uart_tx_data = 8'h0a; // '\n'
                        end else begin
                            // Shouldn't get here but if we do make it visible by printing -
                            uart_tx_data = 8'h2d; // '-'
                        end
                    end else if (memdump_byte_offset < MEM_BYTES || (memdump_byte_offset == MEM_BYTES && (memdump_line_offset != 0))) begin
                        inc_memdump_line_offset = 1;
                        if (memdump_line_offset < 4) begin
                            // Print a byte of the address.
                            uart_tx_data = ascii_hex_nibble(memdump_byte_offset[(12 - memdump_line_offset*4) +: 4]);
                        end else if (memdump_line_offset == 4) begin
                            uart_tx_data = 8'h20; // ' '
                        end else if (memdump_line_offset == 5) begin
                            uart_tx_data = 8'h7c; // '|'
                        end else if (memdump_line_offset == 6) begin
                            uart_tx_data = 8'h20; // ' '
                        end else if (memdump_line_offset < 15) begin
                            if (memdump_line_offset & 1'd1) begin
                                uart_tx_data = ascii_hex_nibble(mem[memdump_byte_offset][7:4]);
                            end else begin
                                uart_tx_data = ascii_hex_nibble(mem[memdump_byte_offset][3:0]);
                                inc_memdump_byte_offset = 1;
                            end
                        end else if (memdump_line_offset == 15) begin
                            uart_tx_data = 8'h0d; // '\r'
                        end else if (memdump_line_offset == 16) begin
                            uart_tx_data = 8'h0a; // '\n'
                            clr_memdump_line_offset = 1;
                        end else begin
                            // Shouldn't get here but if we do make it visible by printing -
                            uart_tx_data = 8'h2d; // '-'
                            clr_memdump_line_offset = 1;
                        end
                    end else begin
                        clr_uart_tx_data_valid = 1;
                    end
                end

                // Restart memdump on button press.
                if (btn[2]) begin
                    clr_memdump_byte_offset = 1;
                    clr_memdump_line_offset = 1;
                    set_uart_tx_data_valid = 1;
                    clr_uart_tx_data_valid = 0;
                end

                // Restart PC & errcode print on button press.
                if (btn[3]) begin
                    clr_stop_pc_msg_byte_offset = 1;
                    clr_errcode_msg_byte_offset = 1;
                    set_uart_tx_data_valid = 1;
                    clr_uart_tx_data_valid = 0;
                end
            end
        endcase
    end

    // Main state machine. This triggers on every clock edge, and observes all the blocking operations
    // computed in the combinational state above, and stores them in registers, so that the next round
    // of combinational logic has fresh inputs.
    always @(posedge i_clk) begin
        // Update error bits.
        errs[ERRBIT_CNT] <= errs[ERRBIT_CNT] || (inc_cycle_count && cycle_count_err);
        errs[ERRBIT_SER] <= errs[ERRBIT_SER] || ((uart_rx_en && uart_rx_err) || (uart_tx_en && uart_tx_err));
        errs[ERRBIT_CPU] <= errs[ERRBIT_CPU] || (cpu_en && (cpu_errs != 0));
        errs[ERRBIT_MEM] <= errs[ERRBIT_MEM] || (mem_read_err || mem_write_err);

        // Check for errors or reset that would intercept the state change.
        // "ASIC ready" code would put all the reset clauses in this first "if" block - because
        // this would allow you to do e.g. `negedge rst_n` triggered async clear, making a clear
        // inference to a particular type of register. Unfortunately, FPGAs don't support this, and
        // so you have this constant tension between FPGA-ready code and ASIC-ready code. This style
        // is very much FPGA-ready.
        if (i_rst) begin
            state <= STATE_INIT;
            errs <= 0;
            loaded_bytes <= 0;
            done_msg_bytes_sent <= 0;
            cycle_count_bit_offset <= 6'd60;
            cycle_count <= 0;
            memdump_byte_offset <= 0;
            memdump_line_offset <= 0;
            stop_pc_msg_byte_offset <= 0;
            errcode_msg_byte_offset <= 0;
            cpu_mem_rdata_valid <= 0;
            cpu_errcode <= 0;
            cpu_stop_pc <= 0;
        end else begin
            if (errs) begin
                state <= STATE_DONE;
            end else begin
                state <= next_state;
                if (inc_cycle_count) begin
                    cycle_count <= cycle_count + 1;
                end
                if (load_mem_byte) begin
                    mem[loaded_bytes] <= uart_rx_data;
                    loaded_bytes <= loaded_bytes + 1;
                end
                if (cpu_readmem) begin
                    cpu_mem_rdata[ 7: 0] <= mem[cpu_mem_raddr];
                    cpu_mem_rdata[15: 8] <= mem[cpu_mem_raddr + 1];
                    cpu_mem_rdata[23:16] <= mem[cpu_mem_raddr + 2];
                    cpu_mem_rdata[31:24] <= mem[cpu_mem_raddr + 3];
                    cpu_mem_rdata_valid <= 1;
                end
                if (cpu_writeback) begin
                    mem[cpu_mem_waddr + 0] <= cpu_mem_wdata[ 7: 0];
                    mem[cpu_mem_waddr + 1] <= cpu_mem_wdata[15: 8];
                    mem[cpu_mem_waddr + 2] <= cpu_mem_wdata[23:16];
                    mem[cpu_mem_waddr + 3] <= cpu_mem_wdata[31:24];
                end
                if (cpu_errs != 0) begin
                    cpu_errcode <= cpu_errs;
                end
                if (cpu_en && cpu_done) begin
                    cpu_stop_pc <= cpu_pc;
                end
            end

            // Printing logic happens regardless of errors.
            if (decrement_bit_offset) begin
                cycle_count_bit_offset <= cycle_count_bit_offset - 4;
            end
            if (clr_done_msg_bytes_sent) begin
                done_msg_bytes_sent <= 0;
            end else if (inc_done_msg_bytes_sent) begin
                done_msg_bytes_sent <= done_msg_bytes_sent + 1;
            end
            // Give reset and clear precedence over set.
            if (i_rst || clr_uart_tx_data_valid) begin
                uart_tx_data_valid <= 0;
            end else if (set_uart_tx_data_valid) begin
                uart_tx_data_valid <= 1;
            end
            if (i_rst || clr_memdump_line_offset) begin
                memdump_line_offset <= 0;
            end else if (inc_memdump_line_offset) begin
                memdump_line_offset <= memdump_line_offset + 1;
            end
            if (i_rst || clr_memdump_byte_offset) begin
                memdump_byte_offset <= 0;
            end if (inc_memdump_byte_offset) begin
                memdump_byte_offset <= memdump_byte_offset + 1;
            end
            if (i_rst || clr_errcode_msg_byte_offset) begin
                errcode_msg_byte_offset <= 0;
            end if (inc_errcode_msg_byte_offset) begin
                errcode_msg_byte_offset <= errcode_msg_byte_offset + 1;
            end
            if (i_rst || clr_stop_pc_msg_byte_offset) begin
                stop_pc_msg_byte_offset <= 0;
            end if (inc_stop_pc_msg_byte_offset) begin
                stop_pc_msg_byte_offset <= stop_pc_msg_byte_offset + 1;
            end
        end

    end

endmodule

module uart_rx(input wire i_clk,
               input wire i_en,
               input wire i_rst,
               input wire i_rx,
               output [7:0] o_data,
               output wire o_data_valid,
               output wire o_err);

    localparam STATE_WAIT = 2'd0; // Waiting for start bit.
    localparam STATE_READ = 2'd1; // Reading data.
    reg [1:0] state = STATE_WAIT;

    reg [7:0] recv_data;
    reg [3:0] recv_bits;
    reg [31:0] delay_count; // Cycles to wait before next bit
    reg err;

    // Baud rate 115200, clock 25MHz
    localparam HOLD_CYCLES = 25000000 / 115200;
    localparam DELAY_CYCLES = HOLD_CYCLES / 2; // Read from the middle

    assign o_data = recv_data;
    assign o_data_valid = (state == STATE_READ && recv_bits == 8 && delay_count == 0);
    assign o_err = err;

    always @(posedge i_clk) begin
        if (i_rst) begin
            state <= STATE_WAIT;
            recv_data <= 0;
            recv_bits <= 0;
            delay_count <= 0;
            err <= 0;
        end else if (i_en) begin
            case (state)

                STATE_WAIT: begin
                    // If we hear a 0, transition to the read state.
                    if (!i_rx) begin
                        recv_data <= 0;
                        recv_bits <= 0;
                        delay_count <= HOLD_CYCLES + DELAY_CYCLES;
                        state <= STATE_READ;
                    end
                end

                STATE_READ: begin
                    if (delay_count == 0) begin
                        if (recv_bits == 8) begin
                            state <= STATE_WAIT;
                            // Report an error if the stop bit is not high as expected.
                            err <= !i_rx;
                        end else begin
                            recv_data <= { i_rx, recv_data[7:1] };
                            recv_bits <= recv_bits + 1;
                            delay_count <= HOLD_CYCLES;
                        end
                    end
                    else begin
                        delay_count <= delay_count - 1;
                    end
                end

            endcase
        end
    end

endmodule

module uart_tx(input wire i_clk,
               input wire i_en,
               input wire i_rst,
               input [7:0] i_data,
               input wire i_data_valid,
               output wire o_tx,
               output wire o_ready,
               output reg o_err);

    localparam STATE_WAIT = 2'd0;
    localparam STATE_SEND = 2'd1;
    localparam STATE_SPACE = 2'd2;
    reg [1:0] state = STATE_WAIT;

    reg [9:0] send_data = ~0;
    reg [3:0] send_bits;
    reg [31:0] send_hold;

    // Baud rate 115200, clock 25MHz
    localparam HOLD_CYCLES = 25000000 / 115200;

    // Cycles to idle high in between bytes (helps avoid timing getting out of
    // sync).
    localparam SPACE_CYCLES = HOLD_CYCLES / 2;

    assign o_tx = send_data[0];
    assign o_ready = state == STATE_WAIT;

    always @(posedge i_clk) begin
        if (i_rst) begin
            state <= STATE_WAIT;
            send_data <= ~0;
            o_err <= 0;
        end else if (i_en) begin
            o_err <= 0;
            case (state)

                STATE_WAIT: begin
                    if (i_data_valid) begin
                        send_data <= { 1'b1, i_data, 1'b0 };
                        send_bits <= 10;
                        send_hold <= HOLD_CYCLES;
                        state <= STATE_SEND;
                    end else begin
                        send_data <= ~0;
                    end
                end

                STATE_SEND: begin
                    if (send_hold == 0) begin
                        if (send_bits == 0) begin
                            send_data <= ~0;
                            state <= STATE_SPACE;
                            send_hold <= SPACE_CYCLES;
                        end else begin
                            send_data <= { 1'b1, send_data[9:1] };
                            send_bits <= send_bits - 1;
                            send_hold <= HOLD_CYCLES;
                        end
                    end
                    else begin
                        send_hold <= send_hold - 1;
                    end
                end

                STATE_SPACE: begin
                    if (send_hold == 0) begin
                        state <= STATE_WAIT;
                    end else begin
                        send_hold <= send_hold - 1;
                    end
                end

            endcase
        end
    end

endmodule

module cpu(input wire i_clk,
           input wire i_en,
           input wire i_rst,
           input [31:0] i_mem_rdata,
           input i_mem_rdata_valid,
           output [31:0] o_mem_wdata,
           output o_mem_wdata_valid,
           output o_mem_rdata_ready,
           output [31:0] o_mem_raddr,
           output [31:0] o_mem_waddr,
           output [31:0] o_pc,
           output [31:0] o_errs,
           output o_done);

    localparam STATE_FETCH = 3'd0;
    localparam STATE_DCODE = 3'd1;
    localparam STATE_EXEC = 3'd2;
    localparam STATE_DONE = 3'd3;
    reg [2:0] state = STATE_FETCH;
    reg [2:0] next_state;

    reg [31:0] pc;
    reg [31:0] insn;
    reg [31:0] rf [0:15];
    reg inc_pc;
    reg read_insn;

    // Error code format:
    // - bits [7:0] hold the error flags
    // - bits [31:8] hold additional info (e.g. the opcode that was invalid)
    localparam ERRBIT_INVALID_OPCODE = 32'd0;
    localparam ERRBIT_INVALID_REG = 32'd1;
    reg err_invalid_opcode;
    reg err_invalid_reg;
    reg [31:0] errcode;

    reg [31:0] mem_raddr;
    reg [31:0] mem_waddr;
    reg [31:0] mem_wdata;
    reg mem_wdata_valid;

    assign o_done = (state == STATE_DONE);
    assign o_errs = errcode;
    assign o_pc = pc;
    assign o_mem_raddr = (state == STATE_FETCH) ? pc : mem_raddr;
    assign o_mem_waddr = mem_waddr;
    assign o_mem_rdata_ready = (state == STATE_FETCH);
    assign o_mem_wdata = mem_wdata;
    assign o_mem_wdata_valid = mem_wdata_valid;

    always @(*) begin
        next_state = state;
        mem_raddr = 0;
        mem_waddr = 0;
        mem_wdata = 0;
        mem_wdata_valid = 0;
        read_insn = 0;
        inc_pc = 0;
        err_invalid_opcode = 0;
        err_invalid_reg = 0;
        case (state)
            
            STATE_FETCH: begin
                if (i_mem_rdata_valid) begin
                    read_insn = 1;
                    next_state = STATE_DCODE;
                end
            end

            STATE_DCODE: begin
                next_state = STATE_EXEC;
                // Case split on opcode
                case (insn[6:0])

                    // ADD
                    7'b0110011: begin
                        // TODO
                    end

                    // LW
                    7'b0000011: begin
                        // TODO
                    end

                    // SW
                    7'b0100011: begin
                        // TODO
                    end

                    // ECALL
                    7'b1110011: begin
                        next_state = STATE_DONE;
                    end

                    default: begin
                        err_invalid_opcode = 1;
                    end
                endcase
            end

            STATE_EXEC: begin
                // TODO
                inc_pc = 1;
                next_state = STATE_FETCH;
            end

            STATE_DONE: begin
            end
        endcase
    end

    always @(posedge i_clk) begin
        if (i_rst) begin
            state <= STATE_FETCH;
            errcode <= 0;
            pc <= 0; 
            mem_raddr <= 0;
            mem_waddr <= 0;
            mem_wdata_valid <= 0;
            rf[0] <= 0;
            rf[1] <= 0;
            rf[2] <= 0;
            rf[3] <= 0;
            rf[4] <= 0;
            rf[5] <= 0;
            rf[6] <= 0;
            rf[7] <= 0;
            rf[8] <= 0;
            rf[9] <= 0;
            rf[10] <= 0;
            rf[11] <= 0;
            rf[12] <= 0;
            rf[13] <= 0;
            rf[14] <= 0;
            rf[15] <= 0;
        end else if (i_en) begin
            // Update error flags.
            errcode[ERRBIT_INVALID_OPCODE] <= errcode[ERRBIT_INVALID_OPCODE] || err_invalid_opcode;
            errcode[ERRBIT_INVALID_REG] <= errcode[ERRBIT_INVALID_REG] || err_invalid_reg;

            // Write additional info to the error code.
            if (err_invalid_opcode) begin
                errcode[14:8] <= insn[6:0];
            end else if (err_invalid_reg) begin
                errcode[31:8] <= ~0;
            end

            if (errcode != 0) begin
                state <= STATE_DONE;
            end else begin
                state <= next_state;
                if (read_insn) begin
                    insn <= i_mem_rdata;
                end
                if (inc_pc) begin
                    pc <= pc + 4;
                end
            end
        end
    end

endmodule
