// Simple module with a JTAG scan chain and the ability to execute a command
// and act busy for a while to simulate an IP under test
module ip(
            tdi,
            shift,
            update,
            capture,
            tck,

            reset_n,

            tdo
         );

  input tdi;
  input shift;
  input update;
  input capture;
  input tck;

  input reset_n;

  output tdo;

  reg [47:0] dr;

  wire [15:0] address;
  wire [31:0] data;

  assign tdo = dr[0];
  assign address[15:0] = dr[47:32];
  assign data[31:0] = dr[31:0];

  // User regs
  reg [31:0] cmd;  // Address 0

  always @ (posedge tck or negedge reset_n) begin
    if (reset_n == 0)
      dr[47:0] <= 48'b0;
    else if (shift == 1)
      begin
        dr[47] <= tdi;
        dr[46:0] <= dr[47:1];
      end
    else
      dr[47:0] <= dr[47:0];
  end

  always @ (negedge tck or negedge reset_n) begin
    if (reset_n == 0)
      cmd[31:0] <= 32'b0;
    else if (update && address == 16'h0)
      cmd[31:0] <= data[31:0];
    else if (capture && address == 16'h0)
      dr[31:0] <= cmd[31:0];
  end

endmodule
