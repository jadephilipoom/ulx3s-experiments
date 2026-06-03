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

    assign uart_rx_en = (state == STATE_INIT);
    wire [7:0] uart_rx_data;
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

    // Set up cycle counter.
    reg [63:0] cycle_count = 0;
    reg inc_cycle_count;
    reg cycle_count_err;
    localparam MAX_CYCLE_COUNT = 64'hffffffffffffffff;

    // Tracking for printing message at the end of exec. Cycle count is printed
    // in hex between prefix and suffix.
    reg [31:0] done_msg_bytes_sent;
    reg [7:0] done_msg_prefix_chars [0:16];
    reg [7:0] done_msg_suffix_chars [0:1];
    reg [6:0] cycle_count_bit_offset;
    reg decrement_bit_offset;
    reg clear_bytes_sent;
    reg inc_bytes_sent;
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

    // Function for converting a nibble to ASCII hex.
    function [7:0] ascii_hex_nibble(input [3:0] n);
        begin
            ascii_hex_nibble = ((n < 4'd10) ? 8'h30 : 8'h57) + {4'd0, n};
        end
    endfunction

    // Split the state machine into two halves:
    // - A combinational section that takes in only state, and produces logic output. That's this
    //   part immediately below
    // - A sequential section that takes combinational outputs and puts them through registers. That's
    //   in the always @ clocked block below.
    //
    // The prior implementation was trying to assign things in the same blocks that would reference
    // them - this actually leads to latches being inferred, and/or combinational cycles, which can
    // result in unpredictable/undefined behavior.
    always @(*) begin
        o_led[7:0] = 0;
        decrement_bit_offset = 0;
        clear_bytes_sent = 0;
        inc_bytes_sent = 0;
        // so the set/clr bits here are combinational signals that tell the sequential section
        // below that it should set or clear the bits. There's many ways to do this, I wouldn't
        // necessarily have coded it like this from a clean sheet but I'm trying to retrofit
        // your concepts into syntactically clean verilog.
        set_uart_tx_data_valid = 0;
        clr_uart_tx_data_valid = 0;
        inc_cycle_count = 0;
        cycle_count_err = 0;
        uart_tx_data = 0;
        next_state = state; // sets a default value for state.
        // we're using "blocking" operations here, so the values are applied "as you read the code"
        // i.e., next_state gets state because of the line above, but will be overridden by any
        // statements later on that mutate that. While it is technically legal in verilog to
        // make variables that are referenced across multiple always @ blocks, in practice, this
        // can lead to synthesis problems. If you want your code to be ASIC-ready, try to keep
        // all the variables that you *update* within a single block (you can reference them
        // anywhere else, but the "left hand sides" should generally try to all be within a
        // single always block, and ideally, within a single statement block)
        case(state)
            STATE_INIT: begin
                o_led[1] = 1;
                clr_uart_tx_data_valid = 1;

                // If the serial receiver is done, transition to the exec state.
                if (uart_rx_en && uart_rx_done) begin
                    next_state = STATE_EXEC;
                end
            end
            STATE_EXEC: begin
                o_led[3] = 1;
                inc_cycle_count = 1;

                // Check if the cycle counter will overflow.
                if (cycle_count == MAX_CYCLE_COUNT) begin
                    cycle_count_err = 1;
                end

                // If the CPU is done, transition to the done state and print a message.
                if (cpu_en && cpu_done) begin
                    next_state = STATE_DONE;
                    uart_tx_data = done_msg_prefix_chars[0];
                    set_uart_tx_data_valid = 1;
                    clear_bytes_sent = 1;
                end
            end
            STATE_DONE: begin
                o_led[2] = 1;
                // If the UART transmitter is ready and there is still
                // something to print, send the next byte.
                if (uart_tx_ready && uart_tx_data_valid) begin
                    if (done_msg_bytes_sent < 17) begin
                        uart_tx_data = done_msg_prefix_chars[done_msg_bytes_sent];
                    end else if (done_msg_bytes_sent < 33) begin
                        uart_tx_data = ascii_hex_nibble(cycle_count[cycle_count_bit_offset +: 4]);
                        decrement_bit_offset = 1;
                    end else if (done_msg_bytes_sent < 35) begin
                        uart_tx_data = done_msg_suffix_chars[done_msg_bytes_sent - 33];
                    end else begin
                        clr_uart_tx_data_valid = 1;
                    end
                    inc_bytes_sent = 1;
                end
            end
            STATE_ERRS: begin
                o_led[0] = 1;
                // Set additional LEDs to error flags.
                o_led[4] = errs[0];
                o_led[5] = errs[1];
                o_led[6] = errs[2];
                o_led[7] = errs[3];

                clr_uart_tx_data_valid = 1;
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
        errs[ERRBIT_CPU] <= errs[ERRBIT_CPU] || (cpu_en && cpu_err);
        errs[ERRBIT_MEM] <= errs[ERRBIT_MEM] || 0; // TODO

        // Check for errors or reset that would intercept the state change.
        // "ASIC ready" code would put all the reset clauses in this first "if" block - because
        // this would allow you to do e.g. `negedge rst_n` triggered async clear, making a clear
        // inference to a particular type of register. Unfortunately, FPGAs don't support this, and
        // so you have this constant tension between FPGA-ready code and ASIC-ready code. This style
        // is very much FPGA-ready.
        if (i_rst) begin
            state <= STATE_INIT;
            errs <= 0;
            done_msg_bytes_sent <= 0;
            cycle_count_bit_offset <= 6'd60;
            cycle_count <= 0;
        end else if (errs) begin
            state <= STATE_ERRS;
        end else begin
            state <= next_state;
            if (inc_cycle_count) begin
                cycle_count <= cycle_count + 1;
            end
            if (decrement_bit_offset) begin
                cycle_count_bit_offset <= cycle_count_bit_offset - 4;
            end
            // I've hoisted done_msg_bytes_sent out of the comb loop and stuck it down here,
            // and its state is only updated based on pure combinational computed in the
            // always @(*) comb block above.
            if (clear_bytes_sent) begin
                done_msg_bytes_sent <= 0;
            end else if (inc_bytes_sent) begin
                done_msg_bytes_sent <= done_msg_bytes_sent + 1;
            end
            // Here I give reset and clear precedence over set. This resolves the question of
            // what happens if both clr and set are set at the same time.
            if (i_rst || clr_uart_tx_data_valid) begin
                uart_tx_data_valid <= 0;
            end else if (set_uart_tx_data_valid) begin
                uart_tx_data_valid <= 1;
            end
        end

    end

endmodule

module uart_rx(input wire i_clk,
               input wire i_en,
               input wire i_rst,
               input wire i_rx,
               output [7:0] o_data,
               output reg o_data_valid,
               output reg o_done,
               output reg o_err);

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
            o_data_valid <= 0;
            o_err <= 0;
            o_done <= 0;
            cycle_count <= cycle_count + 1;
            if (cycle_count >= DELAY) begin
                o_done <= 1;
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
               output reg o_err);

    localparam STATE_WAIT = 1'd0;
    localparam STATE_SEND = 1'd1;
    reg state = STATE_WAIT;

    reg [9:0] send_data = ~0;
    reg [3:0] send_bits;
    reg [31:0] send_hold;

    // Baud rate 115200, clock 25MHz
    localparam HOLD_CYCLES = 25000000 / 115200;

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
           output reg o_err,
           output reg o_done);

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
            o_done <= 0;
            cycle_count <= cycle_count + 1;
            if (cycle_count >= DELAY) begin
                o_done <= 1;
            end
        end
    end

endmodule
