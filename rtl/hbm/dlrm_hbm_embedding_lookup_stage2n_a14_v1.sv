`timescale 1ns/1ps

module dlrm_hbm_embedding_lookup_stage2n_a14_v1 #(
  parameter integer ROWS           = 64,
  parameter integer DIM            = 8,
  parameter integer ELEMENT_WIDTH  = 16,
  parameter integer DATA_WIDTH     = 128,
  parameter integer AXI_ADDR_WIDTH = 64,
  parameter integer AXI_ID_WIDTH   = 1,
  parameter integer INDEX_WIDTH    = (ROWS <= 1) ? 1 : $clog2(ROWS)
) (
  input  logic                          clk,
  input  logic                          rst,

  input  logic                          lookup_req_valid,
  output logic                          lookup_req_ready,
  input  logic [INDEX_WIDTH-1:0]        lookup_req_index,

  output logic                          lookup_rsp_valid,
  input  logic                          lookup_rsp_ready,
  output logic [DATA_WIDTH-1:0]         lookup_rsp_data,
  output logic [INDEX_WIDTH-1:0]        lookup_rsp_index,
  output logic                          lookup_rsp_error,

  output logic [AXI_ID_WIDTH-1:0]       m_axi_arid,
  output logic [AXI_ADDR_WIDTH-1:0]     m_axi_araddr,
  output logic [7:0]                    m_axi_arlen,
  output logic [2:0]                    m_axi_arsize,
  output logic [1:0]                    m_axi_arburst,
  output logic                          m_axi_arlock,
  output logic [3:0]                    m_axi_arcache,
  output logic [2:0]                    m_axi_arprot,
  output logic [3:0]                    m_axi_arqos,
  output logic                          m_axi_arvalid,
  input  logic                          m_axi_arready,

  input  logic [AXI_ID_WIDTH-1:0]       m_axi_rid,
  input  logic [DATA_WIDTH-1:0]         m_axi_rdata,
  input  logic [1:0]                    m_axi_rresp,
  input  logic                          m_axi_rlast,
  input  logic                          m_axi_rvalid,
  output logic                          m_axi_rready
);
  localparam integer ROW_BYTES = (DIM * ELEMENT_WIDTH) / 8;
  localparam logic [2:0] AXI_SIZE =
      $clog2(DATA_WIDTH / 8);

  typedef enum logic [1:0] {
    IDLE,
    SEND_AR,
    WAIT_R,
    RESP
  } state_t;

  state_t state;

  logic [AXI_ADDR_WIDTH-1:0] address_reg;
  logic [INDEX_WIDTH-1:0] request_index_reg;
  logic [DATA_WIDTH-1:0] response_data_reg;
  logic [INDEX_WIDTH-1:0] response_index_reg;
  logic response_error_reg;

  assign lookup_req_ready = (state == IDLE);

  assign lookup_rsp_valid = (state == RESP);
  assign lookup_rsp_data = response_data_reg;
  assign lookup_rsp_index = response_index_reg;
  assign lookup_rsp_error = response_error_reg;

  assign m_axi_arid = '0;
  assign m_axi_araddr = address_reg;
  assign m_axi_arlen = 8'd0;
  assign m_axi_arsize = AXI_SIZE;
  assign m_axi_arburst = 2'b01;
  assign m_axi_arlock = 1'b0;
  assign m_axi_arcache = 4'b0011;
  assign m_axi_arprot = 3'b000;
  assign m_axi_arqos = 4'b0000;
  assign m_axi_arvalid = (state == SEND_AR);

  assign m_axi_rready = (state == WAIT_R);

  always_ff @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      address_reg <= '0;
      request_index_reg <= '0;
      response_data_reg <= '0;
      response_index_reg <= '0;
      response_error_reg <= 1'b0;
    end else begin
      case (state)
        IDLE: begin
          if (lookup_req_valid && lookup_req_ready) begin
            request_index_reg <= lookup_req_index;
            response_index_reg <= lookup_req_index;
            response_error_reg <= 1'b0;

            if (lookup_req_index >= ROWS) begin
              response_data_reg <= '0;
              response_error_reg <= 1'b1;
              state <= RESP;
            end else begin
              // The A14.1 frozen row size is 16 bytes.
              address_reg <=
                  {{(AXI_ADDR_WIDTH-INDEX_WIDTH){1'b0}},
                   lookup_req_index} << 4;
              state <= SEND_AR;
            end
          end
        end

        SEND_AR: begin
          if (m_axi_arvalid && m_axi_arready)
            state <= WAIT_R;
        end

        WAIT_R: begin
          if (m_axi_rvalid && m_axi_rready) begin
            response_data_reg <= m_axi_rdata;
            response_index_reg <= request_index_reg;
            response_error_reg <=
                (m_axi_rresp != 2'b00) ||
                !m_axi_rlast ||
                (m_axi_rid != {AXI_ID_WIDTH{1'b0}});
            state <= RESP;
          end
        end

        RESP: begin
          if (lookup_rsp_valid && lookup_rsp_ready)
            state <= IDLE;
        end

        default: begin
          state <= IDLE;
        end
      endcase
    end
  end

  initial begin
    if (ROWS <= 0)
      $error("A14.1 HBM lookup ROWS must be positive");
    if (DIM <= 0 || ELEMENT_WIDTH <= 0 || DATA_WIDTH <= 0)
      $error("A14.1 HBM lookup dimensions and widths must be positive");
    if (DIM * ELEMENT_WIDTH != DATA_WIDTH)
      $error("A14.1 HBM lookup DATA_WIDTH must equal DIM*ELEMENT_WIDTH");
    if (DATA_WIDTH != 128 || ROW_BYTES != 16)
      $error("A14.1 HBM lookup requires a 128-bit, 16-byte row");
    if (AXI_ADDR_WIDTH < INDEX_WIDTH + 4)
      $error("A14.1 HBM lookup AXI address width is too small");
  end
endmodule
