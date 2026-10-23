#!/usr/bin/env bash
# 冒烟测试：检查每个上游都能正确拉取、镜像层经由本服务下载，并且入口只放行拉取。需要 docker、curl、jq。两种用法：
#   按端口：以 http 模式部署后（MODE=http PUBLIC_SCHEME=http）在本机运行
#     scripts/smoke.sh [主机，默认 localhost]；端口与 .env 一致，可用 PORT_DOCKER 等环境变量覆盖。
#   按域名：tls 模式，或 vhost 模式放在 CDN 之后，经 HTTPS 访问 docker、gcr、ghcr、k8s、quay.<域名>
#     SMOKE_DOMAIN=example.com scripts/smoke.sh
# 运行这个脚本的机器能直连上游，所以测不出"客户端被引去直连上游"的情况；要测这一点，把客户端放进不能上外网的网络里拉取。
set -euo pipefail

HOST="${1:-localhost}"
fail=0

ok() { printf '  通过  %s\n' "$1"; }
bad() { printf '  失败  %s\n' "$1"; fail=1; }
status() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

# 每个上游的入口地址和 docker pull 用的前缀，顺序：Docker Hub、gcr.io、ghcr.io、registry.k8s.io、quay.io
BASES=()
NAMES=()
if [ -n "${SMOKE_DOMAIN:-}" ]; then
  for sub in docker gcr ghcr k8s quay; do
    BASES+=("https://$sub.$SMOKE_DOMAIN")
    NAMES+=("$sub.$SMOKE_DOMAIN")
  done
else
  for port in "${PORT_DOCKER:-5001}" "${PORT_GCR:-5002}" "${PORT_GHCR:-5003}" "${PORT_K8S:-5004}" "${PORT_QUAY:-5005}"; do
    BASES+=("http://$HOST:$port")
    NAMES+=("$HOST:$port")
  done
fi
# containerd 在 ns 参数里写的上游名，顺序同上
NS=(docker.io gcr.io ghcr.io registry.k8s.io quay.io)

wait_ready() {
  for _ in $(seq 1 60); do
    [ "$(status "$1/healthz")" = 200 ] && return 0
    sleep 1
  done
  return 1
}

# 上游序号、经镜像站拉取的名称、直接从上游拉取的名称
CASES=(
  "0 library/hello-world:latest docker.io/library/hello-world:latest"
  "1 distroless/static:nonroot gcr.io/distroless/static:nonroot"
  "2 containerd/busybox:1.36 ghcr.io/containerd/busybox:1.36"
  "3 pause:3.10 registry.k8s.io/pause:3.10"
  "4 coreos/etcd:v3.5.0 quay.io/coreos/etcd:v3.5.0"
)

ACCEPT='application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json'

# 按本站的质询取一个拉取令牌（不需要认证的上游返回空）
pull_token() {
  local base=$1 repo=$2 challenge realm service
  challenge="$(curl -s -o /dev/null -D - "$base/v2/" | tr -d '\r' | sed -n 's/^[Ww]ww-[Aa]uthenticate: Bearer //p')"
  realm="$(sed -n 's/.*realm="\([^"]*\)".*/\1/p' <<<"$challenge")"
  service="$(sed -n 's/.*service="\([^"]*\)".*/\1/p' <<<"$challenge")"
  [ -n "$realm" ] || return 0
  curl -s -G "$realm" --data-urlencode "service=$service" --data-urlencode "scope=repository:$repo:pull" |
    jq -r '.token // .access_token // empty'
}

# 取镜像（linux/amd64）第一个层的状态码：不跟随重定向，200 或 206 说明由本服务转发
blob_status() {
  local base=$1 repo=$2 ref=$3 token auth=() manifest digest
  token="$(pull_token "$base" "$repo")"
  [ -n "$token" ] && auth=(-H "Authorization: Bearer $token")
  manifest="$(curl -s "${auth[@]}" -H "Accept: $ACCEPT" "$base/v2/$repo/manifests/$ref")"
  digest="$(jq -r '.manifests[]? | select(.platform.os == "linux" and .platform.architecture == "amd64") | .digest' <<<"$manifest" | head -n 1)"
  if [ -n "$digest" ]; then
    manifest="$(curl -s "${auth[@]}" -H "Accept: $ACCEPT" "$base/v2/$repo/manifests/$digest")"
  fi
  digest="$(jq -r '.layers[0].digest // empty' <<<"$manifest")"
  [ -n "$digest" ] || { echo "无清单"; return; }
  curl -s -o /dev/null -r 0-1023 -w '%{http_code}' "${auth[@]}" "$base/v2/$repo/blobs/$digest"
}

echo "拉取并比对摘要"
for c in "${CASES[@]}"; do
  read -r i name upstream <<<"$c"
  if ! wait_ready "${BASES[i]}"; then bad "${NAMES[i]}：没有就绪"; continue; fi
  mirrored="$(docker pull "${NAMES[i]}/$name" | sed -n 's/^Digest: //p' || true)"
  direct="$(docker pull "$upstream" | sed -n 's/^Digest: //p' || true)"
  if [ -n "$mirrored" ] && [ "$mirrored" = "$direct" ]; then
    ok "${NAMES[i]} $name $mirrored"
  else
    bad "${NAMES[i]} $name：镜像站 '${mirrored:-无}'，上游 '${direct:-无}'"
  fi
done

echo "镜像层经由本服务下载（上游的 CDN 地址在白名单内）"
for c in "${CASES[@]}"; do
  read -r i name _ <<<"$c"
  s="$(blob_status "${BASES[i]}" "${name%:*}" "${name##*:}")"
  case "$s" in
    200 | 206) ok "${NAMES[i]} ${name%:*} 返回 $s" ;;
    *) bad "${NAMES[i]} ${name%:*} 返回 $s：可能是上游换了 CDN 地址，请看 logs/access.log 并补充白名单" ;;
  esac
done

echo "认证地址指向本站，不暴露源站出口 IP"
for i in "${!BASES[@]}"; do
  base="${BASES[i]}" n="${NAMES[i]}"
  realm="$(curl -s -o /dev/null -D - "$base/v2/" | tr -d '\r' | sed -n 's/^[Ww]ww-[Aa]uthenticate: .*realm="\([^"]*\)".*/\1/p')"
  case "$realm" in
    "" | "$base"/*) ok "$n realm '${realm:-无}'" ;;
    *) bad "$n realm 指向 '$realm'，客户端会直连上游的认证服务" ;;
  esac
done
read -r _ name _ <<<"${CASES[0]}"
token="$(pull_token "${BASES[0]}" "${name%:*}")"
if curl -s -o /dev/null -D - -H "Authorization: Bearer $token" -H "Accept: $ACCEPT" "${BASES[0]}/v2/${name%:*}/manifests/${name##*:}" | grep -qi '^docker-ratelimit-source'; then
  bad "${NAMES[0]} 响应带了 Docker-Ratelimit-Source"
else
  ok "${NAMES[0]} 响应不带 Docker-Ratelimit-Source"
fi

echo "入口规则"
for i in "${!BASES[@]}"; do
  base="${BASES[i]}" n="${NAMES[i]}"
  s="$(status -X POST "$base/v2/smoke/blobs/uploads/")"
  [ "$s" = 405 ] && ok "$n POST 返回 405" || bad "$n POST 返回 $s，应为 405"
  s="$(status -X DELETE "$base/v2/smoke/manifests/latest")"
  [ "$s" = 405 ] && ok "$n DELETE 返回 405" || bad "$n DELETE 返回 $s，应为 405"
  s="$(status "$base/v2/_catalog")"
  [ "$s" = 404 ] && ok "$n /v2/_catalog 返回 404" || bad "$n /v2/_catalog 返回 $s，应为 404"
done

# 各上游互相隔离：用别的上游的入口请求 Docker Hub 的镜像，不能拿到它
echo "上游隔离"
for i in 1 2 3 4; do
  s="$(status -H "Accept: $ACCEPT" "${BASES[i]}/v2/library/hello-world/manifests/latest")"
  case "$s" in
    2*) bad "${NAMES[i]} 返回了 Docker Hub 的 library/hello-world（$s）" ;;
    *) ok "${NAMES[i]} 请求 library/hello-world 返回 $s" ;;
  esac
  # containerd 把这个入口配成了 Docker Hub 的镜像：ns 和入口的上游不一致，返回 404，让 containerd 换下一个地址
  s="$(status -H "Accept: $ACCEPT" "${BASES[i]}/v2/library/hello-world/manifests/latest?ns=docker.io")"
  [ "$s" = 404 ] && ok "${NAMES[i]} ns=docker.io 返回 404" || bad "${NAMES[i]} ns=docker.io 返回 $s，应为 404"
done
for i in "${!BASES[@]}"; do
  s="$(status "${BASES[i]}/v2/?ns=${NS[i]}")"
  case "$s" in
    404) bad "${NAMES[i]} ns=${NS[i]} 被拒绝" ;;
    *) ok "${NAMES[i]} ns=${NS[i]} 放行（$s）" ;;
  esac
done

echo "用法页与探活"
for i in "${!BASES[@]}"; do
  ct="$(curl -s -o /dev/null -w '%{http_code} %{content_type}' "${BASES[i]}/")"
  case "$ct" in
    "200 text/html"*) ok "${NAMES[i]} / 返回用法页" ;;
    *) bad "${NAMES[i]} / 返回 '$ct'，应为 200 text/html" ;;
  esac
  s="$(status "${BASES[i]}/healthz")"
  [ "$s" = 200 ] && ok "${NAMES[i]} /healthz 返回 200" || bad "${NAMES[i]} /healthz 返回 $s，应为 200"
done
s="$(status "${BASES[0]}/robots.txt")"
[ "$s" = 200 ] && ok "/robots.txt 返回 200" || bad "/robots.txt 返回 $s，应为 200"

if [ "$fail" = 0 ]; then echo "全部通过"; else echo "有检查失败"; fi
exit "$fail"
