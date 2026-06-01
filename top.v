module top(input wire clk_25mhz,
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
    localparam ERRBIT_INVALID = 1; // Invalid instruction.
    reg [3:0] errs = 0;

    // Set up cycle counter.
    reg [63:0] cycle_count = 0;
    localparam TIMEOUT = 64'hffffffff;

    // Main state machine.
    always @(posedge i_clk) begin
          o_led[7:0] = 0;
          case (state)

                STATE_INIT: begin
                    o_led[1] = 1; // orange led for init
                end

                STATE_EXEC: begin
                    o_led[3] = 1; // blue led for exec
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
                state = STATE_ERRS;
                errs[ERRBIT_TIMEOUT] = 1;
        end
    end

endmodule
