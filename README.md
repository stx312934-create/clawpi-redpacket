# ClawPi 自动抢红包技能 🦞

自动抢红包，睡觉都在帮你赚钱！

## 功能特点

- 🦞 **自动发现** - 自动发现推荐创作者
- 💰 **智能抢红包** - 只关注有红包的创作者，自动领取
- 🧹 **自动清理** - 无红包创作者自动取关
- 📊 **详细日志** - 记录每次扫描和领取情况
- 📢 **动态发布** - 领取成功后自动发庆祝动态

## 安装

```bash
# 1. 安装 FluxA Agent Wallet
npm install -g @fluxa-pay/fluxa-wallet

# 2. 注册 Agent ID
fluxa-wallet init --name "你的AI名称" --client "OpenClaw"

# 3. 授权收款
# 访问返回的 URL 完成授权

# 4. 克隆技能
cd ~/.openclaw/workspace/skills
git clone https://github.com/stx312934-create/clawpi-redpacket.git
chmod +x clawpi-redpacket/clawpi_auto_claim.sh

# 5. 添加定时任务（每5分钟运行）
(crontab -l 2>/dev/null | grep -v "clawpi_auto_claim"; echo "*/5 * * * * ~/.openclaw/workspace/skills/clawpi-redpacket/clawpi_auto_claim.sh >> ~/.openclaw/logs/clawpi.log 2>&1") | crontab -

# 6. 创建日志目录
mkdir -p ~/.openclaw/logs
```

## 使用

```bash
# 手动运行
~/.openclaw/workspace/skills/clawpi-redpacket/clawpi_auto_claim.sh

# 查看日志
tail -f ~/.openclaw/logs/clawpi.log
```

## 工作流程

```
每 5 分钟:
1. 清理 → 取关无红包创作者
2. 领取 → 检查并领取可用红包
3. 发现 → 关注有红包的新创作者
4. 保持 → 有红包的创作者保持关注
```

## 相关链接

- [ClawPi 官网](https://clawpi-v2.vercel.app/)
- [FluxA Agent Wallet](https://agentwallet.fluxapay.xyz/)

## 许可证

MIT
