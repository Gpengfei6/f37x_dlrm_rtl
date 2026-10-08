# KDOT_INTERACTION_C1 XSim 包

这个目录可以随源码树解压后直接运行。脚本用自身位置寻找仓库根，不依赖某一台机器的绝对路径。

## 合同 B

- 输入 27 个向量，每个 16 个 INT16。索引 0 是 Bottom，1..26 是嵌入。
- 输出 367 项。索引 0..15 是 Bottom 原值，不随 `interaction_shift` 改变。
- 索引 16..366 是 351 个点积，顺序 `i=1..26`、`j=0..i-1`。
- 最后一对是 `(26,25)`，配对索引 350，输出索引 366。
- `GOLDEN_VALUE_26_25=156` 只属于尾向量用例的点积值，不是索引。
- 超时是 testbench 里的 400000 个采样周期。

## 内容

- `rtl/interaction/dlrm_feature_interaction_kaggle_c1_v1.sv`
- `tb/tb_dlrm_feature_interaction_kaggle_c1_v1.sv`
- `tb/ref/kaggle_interaction_c1_ref_v1.py`
- `tb/generated/kaggle_c1_cases_v1.svh`
- `scripts/kdot_interaction_c1/filelist_v1.f`
- `scripts/kdot_interaction_c1/filelist_toy_v1.f`
- `scripts/kdot_interaction_c1/run_kdot_interaction_c1_v1.sh`
- `scripts/kdot_interaction_c1/MANIFEST.sha256`

Toy 源文件只在回归步骤读取，本包不修改它们。

## 在 Vivado 2020.2 的机器上运行

把 `VIVADO_SETTINGS` 指到那台机器自己的 `settings64.sh`，然后在解压后的树根执行：

```bash
export VIVADO_SETTINGS=/path/to/Vivado/2020.2/settings64.sh
bash scripts/kdot_interaction_c1/run_kdot_interaction_c1_v1.sh
sha256sum -c scripts/kdot_interaction_c1/MANIFEST.sha256
```

脚本会先重写 golden，再调用 `xvlog`、`xelab`、`xsim`。没有这三个命令时，状态文件保持 `NOT_RUN`，不会写成 PASS。

通过条件是仿真日志里出现全部 `PASS always_ready case 0` 到 `case 12`、五个非零 shift 的 Bottom 直通、反压、末项暂停、复位、连续请求、非法 shift，以及 `KDOT_INTERACTION_C1_PASS`。缺任何一行都是 FAIL。

日志写到 `docs/evidence/kdot_interaction_c1/`，可用 `KDOT_OUT` 改到别的相对或绝对目录。
