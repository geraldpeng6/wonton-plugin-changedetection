# shellcheck shell=bash
# scripts/smoke.sh 和 e2e/smoke.sh 的插件探测。
# changedetection.io 没有用户体系：上游默认无访问口令，网页只经云吞网关进来，身份由网关会话把守。
# 数据探针经应用自己的 REST API 写一条 watch，升级、重装后断言它还在。

IDENTITY_NA=1
SMOKE_NOTE="应用没有用户体系，也没有应用登录（上游默认无口令）：能打开网页就只有网关认过的主人，身份以网页特征命中为证"
E2E_NOTE="$SMOKE_NOTE"

# 清单里的插件 id（x-wonton.id，安装后不能改）。
plugin_id() { sed -n 's/^  id: //p' "${E2E_DIR:-$SMOKE_DIR}/docker-compose.yml" | head -1; }

# 经核心 API 拿本插件的网页地址（去掉路径）：data_write 在 e2e 导出 E2E_WEB_URL 之前就要用。
plugin_web() {
  local plugins url
  plugins="$(e2e_api GET /_wonton/api/plugins 2>/dev/null)" || return 1
  url="$(jq -r --arg id "$(plugin_id)" --arg json "$plugins" \
    '$json | fromjson | .plugins[] | select(.id==$id) | .web_url // ""' 2>/dev/null)" || return 1
  [[ -n "$url" ]] || return 1
  sed -E 's#^(https?://[^/]+).*#\1#' <<<"$url"
}

# run_hook 在子 shell 里跑，data_write 和 data_check 之间靠落盘传 watch 的 uuid。
probe_uuid_file() { printf '%s/.wonton/probe-watch.uuid' "${E2E_DIR:-$SMOKE_DIR}"; }

# 上游默认开启 REST API 的密钥校验（api_access_token_enabled），令牌存在数据目录的
# changedetection.json 里：数据目录是宿主路径，reinstall 保留数据时令牌不变。
api_token() {
  local dir="$1" f
  f="$1/changedetection.json"
  python3 -c "import json;print(json.load(open('$f'))['settings']['application']['api_access_token'])" 2>/dev/null
}

# URL 只是记录，探针不要求真的抓到（有没有网都验证的是数据本身）。
data_write() {
  local web uuid token body dir
  dir="$(printf '%s/.wonton/data/apps/%s' "${E2E_DIR:-$SMOKE_DIR}" "$(plugin_id | tr . -)")"
  web="$(plugin_web)" || { echo "拿不到插件网页地址"; return 1; }
  token="$(api_token "$dir")" || { echo "读不到 API 令牌（$dir/changedetection.json）"; return 1; }
  body="$(curl -sS --noproxy '*' --fail-with-body -H 'Content-Type: application/json' -H "X-API-KEY: $token" \
    -d "{\"url\":\"https://example.com/\",\"title\":\"wonton-smoke-$(date +%s)\"}" \
    "$web/api/v1/watch")" || { echo "建 watch 失败：$body"; return 1; }
  uuid="$(jq -r '.uuid // empty' <<<"$body")"
  [[ -n "$uuid" ]] || { echo "建 watch 没返回 uuid：$body"; return 1; }
  mkdir -p "$(dirname "$(probe_uuid_file)")" && printf '%s' "$uuid" >"$(probe_uuid_file)"
}

data_check() {
  local web uuid token title dir
  dir="$(printf '%s/.wonton/data/apps/%s' "${E2E_DIR:-$SMOKE_DIR}" "$(plugin_id | tr . -)")"
  uuid="$(cat "$(probe_uuid_file)" 2>/dev/null)"
  [[ -n "$uuid" ]] || { echo "找不到 data_write 写下的 watch uuid"; return 1; }
  web="$(plugin_web)" || { echo "拿不到插件网页地址"; return 1; }
  token="$(api_token "$dir")" || { echo "读不到 API 令牌（$dir/changedetection.json）"; return 1; }
  title="$(curl -sS --noproxy '*' --fail-with-body -H "X-API-KEY: $token" "$web/api/v1/watch/$uuid" 2>/dev/null | jq -r '.title // empty')" ||
    { echo "watch $uuid 查不到（升级或重装后丢了）"; return 1; }
  grep -q '^wonton-smoke-' <<<"$title" || { echo "watch $uuid 的标题对不上：$title"; return 1; }
}

web_assert() { grep -qiE 'new-watch-form|add-watch-url-row'; }   # 标准输入：watch 总览页
