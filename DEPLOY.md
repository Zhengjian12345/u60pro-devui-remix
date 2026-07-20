# 飞猫分身切卡 - 独立版 v2（无需插件）

## 修复内容

### v2 修复
1. **页面不显示**: `fmsimpin_check_api()` 改为检查 `fmsimpin.html` 文件是否存在，不再依赖 `/api/run_shell`
2. **AT命令不执行**: 改为生成临时脚本文件执行，避免复杂的字符串转义问题

## 文件清单

| 文件 | 部署路径 | 说明 |
|:---|:---|:---|
| htmlmain.c | 仓库 src/htmlmain.c | 修改后的源码 |
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
git commit -m "feat: standalone simswitch v2 - fix page visibility and AT command execution

- fmsimpin_check_api: check fmsimpin.html file instead of /api/run_shell
- simswitch: use temp script file to avoid string escaping issues"
git tag v1.2.15
git push origin v1.2.15
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

### 3. 验证

```bash
# 检查临时脚本是否正确生成
ssh root@192.168.0.1 "ls -la /tmp/.fmsw_*.sh 2>/dev/null"

# 检查日志
cat /tmp/devui-fmsimpin-action.log
```

## 调试

如果仍然无法切卡，在设备上手动测试 AT 命令：

```bash
# 找到 AT 端口
ls /dev/at_mdm* /dev/smd* /dev/at_usb* 2>/dev/null

# 测试发送 AT 命令
cat /dev/at_mdm0 & PID=$!
sleep 0.3
printf 'AT+CLCK="SC",1,"0100"' > /dev/at_mdm0
sleep 2
kill $PID 2>/dev/null
```
