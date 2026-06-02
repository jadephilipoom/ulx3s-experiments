module top(input wire clk_25mhz,
           input ftdi_txd,
           output ftdi_rxd,
           output [7:0] led);

    assign i_clk = clk_25mhz;

    // Set up LED array.
    // - 0, 4: red
    // - 1, 5: orange
    // - 2, 6: green
    // - 3, 7: blue
    reg [7:0] o_led = 0;
    assign led = o_led;

    // Set up basic state machine.
    localparam STATE_INIT = 2'd0; // Initializing; program not yet loaded.
    localparam STATE_EXEC = 2'd1; // Executing the program.
    localparam STATE_DONE = 2'd2; // Program exited successfully (terminal state).
    localparam STATE_ERRS = 2'd3; // Crashed due to failures (terminal state).
    reg [1:0] state = STATE_INIT;

    // Error flags.
    localparam ERRBIT_CNT = 0;  // Error from the cycle counter.
    localparam ERRBIT_SER = 2;  // Error from the serial module.
    localparam ERRBIT_CPU = 1;  // Error from the CPU module.
    localparam ERRBIT_MEM = 2;  // Error from the memory module.
    reg [3:0] errs = 0;

    reg [7:0] uart_rx_data;
    wire uart_rx_data_valid;
    wire uart_rx_done;
    wire uart_rx_err;
    uart_rx uart_rx(
        .i_clk(i_clk),
        .i_en(state == STATE_INIT),
        .i_rx(ftdi_txd),
        .o_data(uart_rx_data),
        .o_valid(uart_rx_data_valid),
        .o_done(uart_rx_done),
        .o_err(uart_rx_err),
    );

    reg [7:0] uart_tx_data;
    wire uart_tx_data_valid;
    wire uart_tx_done;
    wire uart_tx_err;
    uart_tx uart_tx(
        .i_clk(i_clk),
        .i_en(state == STATE_DONE),
        .i_data(uart_tx_data),
        .o_tx(ftdi_rxd),
        .o_valid(uart_tx_data_valid),
        .o_done(uart_tx_done),
        .o_err(uart_tx_err),
    );

    wire cpu_done;
    wire cpu_err;
    cpu cpu(
        .i_clk(i_clk),
        .i_en(state == STATE_EXEC),
        .o_err(cpu_err),
        .o_done(cpu_done),
    );

    // Main state machine.
    always @(posedge i_clk) begin
          o_led[7:0] = 0;
          case (state)

                STATE_INIT: begin
                    o_led[1] = 1; // orange led for init

                    // If the serial module is done, transition to the exec state.
                    if (reader_done) begin
                        state = STATE_EXEC;
                    end

                    // If the serial module had errors, transition to the error state.
                    if (reader_err) begin
                        errs[ERRBIT_SER] = 1;
                        state = STATE_ERRS;
                    end
                end

                STATE_EXEC: begin
                    o_led[3] = 1; // blue led for exec

                    // If the CPU had errors, transition to the error state.
                    if (cpu_err) begin
                        errs[ERRBIT_CPU] = 1;
                        state = STATE_ERRS;
                    end

                    // If the CPU is done, transition to the done state.
                    if (cpu_done) begin
                        state = STATE_DONE;
                    end
                end

                STATE_DONE: begin
                    o_led[2] = 1; // green led for done
                end

                STATE_ERRS: begin
                    o_led[0] = 1; // red led for errors

                    // Set additional LEDs to error flags.
                    o_led[4] = errs[0];
                    o_led[5] = errs[1];
                    o_led[6] = errs[2];
                    o_led[7] = errs[3];
                end

        endcase
    end

    wire timeout;
    cycle_counter cycle_counter(
        .i_clk(i_clk),
        .i_en(state != STATE_DONE && state != STATE_ERRS),
        .o_err(timeout),
    );

    // Check for timeouts.
    always @(posedge i_clk) begin
          // If the counter timed out, transition to the error state.
          if (timeout) begin
              errs[ERRBIT_CNT] = 1;
              state = STATE_ERRS;
          end
    end

endmodule

module uart_rx(input wire i_clk,
               input wire i_en,
               input wire i_rx,
               output [7:0] o_data,
               output wire o_valid,
               output wire o_done,
               output wire o_err);

    localparam STATE_WAIT = 2'd0; // Waiting for start sequence.
    localparam STATE_READ = 2'd1; // Reading data until end sequence.
    reg [2:0] state = STATE_WAIT;

    always @(posedge i_clk) begin
        if (i_en) begin
            o_valid = 0;
            o_err = 0;
            o_done = 1;
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
               input [7:0] i_data,
               output wire o_tx,
               output wire o_valid,
               output wire o_done,
               output wire o_err);

    always @(posedge i_clk) begin
        if (i_en) begin
            o_valid = 0;
            o_err = 0;
            o_done = 1;
        end
    end

endmodule

module cpu(input wire i_clk,
           input wire i_en,
           output wire o_err,
           output wire o_done);

    always @(posedge i_clk) begin
        if (i_en) begin
            // TODO
            o_err = 0;
            o_done = 1;
        end
    end

endmodule

// Cycle count incrementer.
module cycle_counter(input wire i_clk,
                     input wire i_en,
                     output wire o_err);

    reg [63:0] cycle_count = 0;
    localparam TIMEOUT = 64'hffffffff;

    always @(posedge i_clk) begin
        if (i_en) begin
            cycle_count <= cycle_count + 1;
            if (cycle_count >= TIMEOUT) begin
                // Counter overflow.
                o_err = 1;
            end
        end
    end

endmodule
