# 双卡管理 / 双卡流量子分页

本 Remix 在“更多功能”页集成两个自定义子分页：

| 页面 | 路径 | 作用 |
|------|------|------|
| 双卡管理 | `ui/functions/sim-switch.html` | 单卡/双卡模式、智能切换、数据卡选择 |
| 双卡流量 | `ui/functions/sim-traffic.html` | 双卡今日/本月用量与剩余额度展示 |

页面通过 `{{CUSTOMFUNCTIONTILES}}` 自动扫描出现在更多功能列表中。

## 设备路径

```text
/data/plugins/u60pro-devui/ui/functions/sim-switch.html
/data/plugins/u60pro-devui/ui/functions/sim-traffic.html
/data/plugins/u60pro-devui/simctl.sh
```

`simctl.sh` 是 DevUI 允许调用的固定控制脚本（与 `cpuctl.sh` / `tsctl.sh` 同一模式），只接受有限子命令：

```sh
simctl.sh status
simctl.sh single
simctl.sh dual
simctl.sh slot 1|2
simctl.sh auto 0|1
```

底层通过 U60Pro `ubus` 调用 `zwrt_zte_mdm.api`：

- `get_sim_info_before` — 读双卡状态
- `zwrt_mdm_change_provision_session` — 单卡/双卡驻网
- `zwrt_zte_mdm_activate_sim` — 切换数据卡
- `st_set_auto_switch_slot` — 智能双卡切换

## 屏幕动作

| act | 含义 |
|-----|------|
| `act:simsingle` | 单卡模式 |
| `act:simdual` | 双卡双待 |
| `act:simslot:1` / `act:simslot:2` | 切换数据卡 |
| `act:simauto:0` / `act:simauto:1` | 关闭/开启智能切换 |
| `act:simrefresh` | 刷新状态 |

## 可选流量采集器

`sim-traffic.html` 默认用 `simctl.sh status` 读取基础 SIM 状态，并尽量解析：

```text
/data/plugins/dual-sim-traffic/state.json
```

若安装了社区/自研 collector（例如设备上的 `dual-sim-traffic/collector.lua`），剩余套餐、今日累计等会更完整。未安装时页面仍可打开，用量字段显示为 `-`。

## 安装

```sh
adb shell 'mkdir -p /data/plugins/u60pro-devui/ui/functions'
adb push ui/functions/sim-switch.html /data/plugins/u60pro-devui/ui/functions/
adb push ui/functions/sim-traffic.html /data/plugins/u60pro-devui/ui/functions/
adb push scripts/simctl.sh /data/plugins/u60pro-devui/simctl.sh
adb shell 'chmod 755 /data/plugins/u60pro-devui/simctl.sh'
# 触碰功能页以刷新入口
adb shell 'touch /data/plugins/u60pro-devui/ui/02-functions.html'
```

双卡管理入口只在 `simctl.sh` 可执行时显示（与 tailscale/mihomo/cpu 页面的“控制器可用才显示”策略一致）。双卡流量页只要文件存在即可显示。
