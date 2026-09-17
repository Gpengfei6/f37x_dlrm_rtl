# A13/A17 实现事实核对

日期：2026-09-15。只记录能从本仓库 **RTL / 配置 / 模型清单 / 已有验收文档** 对上的内容。  
对不上的标 **NOT_CONFIRMED**。不根据论文或记忆补写。不声称理论最高频率。

---

## 1. 定点 / 整数位宽

### 1.1 A13/A17 流水线参数（RTL）

`dlrm_hbm_pipeline_integration_stage2n_a17_v1.sv` 与 A13 控制器默认参数一致，且 A17 用 `initial` 断言核对 embedding 口：

| 量 | 位宽（源码） | 出处 |
|---|---:|---|
| 激活 / embedding 通道 `INPUT_WIDTH` | 16 | A13 控制器、A17 集成 |
| 权重 `WEIGHT_WIDTH` | 8 | 同上 |
| 偏置 `BIAS_WIDTH` | 24 | 同上 |
| 累加器 `ACC_WIDTH` | 48 | 同上 |
| 输出 `OUTPUT_WIDTH` | 16 | 同上 |
| HBM 元素 `HBM_ELEMENT_WIDTH` | 16 | A17 集成；要求与 `INPUT_WIDTH` 相同 |
| 特征交互输入/输出元素 | 16 | `dlrm_feature_interaction_engine.sv` |
| 交互点积累加 | 48 | 同上 |

A17 注释写明：signed INT16 embedding 通道。  
`models/stage2m/stage2m_trained_hybrid_dlrm_manifest.json` 的 `quantization` 字段：`activation=int16`，`weight=int8`，`bias=int24`，`accumulator=signed_int48`。

### 1.2 二进制小数点 / Q 格式

| 项 | 状态 |
|---|---|
| A13/A17 各 16 位通道的小数位数 | **NOT_CONFIRMED**（RTL 只给位宽；未在 A17 模块内写 Q 格式） |
| 早期 `docs/fixed_point_spec_v0.md` 的 INT8 Q3.4 / INT32 累加器 | 对应早期 `config/model_config.json`，**不能**直接当作 A13 板级合同 |
| 模型清单中的 `interaction_shift` / `dense_scale_log2` 等 | 见 `stage2m` manifest；运行时交互移位由 Host 写入 `0x1FC`，具体每次写入值以 Host/模型资产为准 |

Host 读回最终结果时按 **有符号 16 位** 解释 `0x200` 的低 16 位（`stage2n_a17_6_four_bo_host_v1.cpp`）。

---

## 2. Embedding 向量宽度

| 项 | 事实 |
|---|---|
| 通道数 | 8（`HBM_DIM=8`，A13 embedding 口 `8*INPUT_WIDTH`） |
| 每通道 | 16 bit |
| 整行 | 128 bit = 16 字节（A14 v2：`DIM*ELEMENT_WIDTH==DATA_WIDTH`，`ROW_BYTES==16`） |
| 表行数（查找引擎参数） | 64（`HBM_ROWS` / A14 `ROWS`） |
| Host BO 载荷 | 1024 字节 = 64×16（A17 Host `kPayloadBytes`） |

---

## 3. AXI 数据 / 地址宽度

| 口 | 事实 |
|---|---|
| AXI4-Lite | 地址 12 bit，数据 32 bit（A13/A17 内核参数） |
| A13 内核 | **无** `m_axi` |
| A16 | 一个 `m_axi_gmem`：地址 64 bit，数据 128 bit，ID 1 bit |
| A17 | 四个 `m_axi_gmem0..3`：同样 64/128/1 |
| 写通道 | A17 顶层 `m_axi_gmem*_awvalid = 0`（只读查找） |
| 突发 | A14 v2：`arlen=0`（单拍），`arburst=INCR`，`arsize=$clog2(128/8)=4`（16 字节） |

---

## 4. 地址计算

A14 v2（A16/A17 均例化）：

```text
byte_offset = lookup_index << 4
address     = table_base_addr + byte_offset
```

要求：`table_base_addr[3:0]==0`；`index < ROWS`；加法无 64 位溢出。否则报错、不发 AR。

A17 集成层把四个 index **写死**，与参数 `SLOT0_LOOKUP_INDEX` … `SLOT3_LOOKUP_INDEX` 一致：

```text
slot0 → row 37
slot1 → row 38
slot2 → row 39
slot3 → row 40
```

源码中的 packed 拼接 `{32'd40, 32'd39, 32'd38, 32'd37}` 与上表相同（最低位是 slot0=37），不是普通列表从左到右的 slot0。

---

## 5. A17 的四个表基地址

**不是编译期常量。**

| 槽 | 寄存器（低 32 / 高 32） | 运行时来源 |
|---|---|---|
| 0 | `0x304` / `0x308` | BO0 的 `paddr` |
| 1 | `0x318` / `0x31C` | BO1 的 `paddr` |
| 2 | `0x320` / `0x324` | BO2 的 `paddr` |
| 3 | `0x328` / `0x32C` | BO3 的 `paddr` |

链接意图（`config/stage2n_a17_6_target_v1.cfg`）：`gmemi → HBM[i]`。  
某一次板上分配得到的具体物理地址：**NOT_CONFIRMED**（随 XRT 分配变化；不要把某次 log 里的 paddr 写成 ABI）。

---

## 6. 时钟口径

| 项 | 事实 | 出处 |
|---|---|---|
| 请求的内核周期 | 10.000 ns | `constraints/stage2n_a13_cycle_counter_100mhz_v1.xdc`；A13/A16.2 验收文 |
| 与 100 MHz 的关系 | 周期 10 ns 即频率 100 MHz | 同一约束/验收表 |
| A16.2 / A17.6 链接请求 | `--kernel_frequency 100` | A16.2 验收；`scripts/run_stage2n_a17_6_build_v1.py` |
| 含义 | **当前构建与时序门限的目标时钟** | 验收文写明 WNS=0 只表示该门限通过 |
| 器件理论最高频率 / Fmax 扫描 | **NOT_CONFIRMED** | 仓库无以更高频率作为签核目标的源码依据 |
| 把周期计数直接换成纳秒墙钟 | 仅在“每个计数边沿对应一个 `ap_clk` 周期、且该次运行内核确为 100 MHz”时才是 10 ns/周期；Host 墙钟是另一栏 | 计数器在 `ap_clk` 上累加；是否每次板上都锁在 100 MHz 以当时 xclbin 时序报告为准 |

A13 验收记录请求时钟 100.000 MHz、周期 10.000 ns。这是签核目标，不是“还能跑多快”的结论。

---

## 7. 拓扑（避免误读）

| 项 | 事实 |
|---|---|
| Bottom | 8 → 16 → 8（`docs/ARCHITECTURE.md` 与 stage2m 清单） |
| 交互 | 5 个 8 维向量 → 18 维（不是卷积） |
| Top | 18 → 32 → 16 → 1 |
| A17 查找 | 四槽固定行：`slot0→37`，`slot1→38`，`slot2→39`，`slot3→40`；不是多表运行时调度 |
