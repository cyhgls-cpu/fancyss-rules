
## 三个核心规则库的官方源

| 规则 | 官方源 | 原始格式 | 清洗后格式 |
|------|--------|---------|-----------|
| gfwlist | [gfwlist/gfwlist](https://github.com/gfwlist/gfwlist) | base64 编码的 adblock 规则 | `gfwlist.gz`（纯域名，每行一条） |
| chnlist | [felixonmars/dnsmasq-china-list](https://github.com/felixonmars/dnsmasq-china-list) `accelerated-domains.china.conf` | `server=/域名/ip` | `chnlist.gz`（纯域名） |
| chnroute | [misakaio/chnroutes2](https://github.com/misakaio/chnroutes2) + apnic | 纯 CIDR | `chnroute.txt`（纯 CIDR） |

## 目录结构

```
rules_ng/            # 输出目录，插件 URL_MAIN 指向这里
├── gfwlist.gz
├── chnlist.gz
├── chnroute.txt
├── chnroute6.txt
├── apple_china.txt
├── google_china.txt
├── cdn_test.txt
└── rules.json.js    # 版本索引（插件靠它判断是否更新 + md5 校验）
```

## 本地手动构建

```bash
bash scripts/build_rules.sh rules_ng
```

依赖：`curl`、`gzip`、`base64`、`md5sum`、`awk`、`sed`（Linux 自带），`jq` 可选（用于补元数据字段）。

## 说明

- `rules.json.js` 的结构必须与插件 `ss_rule_update.sh` 读取字段一致：`name` / `md5` / `date` / `count`，否则更新会失败或校验不过。
- 未提及的小规则（white_list / black_list / block_list / adslist / rotlist / udplist）原作者也无官网源或属手维护，本仓库默认不生成，可手动放入 `rules_ng/` 并保持 `rules.json.js` 有对应条目（否则插件更新时会因缺字段跳过，不影响其他规则）。
- 若想手动补齐这些小规则文件，把它们放进 `rules_ng/` 后重新跑一次 `build_rules.sh` 即可让 `rules.json.js` 收录它们（脚本已为其预留 entry）。


