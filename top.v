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
    wire uart_rx_data_valid;
    wire uart_rx_done;
    wire uart_rx_err;
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
    wire uart_tx_data_valid;
    wire uart_tx_ready;
    wire uart_tx_err;
    uart_tx uart_tx(
        .i_clk(i_clk),
        .i_en(uart_tx_en),
        .i_rst(i_rst),
        .i_data(uart_tx_fifo[uart_tx_fifo_offset]),
        .i_data_valid(uart_tx_data_valid),
        .o_tx(ftdi_rxd),
        .o_ready(uart_tx_ready),
        .o_err(uart_tx_err),
    );

    assign cpu_en = (state == STATE_EXEC);
    wire cpu_done;
    wire cpu_err;
    cpu cpu(
        .i_clk(i_clk),
        .i_en(cpu_en),
        .i_rst(i_rst),
        .o_err(cpu_err),
        .o_done(cpu_done),
    );

    wire [63:0] cycle_count;
    assign cycle_counter_en = (state == STATE_EXEC);
    wire cycle_counter_err;
    cycle_counter cycle_counter(
        .i_clk(i_clk),
        .i_en(cycle_counter_en),
        .o_count(cycle_count),
        .o_err(cycle_counter_err),
    );

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
                        uart_tx_fifo[uart_tx_fifo_offset + 0]  = 8'h64; // 'd'
                        uart_tx_fifo[uart_tx_fifo_offset + 1]  = 8'h6f; // 'o'
                        uart_tx_fifo[uart_tx_fifo_offset + 2]  = 8'h6e; // 'n'
                        uart_tx_fifo[uart_tx_fifo_offset + 3]  = 8'h65; // 'e'
                        uart_tx_fifo[uart_tx_fifo_offset + 4]  = 8'h21; // '!'
                        uart_tx_fifo[uart_tx_fifo_offset + 5]  = 8'h0d; // '\r'
                        uart_tx_fifo[uart_tx_fifo_offset + 6]  = 8'h0a; // '\n'

                        uart_tx_fifo[uart_tx_fifo_offset + 7]  = 8'h63; // 'c'
                        uart_tx_fifo[uart_tx_fifo_offset + 8]  = 8'h79; // 'y'
                        uart_tx_fifo[uart_tx_fifo_offset + 9]  = 8'h63; // 'c'
                        uart_tx_fifo[uart_tx_fifo_offset + 10] = 8'h6c; // 'l'
                        uart_tx_fifo[uart_tx_fifo_offset + 11] = 8'h65; // 'e'
                        uart_tx_fifo[uart_tx_fifo_offset + 12] = 8'h73; // 's'
                        uart_tx_fifo[uart_tx_fifo_offset + 13] = 8'h3a; // ':'
                        uart_tx_fifo[uart_tx_fifo_offset + 14] = 8'h20; // ' '
                        uart_tx_fifo[uart_tx_fifo_offset + 15] = 8'h30; // '0'
                        uart_tx_fifo[uart_tx_fifo_offset + 16] = 8'h78; // 'x'
                        uart_tx_fifo[uart_tx_fifo_offset + 17] = ascii_hex_nibble(cycle_count[63:60]);
                        uart_tx_fifo[uart_tx_fifo_offset + 18] = ascii_hex_nibble(cycle_count[59:56]);
                        uart_tx_fifo[uart_tx_fifo_offset + 19] = ascii_hex_nibble(cycle_count[55:52]);
                        uart_tx_fifo[uart_tx_fifo_offset + 20] = ascii_hex_nibble(cycle_count[51:48]);
                        uart_tx_fifo[uart_tx_fifo_offset + 21] = ascii_hex_nibble(cycle_count[47:44]);
                        uart_tx_fifo[uart_tx_fifo_offset + 22] = ascii_hex_nibble(cycle_count[43:40]);
                        uart_tx_fifo[uart_tx_fifo_offset + 23] = ascii_hex_nibble(cycle_count[39:36]);
                        uart_tx_fifo[uart_tx_fifo_offset + 24] = ascii_hex_nibble(cycle_count[35:32]);
                        uart_tx_fifo[uart_tx_fifo_offset + 25] = ascii_hex_nibble(cycle_count[31:28]);
                        uart_tx_fifo[uart_tx_fifo_offset + 26] = ascii_hex_nibble(cycle_count[27:24]);
                        uart_tx_fifo[uart_tx_fifo_offset + 27] = ascii_hex_nibble(cycle_count[23:20]);
                        uart_tx_fifo[uart_tx_fifo_offset + 28] = ascii_hex_nibble(cycle_count[19:16]);
                        uart_tx_fifo[uart_tx_fifo_offset + 29] = ascii_hex_nibble(cycle_count[15:12]);
                        uart_tx_fifo[uart_tx_fifo_offset + 30] = ascii_hex_nibble(cycle_count[11:8]);
                        uart_tx_fifo[uart_tx_fifo_offset + 31] = ascii_hex_nibble(cycle_count[7:4]);
                        uart_tx_fifo[uart_tx_fifo_offset + 32] = ascii_hex_nibble(cycle_count[3:0]);
                        uart_tx_fifo[uart_tx_fifo_offset + 33] = 8'h0d; // '\r'
                        uart_tx_fifo[uart_tx_fifo_offset + 34] = 8'h0a; // '\n'

                        uart_tx_fifo_bytelength <= 35;
                        uart_tx_data_valid <= 1;
                        next_state <= STATE_DONE;
                    end
                end

                STATE_DONE: begin
                    o_led[2] = 1; // green led for done

                    // If the UART transmitter is ready and there is data in the FIFO, send it.
                    if (uart_tx_ready && uart_tx_data_valid) begin
                        if (uart_tx_fifo_bytelength <= 1) begin
                            uart_tx_data_valid <= 0;
                        end else begin
                            if (uart_tx_fifo_offset == UART_TX_FIFO_DEPTH - 1) begin
                                uart_tx_fifo_offset <= 0;
                            end else begin
                                uart_tx_fifo_offset <= uart_tx_fifo_offset + 1;
                            end
                            uart_tx_fifo_bytelength <= uart_tx_fifo_bytelength - 1;
                        end
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
               output wire o_data_valid,
               output wire o_done,
               output wire o_err);

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
            state = STATE_WAIT;
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
           output wire o_err,
           output wire o_done);

    // TODO: remove
    reg [24:0] cycle_count = 0;
    localparam DELAY = 25'h1ffff00;

    always @(posedge i_clk) begin
        if (i_rst) begin
            cycle_count <= 0;
            o_done <= 0;
            o_err <= 0;
        end else if (i_en) begin
            // TODO
            o_err = 0;
            o_done = 0;
            cycle_count <= cycle_count + 1;
            if (cycle_count >= DELAY) begin
                o_done = 1;
            end
        end
    end

endmodule

// Cycle count incrementer.
module cycle_counter(input wire i_clk,
                     input wire i_en,
                     input wire i_rst,
                     output [63:0] o_count,
                     output wire o_err);

    reg [63:0] count = 0;
    localparam MAX_COUNT = 64'hffffffffffffffff;

    always @(posedge i_clk) begin
        if (i_rst) begin
            count = 0;
            o_err = 0;
        end else if (i_en) begin
            count = count + 1;
            if (count >= MAX_COUNT) begin
                // Counter overflow.
                o_err = 1;
            end
            o_count = count;
        end
    end

endmodule
