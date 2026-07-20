# 飞猫分身切卡 - 独立版（无需插件）

## 说明

此版本**完全脱离 FMSimPIN 浏览器插件**，直接在 `htmlmain.c` 中通过 `system()` 发送 AT 命令到设备端口。

## 文件清单

| 文件 | 部署路径 | 说明 |
|:---|:---|:---|
| htmlmain.c | 仓库 src/htmlmain.c | 修改后的源码，需要编译 |
| fmsimpin.html | /data/plugins/u60pro-devui/ui/subpages/fmsimpin.html | 切卡页面 |

## 不再需要

- ❌ FMSimPIN 浏览器插件
- ❌ fmsimpin.sh 脚本
- ❌ /api/run_shell 接口

## 部署步骤

### 1. 编译

```bash
cd u60pro-devui-remix
git add src/htmlmain.c
git commit -m "feat: standalone simswitch without FMSimPIN plugin

- Remove dependency on /api/run_shell and FMSimPIN browser plugin
- Send AT+CLCK commands directly via system() to AT ports
- Auto-detect AT port from /dev/at_mdm0 /dev/at_mdm1 /dev/at_usb0 /dev/smd7 /dev/smd11"
git tag v1.2.14
git push origin v1.2.14
```

等待 GitHub Actions 编译完成。

### 2. 部署到设备

```bash
scp u60pro-devui root@192.168.0.1:/tmp/
scp fmsimpin.html root@192.168.0.1:/data/plugins/u60pro-devui/ui/subpages/

ssh root@192.168.0.1 "
  cp /tmp/u60pro-devui /data/plugins/u60pro-devui/
  killall u60pro-devui
  sleep 1
  /data/plugins/u60pro-devui/u60pro-devui &
"
```

## 技术细节

AT 命令通过以下端口顺序自动检测：
1. `/dev/at_mdm0`
2. `/dev/at_mdm1`
3. `/dev/at_usb0`
4. `/dev/smd7`
5. `/dev/smd11`

发送的命令：`AT+CLCK="SC",1,"PIN"`
