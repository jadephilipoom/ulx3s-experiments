module top(input clk_25mhz,
           input [6:0] btn,
           output [7:0] led,
           output wifi_gpio0);

    wire i_clk;
    assign i_clk= clk_25mhz;

    // Setting this pin (somehow?) prevents the ESP32 firmware from writing a
    // passthru bistream and taking over.
    assign wifi_gpio0 = 1'b1;

    reg [7:0] o_led = 0;
    assign led= o_led;

    always @(posedge i_clk) begin
          if (btn[1]) begin 
                o_led[7] = 0;
            end
          if (btn[2]) begin 
                o_led[7] = 1;
            end
    end

endmodule
