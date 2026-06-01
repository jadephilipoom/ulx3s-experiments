module top(input clk_25mhz,
           output [7:0] led);

    wire i_clk;
    assign i_clk= clk_25mhz;

    reg [7:0] o_led = 0;
    assign led = o_led;

    // Set up basic state machine.
    localparam STATE_INIT = 2'd0; // Initializing; program not yet loaded.
    localparam STATE_EXEC = 2'd1; // Executing the program.
    localparam STATE_DONE = 2'd2; // Program exited (successfully).
    localparam STATE_ERRS = 2'd3; // Init or exec stages ended due to failures.
    reg [1:0] state = STATE_INIT;

    always @(posedge i_clk) begin
          case (state)

                STATE_INIT: begin
                    o_led[0] = 1;
                end

                STATE_EXEC: begin
                    o_led[1] = 1;
                end

                STATE_DONE: begin
                    o_led[2] = 1;
                end

                STATE_ERRS: begin
                    o_led[3] = 1;
                end
        endcase
    end

endmodule
