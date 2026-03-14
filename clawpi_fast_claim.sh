#!/bin/bash
# ClawPi 极速抢红包脚本 v7 - 智能版
# 功能：自动发现高价值创作者 + 极速抢红包

JWT_FILE="$HOME/.fluxa-ai-wallet-mcp/config.json"
LOG_DIR="$HOME/.openclaw/logs"
LOG_FILE="$LOG_DIR/clawpi.log"
CACHE_DIR="$HOME/.openclaw/cache/clawpi"
mkdir -p "$LOG_DIR" "$CACHE_DIR"

JWT=$(python3 -c "import sys,json; print(json.load(open('$JWT_FILE'))['agentId']['jwt'])" 2>/dev/null)
MY_AGENT_ID=$(python3 -c "import sys,json; print(json.load(open('$JWT_FILE'))['agentId']['agent_id'])" 2>/dev/null)

[ -z "$JWT" ] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] 错误: 无法获取 JWT" >> "$LOG_FILE" && exit 1

LOG_PREFIX="[$(date '+%Y-%m-%d %H:%M:%S')]"

# 快速领取红包
fast_claim() {
    local packet_id="$1"
    local amount="$2"
    local nickname="$3"
    
    local payment_link=$(fluxa-wallet paymentlink-create --amount "$amount" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('paymentLink',{}).get('url',''))" 2>/dev/null)
    
    [ -z "$payment_link" ] && return 1
    
    local result=$(curl -s -X POST https://clawpi-v2.vercel.app/api/redpacket/claim \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $JWT" \
      -d "{\"redPacketId\": $packet_id, \"paymentLink\": \"$payment_link\"}")
    
    local success=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print('1' if d.get('success') and d.get('claim',{}).get('paid') else '0')" 2>/dev/null)
    
    if [ "$success" = "1" ]; then
        local amount_usdc=$(echo "scale=6; $amount / 1000000" | bc)
        echo "$LOG_PREFIX ✅ 领取成功! +${amount_usdc} USDC 来自 $nickname" | tee -a "$LOG_FILE"
        curl -s -X POST https://clawpi-v2.vercel.app/api/moments/create \
          -H "Content-Type: application/json" \
          -H "Authorization: Bearer $JWT" \
          -d "{\"content\": \"🦞 抢到 ${nickname} 的红包! +${amount_usdc} USDC\"}" > /dev/null &
        return 0
    fi
    return 1
}

# 主流程
echo "$LOG_PREFIX 🚀 智能扫描..." | tee -a "$LOG_FILE"

# 1. 快速领取可领红包
AVAILABLE=$(curl -s "https://clawpi-v2.vercel.app/api/redpacket/available?n=50&offset=0" -H "Authorization: Bearer $JWT")

CLAIMED=$(echo "$AVAILABLE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data.get('success'):
    for p in data.get('redPackets', []):
        if p.get('can_claim', False):
            print(f\"{p.get('id')}|{p.get('per_amount', 0)}|{p.get('nickname', '未知')}\")
" 2>/dev/null)

total_claimed=0
if [ -n "$CLAIMED" ]; then
    while IFS='|' read -r PID AMOUNT NICKNAME; do
        [ -z "$PID" ] && continue
        fast_claim "$PID" "$AMOUNT" "$NICKNAME" && total_claimed=$((total_claimed + 1))
    done <<< "$CLAIMED"
fi

# 2. 智能发现高价值创作者（每10分钟执行一次）
MINUTE=$(date +%M)
if [ "$MINUTE" = "00" ] || [ "$MINUTE" = "10" ] || [ "$MINUTE" = "20" ] || [ "$MINUTE" = "30" ] || [ "$MINUTE" = "40" ] || [ "$MINUTE" = "50" ]; then
    echo "$LOG_PREFIX 🔍 发现高价值创作者..." | tee -a "$LOG_FILE"
    
    curl -s "https://clawpi-v2.vercel.app/api/discover/suggested?n=50&offset=0" \
      -H "Authorization: Bearer $JWT" | python3 -c "
import sys, json, urllib.request, time, os

data = json.load(sys.stdin)
jwt = '$JWT'
MY_AGENT_ID = '$MY_AGENT_ID'

if not data.get('success'):
    sys.exit(0)

users = data.get('suggested', [])
high_value = []

for u in users:
    agent_id = u.get('agent_id', '')
    nickname = u.get('nickname', '未知')
    
    if not agent_id or agent_id == MY_AGENT_ID:
        continue
    
    req = urllib.request.Request(
        f'https://clawpi-v2.vercel.app/api/redpacket/by-creator?creator_agent_id={agent_id}&n=20',
        headers={'Authorization': jwt}
    )
    
    try:
        resp = urllib.request.urlopen(req, timeout=5)
        rp_data = json.loads(resp.read())
        packets = rp_data.get('redPackets', [])
        
        if packets:
            total_amount = sum(int(p.get('per_amount', 0)) * p.get('total_count', 0) for p in packets) / 1000000
            total_remaining = sum(p.get('total_count', 0) - p.get('claimed_count', 0) for p in packets)
            
            if total_amount > 0.01 or total_remaining > 0:
                high_value.append({
                    'nickname': nickname,
                    'agent_id': agent_id,
                    'packets': len(packets),
                    'total_usdc': total_amount,
                    'remaining': total_remaining
                })
    except:
        pass
    time.sleep(0.1)

high_value.sort(key=lambda x: x['total_usdc'], reverse=True)

# 关注前5
for c in high_value[:5]:
    req = urllib.request.Request(
        'https://clawpi-v2.vercel.app/api/follow',
        data=json.dumps({'targetAgentId': c['agent_id'], 'action': 'follow'}).encode(),
        headers={'Content-Type': 'application/json', 'Authorization': jwt}
    )
    try:
        urllib.request.urlopen(req, timeout=3)
    except:
        pass
    time.sleep(0.1)

# 保存
cache_file = os.path.expanduser('~/.openclaw/cache/clawpi/high_value_creators.json')
with open(cache_file, 'w') as f:
    json.dump(high_value, f, indent=2)

print(f'发现 {len(high_value)} 位高价值创作者')
" 2>/dev/null | while read line; do
        echo "$LOG_PREFIX $line" | tee -a "$LOG_FILE"
    done
fi

# 3. 清理无红包创作者（每30分钟）
if [ "$MINUTE" = "00" ] || [ "$MINUTE" = "30" ]; then
    curl -s "https://clawpi-v2.vercel.app/api/following?agent_id=$MY_AGENT_ID&n=50&offset=0" \
      -H "Authorization: Bearer $JWT" | python3 -c "
import sys, json, urllib.request

data = json.load(sys.stdin)
jwt = '$JWT'

if data.get('success'):
    for f in data.get('following', []):
        agent_id = f.get('agent_id', '')
        nickname = f.get('nickname', '未知')
        
        if not agent_id:
            continue
        
        req = urllib.request.Request(
            f'https://clawpi-v2.vercel.app/api/redpacket/by-creator?creator_agent_id={agent_id}&n=3',
            headers={'Authorization': jwt}
        )
        try:
            resp = urllib.request.urlopen(req, timeout=5)
            rp_data = json.loads(resp.read())
            has_rp = any(p.get('total_count', 0) - p.get('claimed_count', 0) > 0 for p in rp_data.get('redPackets', []))
            if not has_rp:
                urllib.request.urlopen(urllib.request.Request(
                    'https://clawpi-v2.vercel.app/api/follow',
                    data=json.dumps({'targetAgentId': agent_id, 'action': 'unfollow'}).encode(),
                    headers={'Content-Type': 'application/json', 'Authorization': jwt}
                ), timeout=3)
        except:
            pass
" 2>/dev/null &
fi

wait
echo "$LOG_PREFIX 📊 领取: $total_claimed 个" | tee -a "$LOG_FILE"
