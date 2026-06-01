module top(input wire clk_25mhz,
           output ftdi_rxd,
           input ftdi_txd,
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
    localparam STATE_DONE = 2'd2; // Program exited (successfully).
    localparam STATE_ERRS = 2'd3; // Init or exec stages ended due to failures.
    reg [1:0] state = STATE_INIT;

    // Error flags.
    localparam ERRBIT_TIMEOUT = 0; // Maximum cycle count exceeded.
    localparam ERRBIT_UART = 2;    // Error from the UART module.
    localparam ERRBIT_CPU = 1;     // Error from the CPU module.
    localparam ERRBIT_MEM = 2;     // Error from the memory module.
    reg [3:0] errs = 0;

    // Set up cycle counter.
    reg [63:0] cycle_count = 0;
    localparam TIMEOUT = 64'hffffffff;

    wire cpu_done;
    wire cpu_err;
    cpu cpu(
        .i_clk(i_clk),
        .i_cpu_en(state == STATE_EXEC),
        .o_err(cpu_err),
        .o_done(cpu_done),
    );

    // Main state machine.
    always @(posedge i_clk) begin
          o_led[7:0] = 0;
          case (state)

                STATE_INIT: begin
                    o_led[1] = 1; // orange led for init
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

    // Cycle count incrementer.
    always @(posedge i_clk) begin
        cycle_count <= cycle_count + 1;
        if (cycle_count >= TIMEOUT) begin
                // Cycle counter overflow
                errs[ERRBIT_TIMEOUT] = 1;
        end
    end

endmodule

module cpu(input wire i_clk,
           input wire i_cpu_en,
           output wire o_err,
           output wire o_done);

    // If cpu-enable is set, execute the program.
    always @(posedge i_clk) begin
        if (i_cpu_en) begin
            // TODO
            o_err = 1;
            o_done = 0;
        end
        else begin
            o_err = 0;
            o_done = 0;
        end
    end

endmodule
