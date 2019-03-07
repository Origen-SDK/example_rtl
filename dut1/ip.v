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

  reg [48:0] dr;

  wire write_en;
  wire write;
  wire read;
  wire [15:0] address;
  wire [31:0] data;
  wire busy, fail, error;

  assign tdo = dr[0];
  assign address[15:0] = dr[47:32];
  assign data[31:0] = dr[31:0];
  assign write_en = dr[48];
  assign write = write_en && update;
  assign read = !write_en && capture;

  // JTAG scan chain

  always @ (posedge tck or negedge reset_n) begin
    if (reset_n == 0)
      dr[48:0] <= 49'b0;
    else if (shift == 1)
      begin
        dr[48] <= tdi;
        dr[47:0] <= dr[48:1];
      end
    else
      dr[48:0] <= dr[48:0];
  end

  // User regs
  reg [31:0] cmd;       // Address 0
  reg [31:0] status;    // Address 4
  reg [31:0] data_reg;  // Address 8

  always @ (negedge tck or negedge reset_n) begin
    if (reset_n == 0)
      cmd[31:0] <= 32'b0;
    else if (write && address == 16'h0) begin
      if (busy)
        status[2] <= 1'b1;
      else
        cmd[31:0] <= data[31:0];
      end
    else if (read && address == 16'h0)
      dr[31:0] <= cmd[31:0];
  end

  assign busy = status[0];
  assign fail = status[1];
  assign error = status[2];
  
  always @ (negedge tck or negedge reset_n) begin
    if (reset_n == 0)
      status[31:0] <= 32'b1;   // Set busy bit during reset
    else if (write && address == 16'h4) begin
      if (busy)
        status[2] <= 1'b1;
      else
        begin
          if (data[1] == 1'b1)
            status[1] <= 1'b0;
          if (data[2] == 1'b1)
            status[2] <= 1'b0;
        end
      end
    else if (read && address == 16'h4)
      dr[31:0] <= status[31:0];
  end

  always @ (posedge reset_n) begin
    status[31:0] <= 32'b0;   // Clear busy bit
  end

  always @ (negedge tck or negedge reset_n) begin
    if (reset_n == 0)
      data_reg[31:0] <= 32'b0;
    else if (write && address == 16'h8)
      data_reg[31:0] <= data[31:0];
    else if (read && address == 16'h8)
      dr[31:0] <= data_reg[31:0];
  end

  // Commands 

  reg [31:0] i; // Used as a timer to emulate a command running for a while

  always @ (negedge tck) begin
    if (cmd >= 32'd1 && cmd <= 32'd1000)
      begin
        if (busy == 0)
          begin
            i[31:0] <= 1000 * cmd;
            status[0] <= 1'b1;
          end
        else
          begin
            if (i == 1)
              begin
                cmd[31:0] <= 32'h0;
                i <= 0;
                status[0] <= 1'b0;
              end
            else
              i <= i - 1;
          end
      end
    // Illegal command code
    else if (cmd != 32'h0)
      status[2] <= 1'b1;
  end

endmodule
