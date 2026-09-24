#!/bin/bash
# fancyss 规则库构建脚本（替代原作者 hq450/fancyss 的 rules_ng 更新源）
#
# 用途：定时拉取第三方官方规则源，清洗成 fancyss 可用的格式，
#       并生成 rules.json.js 版本索引文件。
#
# 输出目录结构（对应插件 URL_MAIN 指向的目录）：
#   rules_ng/
#   ├── gfwlist.gz
#   ├── chnlist.gz
#   ├── chnroute.txt
#   ├── chnroute6.txt
#   ├── apple_china.txt
#   ├── google_china.txt
#   ├── cdn_test.txt
#   ├── white_list.txt
#   ├── black_list.txt
#   ├── block_list.txt
#   ├── adslist.gz
#   ├── rotlist.txt
#   ├── udplist.txt
#   └── rules.json.js
#
# 由 GitHub Actions 或本地 crontab 调用：
#   bash build_rules.sh <输出目录>

set -u

OUT_DIR="${1:-rules_ng}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$OUT_DIR"

# ---------- 工具函数 ----------
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# 从 dnsmasq-china-list 的 *.conf（server=/域名/ip）中提取纯域名
extract_domain_from_conf() {
    # 输入：server=/example.com/114.114.114.114 或含 ipset 等注释
    sed -E 's/^[[:space:]]*server=\/([^/]+)\/.*/\1/' | \
        grep -v '^#' | grep -v '^$' | grep -E '^[a-zA-Z0-9_.-]+$'
}

# 标准化域名文件：去空行、去注释、小写、排序、去重
normalize_domains() {
    grep -vE '^\s*(#|!|$)' | tr '[:upper:]' '[:lower:]' | \
        sed -E 's/[[:space:]]+//g' | sort -u
}

# 下载，失败返回非0
fetch() {
    curl -fsSL --retry 3 --connect-timeout 20 --max-time 120 "$1"
}

# ---------- 1. gfwlist（被墙域名）----------
# 主源：Loyalsoldier/v2ray-rules-dat 的 gfw.txt（纯域名、社区活跃、每日更新）
# 补充源：官方 gfwlist/gfwlist（base64 编码的 adblock 规则）
# 策略：合并两者去重，覆盖最全
build_gfwlist() {
    log "构建 gfwlist ..."
    : > "$WORK/gfwlist.txt"

    # 主源：Loyalsoldier gfw.txt（纯域名）
    fetch "https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/gfw.txt" 2>/dev/null \
        | normalize_domains | grep -E '\.' >> "$WORK/gfwlist.txt"

    # 补充源：官方 gfwlist（base64 adblock）
    local raw="$WORK/gfwlist_raw.txt"
    if fetch "https://raw.githubusercontent.com/gfwlist/gfwlist/master/gfwlist.txt" > "$raw" 2>/dev/null; then
        base64 -d "$raw" 2>/dev/null > "$WORK/gfwlist_dec.txt" || cp "$raw" "$WORK/gfwlist_dec.txt"
        sed -E '
            s/^\|\|([a-zA-Z0-9_.-]+)\^?.*$/\1/
            s/^\|?https?:\/\/([a-zA-Z0-9_.-]+)[/[:space:]].*$/\1/
        ' "$WORK/gfwlist_dec.txt" | \
            grep -vE '^(\||@@|!|/|\*)' | \
            normalize_domains | grep -E '\.' >> "$WORK/gfwlist.txt"
    fi

    # 补充源：blackmatrix7 Proxy（被墙/成人站，更新极快，补齐原作者的成人/敏感站）
    if fetch "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Proxy/Proxy.list" > "$WORK/bm_proxy.txt" 2>/dev/null; then
        grep -E '^(DOMAIN|DOMAIN-SUFFIX),' "$WORK/bm_proxy.txt" | \
            sed -E 's/^(DOMAIN|DOMAIN-SUFFIX),//' | \
            normalize_domains | grep -E '\.' >> "$WORK/gfwlist.txt"
    fi

    sort -u "$WORK/gfwlist.txt" -o "$WORK/gfwlist.txt"
    gzip -9 -c "$WORK/gfwlist.txt" > "$OUT_DIR/gfwlist.gz"
    log "gfwlist: $(wc -l < "$WORK/gfwlist.txt") 条"
}

# ---------- 2. chnlist（大陆域名）----------
# 官方源：felixonmars/dnsmasq-china-list 的 accelerated-domains.china.conf
build_chnlist() {
    log "构建 chnlist ..."
    fetch "https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/accelerated-domains.china.conf" > "$WORK/chnlist.conf" || return 1
    extract_domain_from_conf < "$WORK/chnlist.conf" | normalize_domains > "$WORK/chnlist.txt"
    gzip -9 -c "$WORK/chnlist.txt" > "$OUT_DIR/chnlist.gz"
    log "chnlist: $(wc -l < "$WORK/chnlist.txt") 条"
}

# ---------- 3. chnroute（大陆 IPv4 CIDR）----------
# 官方源：misakaio/chnroutes2 的 chnroute.txt（纯 CIDR）；也可叠加 apnic
build_chnroute() {
    log "构建 chnroute ..."
    fetch "https://raw.githubusercontent.com/misakaio/chnroutes2/master/chnroutes.txt" > "$WORK/chnroute_v4.txt" || return 1
    # 可选：叠加 apnic 国内段（保证和原作者 "merged" 行为接近）
    fetch "https://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest" > "$WORK/apnic.txt" 2>/dev/null || true
    if [ -s "$WORK/apnic.txt" ]; then
        awk -F'|' '$1=="apnic" && $2=="CN" && $3=="ipv4" {print $4"/"32-log($5)/log(2)}' "$WORK/apnic.txt" >> "$WORK/chnroute_v4.txt"
    fi
    grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$' "$WORK/chnroute_v4.txt" | sort -u > "$OUT_DIR/chnroute.txt"
    log "chnroute: $(wc -l < "$OUT_DIR/chnroute.txt") 条"
}

# ---------- 4. chnroute6（大陆 IPv6 CIDR）----------
build_chnroute6() {
    log "构建 chnroute6 ..."
    fetch "https://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest" > "$WORK/apnic6.txt" 2>/dev/null || return 1
    awk -F'|' '$1=="apnic" && $2=="CN" && $3=="ipv6" {print $4"/"$5}' "$WORK/apnic6.txt" | sort -u > "$OUT_DIR/chnroute6.txt"
    log "chnroute6: $(wc -l < "$OUT_DIR/chnroute6.txt") 条"
}

# ---------- 5. 其他辅助规则（来自 dnsmasq-china-list）----------
build_apple_china() {
    log "构建 apple_china ..."
    fetch "https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/apple.china.conf" | \
        extract_domain_from_conf | normalize_domains > "$OUT_DIR/apple_china.txt"
    log "apple_china: $(wc -l < "$OUT_DIR/apple_china.txt") 条"
}

build_google_china() {
    log "构建 google_china ..."
    fetch "https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/google.china.conf" | \
        extract_domain_from_conf | normalize_domains > "$OUT_DIR/google_china.txt"
    log "google_china: $(wc -l < "$OUT_DIR/google_china.txt") 条"
}

build_cdn_test() {
    log "构建 cdn_test ..."
    fetch "https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/cdn-testlist.txt" | \
        normalize_domains | grep -E '\.' > "$OUT_DIR/cdn_test.txt"
    log "cdn_test: $(wc -l < "$OUT_DIR/cdn_test.txt") 条"
}

# ---------- 5.5 adslist（广告域名，来自 anti-ad）----------
build_adslist() {
    log "构建 adslist ..."
    fetch "https://anti-ad.net/domains.txt" | normalize_domains | grep -E '\.' > "$WORK/adslist.txt"
    gzip -9 -c "$WORK/adslist.txt" > "$OUT_DIR/adslist.gz"
    log "adslist: $(wc -l < "$WORK/adslist.txt") 条"
}

# ---------- 6. 生成 rules.json.js 索引 ----------
# 该文件结构必须与插件 ss_rule_update.sh 完全一致：
#   { "<key>": { "name", "date", "md5", "count", ... } }
# date 格式：YYYY-MM-DD HH:MM
gen_rules_json() {
    log "生成 rules.json.js ..."
    local ts
    ts="$(date '+%Y-%m-%d %H:%M')"

    local json="$WORK/rules.json.js"
    echo "{" > "$json"

    entry() {
        # $1 key  $2 filename
        local key="$1" file="$2"
        local md5 count
        md5="$(md5sum "$OUT_DIR/$file" 2>/dev/null | awk '{print $1}')"
        if echo "$file" | grep -q '\.gz$'; then
            count="$(gzip -dc "$OUT_DIR/$file" 2>/dev/null | grep -cE '.')"
        else
            count="$(grep -cE '.' "$OUT_DIR/$file" 2>/dev/null)"
        fi
        [ -z "$count" ] && count="0"
        echo "  \"$key\": {\"name\":\"$file\",\"date\":\"$ts\",\"md5\":\"$md5\",\"count\":\"$count\"},"
    }

    entry "gfwlist"   "gfwlist.gz"    >> "$json"
    entry "chnlist"   "chnlist.gz"    >> "$json"
    entry "chnroute"  "chnroute.txt"  >> "$json"
    entry "chnroute6" "chnroute6.txt" >> "$json"
    entry "apple_china" "apple_china.txt" >> "$json"
    entry "google_china" "google_china.txt" >> "$json"
    entry "cdn_test"   "cdn_test.txt"   >> "$json"
    # 静态/无官网源的小规则：保持现状（可选，见 README）
    entry "white_list" "white_list.txt" >> "$json"
    entry "black_list" "black_list.txt" >> "$json"
    entry "block_list" "block_list.txt" >> "$json"
    entry "adslist"   "adslist.gz"     >> "$json"
    entry "rotlist"   "rotlist.txt"    >> "$json"
    entry "udplist"   "udplist.txt"    >> "$json"

    # 去掉最后一行末尾的逗号，并补上额外元数据字段（与原版结构兼容）
    # 说明：chnlist 原版有 note；chnroute 有 source；这些是可选展示字段
    sed -i '$ s/,$//' "$json"
    echo "}" >> "$json"

    # 用 jq 校验 + 补元数据（可选，若环境有 jq）
    if command -v jq >/dev/null 2>&1; then
        jq '.chnlist.note="merged from dnsmasq-china-list" |
            .chnroute.source="merged" |
            .chnroute6.source="apnic"' "$json" > "$json.tmp" && mv "$json.tmp" "$json"
    fi

    cp "$json" "$OUT_DIR/rules.json.js"
    log "rules.json.js 生成完毕"
}

# ---------- 主流程 ----------
main() {
    build_gfwlist     || log "gfwlist 构建失败（跳过）"
    build_chnlist     || log "chnlist 构建失败（跳过）"
    build_chnroute    || log "chnroute 构建失败（跳过）"
    build_chnroute6   || log "chnroute6 构建失败（跳过）"
    build_apple_china || log "apple_china 构建失败（跳过）"
    build_google_china|| log "google_china 构建失败（跳过）"
    build_cdn_test    || log "cdn_test 构建失败（跳过）"
    build_adslist    || log "adslist 构建失败（跳过）"
    gen_rules_json

    log "全部完成。输出目录：$OUT_DIR"
}

main
