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
    localparam STATE_DONE = 2'd2; // Program exited successfully (terminal state).
    localparam STATE_ERRS = 2'd3; // Crashed due to failures (terminal state).
    reg [1:0] state = STATE_INIT;
    reg [1:0] next_state = STATE_INIT;

    // Error flags.
    localparam ERRBIT_CNT = 0;  // Error from the cycle counter.
    localparam ERRBIT_SER = 2;  // Error from the serial module.
    localparam ERRBIT_CPU = 1;  // Error from the CPU module.
    localparam ERRBIT_MEM = 3;  // Error from the memory module.
    reg [3:0] errs = 0;

    // FIFO for data to send via serial.
    localparam UART_TX_FIFO_DEPTH = 64;
    reg [7:0] uart_tx_fifo [0:UART_TX_FIFO_DEPTH];
    reg [6:0] uart_tx_fifo_bytelength = 0;
    reg [5:0] uart_tx_fifo_offset = 0;

    assign uart_rx_en = (state == STATE_INIT);
    reg [7:0] uart_rx_data;
    reg uart_rx_data_valid;
    reg uart_rx_done;
    reg uart_rx_err;
    uart_rx uart_rx(
        .i_clk(i_clk),
        .i_en(uart_rx_en),
        .i_rst(i_rst),
        .i_rx(ftdi_txd),
        .o_data(uart_rx_data),
        .o_data_valid(uart_rx_data_valid),
        .o_done(uart_rx_done),
        .o_err(uart_rx_err),
    );

    assign uart_tx_en = (state == STATE_DONE);
    reg [7:0] uart_tx_data;
    reg uart_tx_data_valid;
    reg uart_tx_ready;
    reg uart_tx_err;
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

    assign cpu_en = (state == STATE_EXEC);
    reg cpu_done;
    reg cpu_err;
    cpu cpu(
        .i_clk(i_clk),
        .i_en(cpu_en),
        .i_rst(i_rst),
        .o_err(cpu_err),
        .o_done(cpu_done),
    );

    wire [63:0] cycle_count;
    assign cycle_counter_en = (state == STATE_EXEC);
    reg cycle_counter_err;
    cycle_counter cycle_counter(
        .i_clk(i_clk),
        .i_en(cycle_counter_en),
        .o_count(cycle_count),
        .o_err(cycle_counter_err),
    );

    // Tracking for printing message at the end of exec. Cycle count is printed
    // in hex between prefix and suffix.
    reg [31:0] done_msg_bytes_sent;
    reg [7:0] done_msg_prefix_chars [0:16];
    reg [7:0] done_msg_suffix_chars [0:1];
    reg [6:0] cycle_count_bit_offset;
    initial begin
        done_msg_bytes_sent = 0;
        uart_tx_data_valid = 0;
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

    // Function for converting a nibble to ASCII hex.
    function [7:0] ascii_hex_nibble(input [3:0] n);
        begin
            ascii_hex_nibble = ((n < 4'd10) ? 8'h30 : 8'h57) + {4'd0, n};
        end
    endfunction

    // Main state machine.
    always @(posedge i_clk) begin
          o_led[7:0] = 0;
          case (state)

                STATE_INIT: begin
                    o_led[1] = 1; // orange led for init
                    uart_tx_data_valid <= 0;

                    // If the serial receiver is done, transition to the exec state.
                    if (uart_rx_en && uart_rx_done) begin
                        next_state <= STATE_EXEC;
                    end
                end

                STATE_EXEC: begin
                    o_led[3] = 1; // blue led for exec

                    // If the CPU is done, transition to the done state and print a message.
                    if (cpu_en && cpu_done) begin
                        next_state <= STATE_DONE;
                        uart_tx_data <= done_msg_prefix_chars[0];
                        uart_tx_data_valid <= 1;
                        done_msg_bytes_sent <= 1;
                    end
                end

                STATE_DONE: begin
                    o_led[2] = 1; // green led for done

                    // If the UART transmitter is ready and there is still
                    // something to print, send the next byte.
                    if (uart_tx_ready && uart_tx_data_valid) begin
                        if (done_msg_bytes_sent < 17) begin
                            uart_tx_data <= done_msg_prefix_chars[done_msg_bytes_sent];
                        end else if (done_msg_bytes_sent < 33) begin
                            // uart_tx_data <= ascii_hex_nibble(cycle_count[cycle_count_bit_offset+3:cycle_count_bit_offset]);
                            uart_tx_data <= "0" + cycle_count[cycle_count_bit_offset+3:cycle_count_bit_offset];
                            cycle_count_bit_offset <= cycle_count_bit_offset - 4;
                        end else if (done_msg_bytes_sent < 35) begin
                            uart_tx_data <= done_msg_suffix_chars[done_msg_bytes_sent - 33];
                        end else begin
                            uart_tx_data_valid <= 0;
                        end
                        done_msg_bytes_sent <= done_msg_bytes_sent + 1;
                    end
                end

                STATE_ERRS: begin
                    o_led[0] = 1; // red led for errors
                    uart_tx_data_valid <= 0;
                    uart_tx_fifo_bytelength <= 0;

                    // Set additional LEDs to error flags.
                    o_led[4] = errs[0];
                    o_led[5] = errs[1];
                    o_led[6] = errs[2];
                    o_led[7] = errs[3];
                end

        endcase

        // Update error bits.
        errs[ERRBIT_CNT] <= errs[ERRBIT_CNT] || (cycle_counter_en && cycle_counter_err);
        errs[ERRBIT_SER] <= errs[ERRBIT_SER] || ((uart_rx_en && uart_rx_err) || (uart_tx_en && uart_tx_err));
        errs[ERRBIT_CPU] <= errs[ERRBIT_CPU] || (cpu_en && cpu_err);
        errs[ERRBIT_MEM] <= errs[ERRBIT_MEM] || 0; // TODO

        // Check for errors or reset that would intercept the state change.
        if (i_rst) begin
            state <= STATE_INIT;
            next_state <= STATE_INIT;
            errs <= 0;
            uart_tx_fifo_bytelength <= 0;
            uart_tx_fifo_offset <= 0;
            done_msg_bytes_sent <= 0;
            cycle_count_bit_offset <= 6'd60;
        end else if (errs) begin
            state <= STATE_ERRS;
            next_state <= STATE_ERRS;
        end else begin
            state <= next_state;
        end

    end

endmodule

module uart_rx(input wire i_clk,
               input wire i_en,
               input wire i_rst,
               input wire i_rx,
               output [7:0] o_data,
               output o_data_valid,
               output o_done,
               output o_err);

    localparam STATE_WAIT = 2'd0; // Waiting for start sequence.
    localparam STATE_READ = 2'd1; // Reading data until end sequence.
    reg [2:0] state = STATE_WAIT;

    // TODO: remove
    reg [24:0] cycle_count = 0;
    localparam DELAY = 25'h1ffffff;

    always @(posedge i_clk) begin
        if (i_rst) begin
            cycle_count <= 0;
            state <= STATE_WAIT;
            o_data_valid <= 0;
            o_done <= 0;
            o_err <= 0;
        end else if (i_en) begin
            o_data_valid = 0;
            o_err = 0;
            o_done = 0;
            cycle_count <= cycle_count + 1;
            if (cycle_count >= DELAY) begin
                o_done = 1;
            end
            case (state)

                STATE_WAIT: begin
                    // TODO: listen for start
                end

                STATE_READ: begin
                    // TODO: listen for end
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
               output wire o_err);

    localparam STATE_WAIT = 1'd0;
    localparam STATE_SEND = 1'd1;
    reg [1:0] state = STATE_WAIT;

    reg [9:0] send_data = ~0;
    reg [3:0] send_bits;
    reg [31:0] send_hold;

    // Baud rate 115200, clock 25MHz
    localparam HOLD_CYCLES = 25000000 / 115200;

    assign o_tx = send_data[0];
    assign o_ready = state == STATE_WAIT;

    always @(posedge i_clk) begin
        if (i_rst) begin
            cycle_count <= 0;
            state <= STATE_WAIT;
            send_data <= ~0;
            o_err <= 0;
        end else if (i_en) begin
            o_err = 0;
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
                            state <= STATE_WAIT;
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

            endcase
        end
    end

endmodule

module cpu(input wire i_clk,
           input wire i_en,
           input wire i_rst,
           output o_err,
           output o_done);

    // TODO: remove
    reg [24:0] cycle_count = 0;
    localparam DELAY = 25'h1ffabcd;

    always @(posedge i_clk) begin
        if (i_rst) begin
            cycle_count <= 0;
            o_done <= 0;
            o_err <= 0;
        end else if (i_en) begin
            // TODO
            o_err <= 0;
            cycle_count <= cycle_count + 1;
            if (cycle_count >= DELAY) begin
                o_done <= 1;
            end else begin
                o_done <= 0;
            end
        end
    end

endmodule

// Cycle count incrementer.
module cycle_counter(input wire i_clk,
                     input wire i_en,
                     input wire i_rst,
                     output reg [63:0] o_count,
                     output reg o_err);

    reg [63:0] count;
    localparam MAX_COUNT = 64'hffffffffffffffff;

    initial begin
        count = 0;
        o_err = 0;
    end

    always @(posedge i_clk) begin
        if (i_rst) begin
            count <= 0;
            o_err <= 0;
        end else if (i_en) begin
            count <= count + 1;
            if (count >= MAX_COUNT) begin
                // Counter overflow.
                o_err <= 1;
            end
            o_count <= count;
        end
    end

endmodule
