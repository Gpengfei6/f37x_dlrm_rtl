#!/usr/bin/env python3
"""Build A18 kernel as a versioned copy of the accepted A17 kernel.

Does not modify A17 originals. Adds 0x330-0x33C lookup-index staging,
latches indexes with table bases on accepted START, and ignores busy
index writes without raising WRAPPER_ERROR_PENDING.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a17_v1.sv"
DST = ROOT / "rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a18_v1.sv"


def main():
    text = SRC.read_text(encoding="utf-8")
    if "module dlrm_f37x_rtl_kernel_stage2n_a17_v1" not in text:
        raise SystemExit("unexpected A17 kernel header")

    text = text.replace(
        "// Stage 2N-A17.2 v1 F37X four-master public kernel top.\n"
        "//\n"
        "// The verified Stage 2N-A2 kernel remains unchanged at 0x000-0x17F:\n"
        "//   0x000-0x0FF legacy MLP window\n"
        "//   0x100-0x13F standalone interaction window\n"
        "//\n"
        "// The accepted A13 register map remains unchanged through 0x224, including\n"
        "// its four read-only cycle counters. The accepted A15 window at 0x300-0x308\n"
        "// and A16 counters at 0x30C/0x310 are preserved. A17.2 adds three further\n"
        "// 64-bit table bases and four public read-only AXI masters.\n"
        "module dlrm_f37x_rtl_kernel_stage2n_a17_v1 #(",
        "// Stage 2N-A18.1 v1 F37X four-master public kernel top.\n"
        "// Versioned copy of dlrm_f37x_rtl_kernel_stage2n_a17_v1.sv.\n"
        "// A13 through 0x224, A15/A16 0x300-0x310, A17 bases 0x318-0x32C unchanged.\n"
        "// Adds runtime lookup indexes at 0x330-0x33C. CLEAR remains A17: only\n"
        "// DONE->IDLE and ERROR->RECOVER. Busy index writes are ignored, not errors.\n"
        "module dlrm_f37x_rtl_kernel_stage2n_a18_v1 #(",
    )
    text = text.replace(
        "dlrm_internal_pipeline_axi_lite_adapter_stage2n_a17_v1",
        "dlrm_internal_pipeline_axi_lite_adapter_stage2n_a18_v1",
    )
    text = text.replace(
        "dlrm_hbm_pipeline_integration_stage2n_a17_v1",
        "dlrm_hbm_pipeline_integration_stage2n_a18_v1",
    )
    text = text.replace("32'h0002_4E17", "32'h0002_4E18")
    text = text.replace(
        '$error("A17.2 pipeline adapter requires a 32-bit AXI-Lite bus");',
        '$error("A18.1 pipeline adapter requires a 32-bit AXI-Lite bus");',
    )
    text = text.replace(
        '$error("A17.2 pipeline adapter requires NUM_PE=16");',
        '$error("A18.1 pipeline adapter requires NUM_PE=16");',
    )
    text = text.replace(
        '$error("A17.2 pipeline adapter requires signed INT16 activations");',
        '$error("A18.1 pipeline adapter requires signed INT16 activations");',
    )
    text = text.replace(
        '$error("A17.2 m_axi_gmem address width must be 64 bits");',
        '$error("A18.1 m_axi_gmem address width must be 64 bits");',
    )
    text = text.replace(
        '$error("A17.2 m_axi_gmem data width must be 128 bits");',
        '$error("A18.1 m_axi_gmem data width must be 128 bits");',
    )
    text = text.replace(
        '$error("A17.2 m_axi_gmem ID width must be 1 bit");',
        '$error("A18.1 m_axi_gmem ID width must be 1 bit");',
    )

    old_addr = """    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_A17_TABLE_BASE3_HI = 12'h32C;

    localparam logic [15:0] PIPE_CMD_DESC_COMMIT = 16'h0001;"""
    new_addr = """    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_A17_TABLE_BASE3_HI = 12'h32C;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_A18_LOOKUP_INDEX0 = 12'h330;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_A18_LOOKUP_INDEX1 = 12'h334;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_A18_LOOKUP_INDEX2 = 12'h338;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_A18_LOOKUP_INDEX3 = 12'h33C;

    localparam logic [15:0] PIPE_CMD_DESC_COMMIT = 16'h0001;"""
    if old_addr not in text:
        raise SystemExit("address block not found")
    text = text.replace(old_addr, new_addr, 1)

    old_decl = """    logic [3:0][C_M_AXI_GMEM_ADDR_WIDTH-1:0] a17_table_base_stage;"""
    # find the stage declaration - there may be cmd too
    if "a17_table_base_stage" not in text:
        raise SystemExit("table base stage missing")

    # Insert index regs after table-base cmd/stage declarations.
    needle = "    logic [3:0][C_M_AXI_GMEM_ADDR_WIDTH-1:0] a17_table_base_cmd;"
    if needle not in text:
        raise SystemExit("table base cmd missing")
    text = text.replace(
        needle,
        needle
        + "\n    logic [3:0][31:0] a18_lookup_index_stage;"
        + "\n    logic [3:0][31:0] a18_lookup_index_cmd;",
        1,
    )

    old_start = """                        a17_table_base_cmd <= a17_table_base_stage;
                        a15_bottom_descriptor_base_cmd <="""
    new_start = """                        a17_table_base_cmd <= a17_table_base_stage;
                        a18_lookup_index_cmd <= a18_lookup_index_stage;
                        a15_bottom_descriptor_base_cmd <="""
    if old_start not in text:
        raise SystemExit("START latch block not found")
    text = text.replace(old_start, new_start, 1)

    old_rst_seq = """            a17_table_base_cmd <= '0;
            a15_bottom_descriptor_base_cmd <= '0;"""
    new_rst_seq = """            a17_table_base_cmd <= '0;
            a18_lookup_index_cmd[0] <= 32'd37;
            a18_lookup_index_cmd[1] <= 32'd38;
            a18_lookup_index_cmd[2] <= 32'd39;
            a18_lookup_index_cmd[3] <= 32'd40;
            a15_bottom_descriptor_base_cmd <= '0;"""
    if old_rst_seq not in text:
        raise SystemExit("sequencer reset not found")
    text = text.replace(old_rst_seq, new_rst_seq, 1)

    old_rst_stage = """            a17_table_base_stage <= '0;

            for (reset_index = 0; reset_index < 8;"""
    new_rst_stage = """            a17_table_base_stage <= '0;
            a18_lookup_index_stage[0] <= 32'd37;
            a18_lookup_index_stage[1] <= 32'd38;
            a18_lookup_index_stage[2] <= 32'd39;
            a18_lookup_index_stage[3] <= 32'd40;

            for (reset_index = 0; reset_index < 8;"""
    if old_rst_stage not in text:
        raise SystemExit("lite reset stage not found")
    text = text.replace(old_rst_stage, new_rst_stage, 1)

    old_wr = """                    ADDR_A17_TABLE_BASE3_HI: begin
                        if (a15_state != A15_IDLE) begin
                            wrapper_error_latched <= 1'b1;
                            wrapper_error_code <= WRAPPER_ERROR_PENDING;
                        end else begin
                            a17_table_base_stage[3][63:32] <= apply_wstrb32(
                                a17_table_base_stage[3][63:32],
                                wdata_reg, wstrb_reg);
                        end
                    end

                    default: begin"""
    new_wr = """                    ADDR_A17_TABLE_BASE3_HI: begin
                        if (a15_state != A15_IDLE) begin
                            wrapper_error_latched <= 1'b1;
                            wrapper_error_code <= WRAPPER_ERROR_PENDING;
                        end else begin
                            a17_table_base_stage[3][63:32] <= apply_wstrb32(
                                a17_table_base_stage[3][63:32],
                                wdata_reg, wstrb_reg);
                        end
                    end

                    ADDR_A18_LOOKUP_INDEX0: begin
                        if (a15_state == A15_IDLE)
                            a18_lookup_index_stage[0] <= apply_wstrb32(
                                a18_lookup_index_stage[0],
                                wdata_reg, wstrb_reg);
                    end
                    ADDR_A18_LOOKUP_INDEX1: begin
                        if (a15_state == A15_IDLE)
                            a18_lookup_index_stage[1] <= apply_wstrb32(
                                a18_lookup_index_stage[1],
                                wdata_reg, wstrb_reg);
                    end
                    ADDR_A18_LOOKUP_INDEX2: begin
                        if (a15_state == A15_IDLE)
                            a18_lookup_index_stage[2] <= apply_wstrb32(
                                a18_lookup_index_stage[2],
                                wdata_reg, wstrb_reg);
                    end
                    ADDR_A18_LOOKUP_INDEX3: begin
                        if (a15_state == A15_IDLE)
                            a18_lookup_index_stage[3] <= apply_wstrb32(
                                a18_lookup_index_stage[3],
                                wdata_reg, wstrb_reg);
                    end

                    default: begin"""
    if old_wr not in text:
        raise SystemExit("BASE3_HI write block not found")
    text = text.replace(old_wr, new_wr, 1)

    old_rd = """                    ADDR_A17_TABLE_BASE3_HI:
                        s_axi_control_rdata <= a17_table_base_stage[3][63:32];
                    default:
                        s_axi_control_rdata <= 32'd0;"""
    new_rd = """                    ADDR_A17_TABLE_BASE3_HI:
                        s_axi_control_rdata <= a17_table_base_stage[3][63:32];
                    ADDR_A18_LOOKUP_INDEX0:
                        s_axi_control_rdata <= a18_lookup_index_stage[0];
                    ADDR_A18_LOOKUP_INDEX1:
                        s_axi_control_rdata <= a18_lookup_index_stage[1];
                    ADDR_A18_LOOKUP_INDEX2:
                        s_axi_control_rdata <= a18_lookup_index_stage[2];
                    ADDR_A18_LOOKUP_INDEX3:
                        s_axi_control_rdata <= a18_lookup_index_stage[3];
                    default:
                        s_axi_control_rdata <= 32'd0;"""
    if old_rd not in text:
        raise SystemExit("BASE3_HI read block not found")
    text = text.replace(old_rd, new_rd, 1)

    old_port = """        .table_base_addr(a17_table_base_cmd),
        .load_all_req_valid(a15_state == A15_LOAD_REQUEST),"""
    new_port = """        .table_base_addr(a17_table_base_cmd),
        .lookup_index(a18_lookup_index_cmd),
        .load_all_req_valid(a15_state == A15_LOAD_REQUEST),"""
    if old_port not in text:
        raise SystemExit("integration port map not found")
    text = text.replace(old_port, new_port, 1)

    if "ADDR_A18_LOOKUP_INDEX0" not in text:
        raise SystemExit("index addresses missing after transform")
    if "module dlrm_f37x_rtl_kernel_stage2n_a17_v1" in text:
        raise SystemExit("A17 kernel module name still present")
    DST.write_text(text, encoding="utf-8", newline="\n")
    print("WROTE", DST, "bytes", DST.stat().st_size)


if __name__ == "__main__":
    main()
