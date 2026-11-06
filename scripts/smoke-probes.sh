# shellcheck shell=bash
# scripts/smoke.sh 和 e2e/smoke.sh 的插件探测。
# changedetection.io 没有用户体系：上游默认无访问口令，网页只经云吞网关进来，身份由网关会话把守。
# 数据探针走应用自己的快速添加表单（POST /form/add）写一条 watch——REST API 默认开密钥校验，
# 令牌存在容器数据里，钩子契约里拿不到；data_check 断言这条 watch 的 URL 还在总览页。

# shellcheck disable=SC2034  # 由开发套件 probes.sh 与 e2e/smoke.sh source 后读取
IDENTITY_NA=1
# shellcheck disable=SC2034  # 同上：SMOKE_NOTE 给 probes.sh，E2E_NOTE 给 e2e/smoke.sh
SMOKE_NOTE="应用没有用户体系，也没有应用登录（上游默认无口令）：能打开网页就只有网关认过的主人，身份以网页特征命中为证"
# shellcheck disable=SC2034  # 同上
E2E_NOTE="$SMOKE_NOTE"

web_assert() { grep -qiE 'new-watch-form|add-watch-url-row'; }   # 标准输入：watch 总览页

# data_write：经表单建 watch，URL 带唯一标记并覆盖写进 SMOKE_STATE。
# 应用首查后会把标题换成网页标题，但 URL 原样渲染在总览页的 favicon 链接（open_link）里。
data_write() {
  local ts body
  ts="$(date +%s)"
  if ! body="$(web_get /form/add/quickwatch --data-urlencode "url=https://example.com/?wonton-smoke-$ts" -L 2>&1)"; then
    echo "data_write：POST /form/add 失败：$(head -c 200 <<<"$body")"
    return 1
  fi
  printf '%s' "$ts" >"$SMOKE_STATE"
  echo "data_write：建了 watch wonton-smoke-$ts，标记写入 SMOKE_STATE"
}

data_check() {
  local ts page
  ts="$(cat "$SMOKE_STATE" 2>/dev/null)"
  [[ -n "$ts" ]] || { echo "data_check：SMOKE_STATE 里没有 data_write 写的标记"; return 1; }
  if ! page="$(web_get / 2>&1)"; then
    echo "data_check：拿不到总览页：$(head -c 200 <<<"$page")"
    return 1
  fi
  grep -q "wonton-smoke-$ts" <<<"$page" ||
    { echo "data_check：总览页里没有 wonton-smoke-$ts（watch 丢了）"; return 1; }
}
