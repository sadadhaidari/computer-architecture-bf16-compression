// One elastic stage per core. The 640-bit bus is an internal frame, not FPGA pins.
module bf16_encoder (
    input wire clk, rst,
    input wire in_valid, output wire in_ready,
    input wire [511:0] in_data, input wire [7:0] in_base,
    output reg out_valid, input wire out_ready,
    output reg [639:0] out_data, output reg [6:0] out_bytes,
    output reg [7:0] out_base
);
    reg [639:0] packed_data;
    reg [3:0] code;
    reg [7:0] exponent;
    integer lane, count, delta;
    always @* begin
        packed_data=0; count=0; code=0; exponent=0; delta=0;
        for (lane=0;lane<32;lane=lane+1) begin
            // Keep sign and fraction intact; compress the exponent field.
            packed_data[8*lane +:8]={in_data[16*lane+15],in_data[16*lane +:7]};
            exponent=in_data[16*lane+7 +:8];
            delta={1'b0,exponent}-{1'b0,in_base};
            // Use offsets 0 through 14; code 15 reserves a full-exponent escape.
            if (delta>=0 && delta<15) code=delta[3:0];
            else begin
                code=15; packed_data[384+8*count +:8]=exponent; count=count+1;
            end
            if (lane<16) packed_data[256+8*lane +:4]=code;
            else packed_data[260+8*(lane-16) +:4]=code;
        end
    end
    // Hold the output during a stall; accept a new frame when the stage is free.
    assign in_ready=!out_valid || out_ready;
    always @(posedge clk) begin
        if (rst) begin out_valid<=0;out_data<=0;out_bytes<=0;out_base<=0;end
        else if (in_ready) begin
            out_valid<=in_valid;
            if (in_valid) begin out_data<=packed_data;out_bytes<=48+count;out_base<=in_base;end
        end
    end
endmodule

module bf16_decoder (
    input wire clk, rst,
    input wire in_valid, output wire in_ready,
    input wire [639:0] in_data, input wire [6:0] in_bytes,
    input wire [7:0] in_base,
    output reg out_valid, input wire out_ready,
    output reg [511:0] out_data, output reg out_error
);
    reg [511:0] restored;
    reg [3:0] code;
    reg [7:0] payload,exponent;
    reg bad;
    integer lane,count;
    always @* begin
        restored=0;count=0;code=0;payload=0;exponent=0;bad=(in_base>241);
        for (lane=0;lane<32;lane=lane+1) begin
            payload=in_data[8*lane +:8];
            if (lane<16) code=in_data[256+8*lane +:4];
            else code=in_data[260+8*(lane-16) +:4];
            if (code==15) begin exponent=in_data[384+8*count +:8];count=count+1;end
            else exponent=in_base+code;
            restored[16*lane +:16]={payload[7],exponent,payload[6:0]};
        end
        // The declared frame length must match the number of escape codes.
        if (in_bytes!=48+count) bad=1;
    end
    assign in_ready=!out_valid || out_ready;
    always @(posedge clk) begin
        if (rst) begin out_valid<=0;out_data<=0;out_error<=0;end
        else if (in_ready) begin
            out_valid<=in_valid;
            if (in_valid) begin out_data<=restored;out_error<=bad;end
        end
    end
endmodule

// The encoder and decoder are separate paths. This wrapper contains no RAM controller.
module bf16_codec_pair (
    input wire clk,rst,
    input wire write_valid, output wire write_ready,
    input wire [511:0] write_data,input wire [7:0] write_base,
    output wire packed_valid,input wire packed_ready,
    output wire [639:0] packed_data,output wire [6:0] packed_bytes,
    output wire [7:0] packed_base,
    input wire read_valid,output wire read_ready,
    input wire [639:0] read_data,input wire [6:0] read_bytes,input wire [7:0] read_base,
    output wire restored_valid,input wire restored_ready,
    output wire [511:0] restored_data,output wire read_error
);
    bf16_encoder enc(clk,rst,write_valid,write_ready,write_data,write_base,packed_valid,packed_ready,packed_data,packed_bytes,packed_base);
    bf16_decoder dec(clk,rst,read_valid,read_ready,read_data,read_bytes,read_base,restored_valid,restored_ready,restored_data,read_error);
endmodule
