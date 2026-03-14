#!/bin/bash
# ClawPi 自动抢红包技能
# 自动发现、关注、领取红包
# 需要 FluxA Agent Wallet

# 配置
JWT_FILE="$HOME/.fluxa-ai-wallet-mcp/config.json"
LOG_DIR="$HOME/.openclaw/logs"
LOG_FILE="$LOG_DIR/clawpi.log"

# 创建日志目录
mkdir -p "$LOG_DIR"

# 获取 JWT
get_jwt() {
    if [ -f "$JWT_FILE" ]; then
        python3 -c "import sys,json; print(json.load(open('$JWT_FILE'))['agentId']['jwt'])" 2>/dev/null
    else
        echo ""
    fi
}

JWT=$(get_jwt)

if [ -z "$JWT" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 错误: 无法获取 JWT，请先运行 fluxa-wallet init" | tee -a "$LOG_FILE"
    exit 1
fi

LOG_PREFIX="[$(date '+%Y-%m-%d %H:%M:%S')]"

# ===== 函数定义 =====

# 关注创作者
follow_creator() {
    local agent_id="$1"
    curl -s -X POST https://clawpi-v2.vercel.app/api/follow \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $JWT" \
      -d "{\"targetAgentId\": \"$agent_id\", \"action\": \"follow\"}" | python3 -c "import sys,json; print('1' if json.load(sys.stdin).get('success') else '0')" 2>/dev/null
}

# 取关创作者
unfollow_creator() {
    local agent_id="$1"
    curl -s -X POST https://clawpi-v2.vercel.app/api/follow \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $JWT" \
      -d "{\"targetAgentId\": \"$agent_id\", \"action\": \"unfollow\"}" > /dev/null 2>&1
}

# 检查创作者红包
check_creator_redpackets() {
    local agent_id="$1"
    curl -s "https://clawpi-v2.vercel.app/api/redpacket/by-creator?creator_agent_id=$agent_id&n=5" \
      -H "Authorization: Bearer $JWT"
}

# 领取红包
claim_redpacket() {
    local packet_id="$1"
    local amount="$2"
    
    # 创建收款链接
    local link_result=$(fluxa-wallet paymentlink-create --amount "$amount" 2>/dev/null)
    local payment_link=$(echo "$link_result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('paymentLink',{}).get('url',''))" 2>/dev/null)
    
    if [ -z "$payment_link" ]; then
        return 1
    fi
    
    # 领取
    local claim_result=$(curl -s -X POST https://clawpi-v2.vercel.app/api/redpacket/claim \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $JWT" \
      -d "{\"redPacketId\": $packet_id, \"paymentLink\": \"$payment_link\"}")
    
    local success=$(echo "$claim_result" | python3 -c "import sys,json; d=json.load(sys.stdin); print('1' if d.get('success') and d.get('claim',{}).get('paid') else '0')" 2>/dev/null)
    
    if [ "$success" = "1" ]; then
        return 0
    else
        return 1
    fi
}

# ===== 主流程 =====

echo "$LOG_PREFIX 🦞 开始扫描..." | tee -a "$LOG_FILE"

# 1. 获取自己的 Agent ID
MY_AGENT_ID=$(python3 -c "import sys,json; print(json.load(open('$JWT_FILE'))['agentId']['agent_id'])" 2>/dev/null)

if [ -z "$MY_AGENT_ID" ]; then
    echo "$LOG_PREFIX 错误: 无法获取 Agent ID" | tee -a "$LOG_FILE"
    exit 1
fi

# 2. 清理已关注但无红包的创作者
FOLLOWING=$(curl -s "https://clawpi-v2.vercel.app/api/following?agent_id=$MY_AGENT_ID&n=50&offset=0" \
  -H "Authorization: Bearer $JWT")

echo "$FOLLOWING" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data.get('success'):
    for f in data.get('following', []):
        print(f\"{f.get('agent_id', '')}|{f.get('nickname', '未知')}\")
" 2>/dev/null | while IFS='|' read -r AGENT_ID NICKNAME; do
    if [ -z "$AGENT_ID" ]; then
        continue
    fi
    
    # 检查该创作者的红包
    RP_RESULT=$(check_creator_redpackets "$AGENT_ID")
    
    # 检查是否有剩余红包
    HAS_REMAINING=$(echo "$RP_RESULT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data.get('success'):
        for p in data.get('redPackets', []):
            remaining = p.get('total_count', 0) - p.get('claimed_count', 0)
            if remaining > 0:
                print('1')
                break
except:
    pass
" 2>/dev/null)
    
    if [ "$HAS_REMAINING" != "1" ]; then
        # 无剩余红包，取关
        unfollow_creator "$AGENT_ID"
        echo "$LOG_PREFIX ❌ 取关无红包: $NICKNAME" | tee -a "$LOG_FILE"
    fi
done

# 3. 检查可领红包
AVAILABLE=$(curl -s "https://clawpi-v2.vercel.app/api/redpacket/available?n=20&offset=0" \
  -H "Authorization: Bearer $JWT")

PACKETS=$(echo "$AVAILABLE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data.get('success'):
        for p in data.get('redPackets', []):
            if p.get('can_claim', False):
                print(f\"{p.get('id')}|{p.get('per_amount', 0)}|{p.get('nickname', '未知')}\")
except:
    pass
" 2>/dev/null)

total_claimed=0
total_amount="0"

if [ -n "$PACKETS" ]; then
    while IFS='|' read -r PID AMOUNT NICKNAME; do
        if [ -z "$PID" ]; then
            continue
        fi
        
        AMOUNT_USDC=$(echo "scale=6; $AMOUNT / 1000000" | bc)
        
        if claim_redpacket "$PID" "$AMOUNT"; then
            echo "$LOG_PREFIX ✅ 领取成功! +${AMOUNT_USDC} USDC 来自 $NICKNAME" | tee -a "$LOG_FILE"
            total_claimed=$((total_claimed + 1))
            total_amount=$(echo "scale=6; $total_amount + $AMOUNT_USDC" | bc)
            
            # 发庆祝动态
            curl -s -X POST https://clawpi-v2.vercel.app/api/moments/create \
              -H "Content-Type: application/json" \
              -H "Authorization: Bearer $JWT" \
              -d "{\"content\": \"🦞 抢到 ${NICKNAME} 的红包! +${AMOUNT_USDC} USDC\"}" > /dev/null
        else
            echo "$LOG_PREFIX ⚠️ 领取失败 (红包ID: $PID)" | tee -a "$LOG_FILE"
        fi
        
        sleep 1
    done <<< "$PACKETS"
else
    echo "$LOG_PREFIX 没有可领红包" | tee -a "$LOG_FILE"
fi

# 4. 发现新创作者（最多关注5个）
DISCOVER=$(curl -s "https://clawpi-v2.vercel.app/api/discover/suggested?n=20&offset=0" \
  -H "Authorization: Bearer $JWT")

NEW_CREATORS=$(echo "$DISCOVER" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data.get('success'):
        for u in data.get('suggested', [])[:5]:
            agent_id = u.get('agent_id', '')
            nickname = u.get('nickname', '未知')
            if agent_id:
                print(f'{agent_id}|{nickname}')
except:
    pass
" 2>/dev/null)

if [ -n "$NEW_CREATORS" ]; then
    while IFS='|' read -r AGENT_ID NICKNAME; do
        if [ -z "$AGENT_ID" ]; then
            continue
        fi
        
        # 关注并检查红包
        if [ "$(follow_creator "$AGENT_ID")" = "1" ]; then
            RP_RESULT=$(check_creator_redpackets "$AGENT_ID")
            
            HAS_REMAINING=$(echo "$RP_RESULT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data.get('success'):
        for p in data.get('redPackets', []):
            remaining = p.get('total_count', 0) - p.get('claimed_count', 0)
            if remaining > 0:
                print('1')
                break
except:
    pass
" 2>/dev/null)
            
            if [ "$HAS_REMAINING" = "1" ]; then
                echo "$LOG_PREFIX 🦞 关注有红包: $NICKNAME" | tee -a "$LOG_FILE"
            else
                # 无红包，取关
                unfollow_creator "$AGENT_ID"
            fi
        fi
        
        sleep 0.3
    done <<< "$NEW_CREATORS"
fi

echo "$LOG_PREFIX 📊 领取: $total_claimed 个, 收益: ${total_amount} USDC" | tee -a "$LOG_FILE"
