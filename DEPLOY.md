# 飞猫分身切卡部署说明

## 文件清单

| 文件 | 部署路径 | 说明 |
|:---|:---|:---|
| htmlmain.c | 仓库 src/htmlmain.c | 修改后的源码，需要编译 |
| fmsimpin.sh | /data/plugins/u60pro-devui/fmsimpin.sh | AT切卡脚本 |
| fmsimpin.html | /data/plugins/u60pro-devui/ui/subpages/fmsimpin.html | 切卡页面 |

## 部署步骤

### 1. 编译 htmlmain.c

```bash
cd u60pro-devui-remix
git add src/htmlmain.c
git commit -m "refactor: replace custom fmswitch with upstream simswitch via plugin_action_submit"
git tag v1.2.13
git push origin v1.2.13
```

等待 GitHub Actions 编译完成，下载 Release 中的二进制文件。

### 2. 部署到设备

```bash
# 推送到设备
scp u60pro-devui root@192.168.0.1:/tmp/
scp fmsimpin.sh root@192.168.0.1:/data/plugins/u60pro-devui/
scp fmsimpin.html root@192.168.0.1:/data/plugins/u60pro-devui/ui/subpages/

# 设置权限
ssh root@192.168.0.1 "chmod +x /data/plugins/u60pro-devui/fmsimpin.sh"

# 重启 devui
ssh root@192.168.0.1 "cp /tmp/u60pro-devui /data/plugins/u60pro-devui/ && killall u60pro-devui; sleep 1; /data/plugins/u60pro-devui/u60pro-devui &"
```

## 前提条件

- 设备已安装 FMSimPIN 浏览器插件（提供 /api/run_shell 接口）
- 使用飞猫分身卡（支持 PIN 切卡）

## 动作变更

| 旧动作 | 新动作 |
|:---|:---|
| act:fmswitch:0100 | act:simswitch:0100 |
| act:fmswitch:0200 | act:simswitch:0200 |
| act:fmswitch:0300 | act:simswitch:0300 |
