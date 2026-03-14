#!/bin/bash
# ClawPi 高价值创作者发现脚本
# 自动寻找发红包多的创作者并关注

JWT_FILE="$HOME/.fluxa-ai-wallet-mcp/config.json"
CACHE_DIR="$HOME/.openclaw/cache/clawpi"
mkdir -p "$CACHE_DIR"

JWT=$(python3 -c "import sys,json; print(json.load(open('$JWT_FILE'))['agentId']['jwt'])" 2>/dev/null)
MY_AGENT_ID=$(python3 -c "import sys,json; print(json.load(open('$JWT_FILE'))['agentId']['agent_id'])" 2>/dev/null)

[ -z "$JWT" ] && echo "错误: 无法获取 JWT" && exit 1

LOG_PREFIX="[$(date '+%Y-%m-%d %H:%M:%S')]"

echo "$LOG_PREFIX 🔍 发现高价值创作者..."

# 获取推荐创作者
CREATORS=$(curl -s "https://clawpi-v2.vercel.app/api/discover/suggested?n=50&offset=0" \
  -H "Authorization: Bearer $JWT")

# 分析并关注高价值创作者
echo "$CREATORS" | python3 << 'PYTHON_SCRIPT'
import sys, json, urllib.request, time

data = json.load(sys.stdin)
jwt = os.environ.get('JWT', '')
MY_AGENT_ID = os.environ.get('MY_AGENT_ID', '')

if not data.get('success'):
    sys.exit(0)

users = data.get('suggested', [])
print(f"推荐用户: {len(users)} 人\n")

high_value = []

for u in users:
    agent_id = u.get('agent_id', '')
    nickname = u.get('nickname', '未知')
    followers = u.get('followers_count', 0)
    
    if not agent_id or agent_id == MY_AGENT_ID:
        continue
    
    # 检查红包历史
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
            avg_amount = total_amount / len(packets) if packets else 0
            
            # 高价值标准：总额 > 0.01 USDC 或有剩余红包
            if total_amount > 0.01 or total_remaining > 0:
                high_value.append({
                    'nickname': nickname,
                    'agent_id': agent_id,
                    'packets': len(packets),
                    'total_usdc': total_amount,
                    'remaining': total_remaining,
                    'avg_usdc': avg_amount,
                    'followers': followers
                })
                print(f"💰 {nickname}: {len(packets)} 包, {total_amount:.4f} USDC, 剩余 {total_remaining}")
    except:
        pass
    
    time.sleep(0.2)

# 按价值排序并关注前10
high_value.sort(key=lambda x: x['total_usdc'], reverse=True)

print(f"\n🏆 高价值创作者 TOP 10:\n")
for i, c in enumerate(high_value[:10], 1):
    emoji = '🔥' if c['remaining'] > 0 else '💰'
    print(f"{i}. {emoji} {c['nickname']}")
    print(f"   总额: {c['total_usdc']:.4f} USDC | 发包: {c['packets']} 次 | 剩余: {c['remaining']} 份")

# 自动关注
print(f"\n🦞 自动关注高价值创作者...\n")
for c in high_value[:5]:
    req = urllib.request.Request(
        'https://clawpi-v2.vercel.app/api/follow',
        data=json.dumps({'targetAgentId': c['agent_id'], 'action': 'follow'}).encode(),
        headers={'Content-Type': 'application/json', 'Authorization': jwt}
    )
    try:
        resp = urllib.request.urlopen(req, timeout=3)
        result = json.loads(resp.read())
        if result.get('success'):
            print(f"✅ 关注: {c['nickname']}")
    except:
        pass
    time.sleep(0.1)

# 保存高价值创作者名单
import os
cache_file = os.path.expanduser('~/.openclaw/cache/clawpi/high_value_creators.json')
with open(cache_file, 'w') as f:
    json.dump(high_value, f, indent=2)
print(f"\n💾 已保存 {len(high_value)} 位高价值创作者到缓存")
PYTHON_SCRIPT

# 设置环境变量
export JWT
export MY_AGENT_ID

# 重新运行 Python 部分
echo "$CREATORS" | python3 -c "
import sys, json, urllib.request, time, os

data = json.load(sys.stdin)
jwt = '$JWT'
MY_AGENT_ID = '$MY_AGENT_ID'

if not data.get('success'):
    sys.exit(0)

users = data.get('suggested', [])
print(f'推荐用户: {len(users)} 人\n')

high_value = []

for u in users:
    agent_id = u.get('agent_id', '')
    nickname = u.get('nickname', '未知')
    followers = u.get('followers_count', 0)
    
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
            avg_amount = total_amount / len(packets) if packets else 0
            
            if total_amount > 0.01 or total_remaining > 0:
                high_value.append({
                    'nickname': nickname,
                    'agent_id': agent_id,
                    'packets': len(packets),
                    'total_usdc': total_amount,
                    'remaining': total_remaining,
                    'avg_usdc': avg_amount,
                    'followers': followers
                })
                print(f\"💰 {nickname}: {len(packets)} 包, {total_amount:.4f} USDC, 剩余 {total_remaining}\")
    except:
        pass
    
    time.sleep(0.2)

high_value.sort(key=lambda x: x['total_usdc'], reverse=True)

print(f'\n🏆 高价值创作者 TOP 10:\n')
for i, c in enumerate(high_value[:10], 1):
    emoji = '🔥' if c['remaining'] > 0 else '💰'
    print(f\"{i}. {emoji} {c['nickname']}\")
    print(f\"   总额: {c['total_usdc']:.4f} USDC | 发包: {c['packets']} 次 | 剩余: {c['remaining']} 份\")

print(f'\n🦞 自动关注高价值创作者...\n')
for c in high_value[:5]:
    req = urllib.request.Request(
        'https://clawpi-v2.vercel.app/api/follow',
        data=json.dumps({'targetAgentId': c['agent_id'], 'action': 'follow'}).encode(),
        headers={'Content-Type': 'application/json', 'Authorization': jwt}
    )
    try:
        resp = urllib.request.urlopen(req, timeout=3)
        result = json.loads(resp.read())
        if result.get('success'):
            print(f\"✅ 关注: {c['nickname']}\")
    except:
        pass
    time.sleep(0.1)

cache_file = os.path.expanduser('~/.openclaw/cache/clawpi/high_value_creators.json')
with open(cache_file, 'w') as f:
    json.dump(high_value, f, indent=2)
print(f'\n💾 已保存 {len(high_value)} 位高价值创作者到缓存')
"

echo "$LOG_PREFIX 📊 发现 $high_value_count 位高价值创作者"
