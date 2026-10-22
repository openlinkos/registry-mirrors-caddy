#!/usr/bin/env bash
# 冒烟测试：以 MODE=http 启动后在本机运行，检查每个上游都能正确拉取、镜像层经由本服务下载，
# 并且只放行拉取。需要 docker、curl、jq。
# 用法：scripts/smoke.sh [主机，默认 localhost]
set -euo pipefail

HOST="${1:-localhost}"
fail=0

ok() { printf '  通过  %s\n' "$1"; }
bad() { printf '  失败  %s\n' "$1"; fail=1; }
status() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

wait_ready() {
  for _ in $(seq 1 60); do
    [ "$(status "http://$HOST:$1/")" = 200 ] && return 0
    sleep 1
  done
  return 1
}

# 端口、经镜像站拉取的名称、直接从上游拉取的名称
CASES=(
  "5001 library/hello-world:latest docker.io/library/hello-world:latest"
  "5002 distroless/static:nonroot gcr.io/distroless/static:nonroot"
  "5003 containerd/busybox:1.36 ghcr.io/containerd/busybox:1.36"
  "5004 pause:3.10 registry.k8s.io/pause:3.10"
  "5005 coreos/etcd:v3.5.0 quay.io/coreos/etcd:v3.5.0"
)

ACCEPT='application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json'

# 按上游的质询取一个拉取令牌（不需要认证的上游返回空）
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
  local port=$1 repo=$2 ref=$3 base token auth=() manifest digest
  base="http://$HOST:$port"
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
  read -r port name upstream <<<"$c"
  if ! wait_ready "$port"; then bad "$port：没有就绪"; continue; fi
  mirrored="$(docker pull "$HOST:$port/$name" | sed -n 's/^Digest: //p' || true)"
  direct="$(docker pull "$upstream" | sed -n 's/^Digest: //p' || true)"
  if [ -n "$mirrored" ] && [ "$mirrored" = "$direct" ]; then
    ok "$port $name $mirrored"
  else
    bad "$port $name：镜像站 '${mirrored:-无}'，上游 '${direct:-无}'"
  fi
done

echo "镜像层经由本服务下载（上游的 CDN 地址在白名单内）"
for c in "${CASES[@]}"; do
  read -r port name _ <<<"$c"
  s="$(blob_status "$port" "${name%:*}" "${name##*:}")"
  case "$s" in
    200 | 206) ok "$port ${name%:*} 返回 $s" ;;
    *) bad "$port ${name%:*} 返回 $s：可能是上游换了 CDN 地址，请看 logs/access.log 并补充白名单" ;;
  esac
done

echo "只放行拉取"
for port in 5001 5002 5003 5004 5005; do
  s="$(status -X POST "http://$HOST:$port/v2/smoke/blobs/uploads/")"
  [ "$s" = 405 ] && ok "$port POST 返回 405" || bad "$port POST 返回 $s，应为 405"
  s="$(status -X DELETE "http://$HOST:$port/v2/smoke/manifests/latest")"
  [ "$s" = 405 ] && ok "$port DELETE 返回 405" || bad "$port DELETE 返回 $s，应为 405"
  s="$(status "http://$HOST:$port/v2/_catalog")"
  [ "$s" = 404 ] && ok "$port /v2/_catalog 返回 404" || bad "$port /v2/_catalog 返回 $s，应为 404"
done

echo "每个端口只转发到自己的上游"
for port in 5002 5003 5004 5005; do
  s="$(status -H "Accept: $ACCEPT" "http://$HOST:$port/v2/library/hello-world/manifests/latest")"
  case "$s" in
    2*) bad "$port 返回了 Docker Hub 的 library/hello-world（$s）" ;;
    *) ok "$port 请求 library/hello-world 返回 $s" ;;
  esac
done

echo "用法页与探活"
for port in 5001 5002 5003 5004 5005; do
  ct="$(curl -s -o /dev/null -w '%{http_code} %{content_type}' "http://$HOST:$port/")"
  case "$ct" in
    "200 text/html"*) ok "$port / 返回用法页" ;;
    *) bad "$port / 返回 '$ct'，应为 200 text/html" ;;
  esac
  s="$(status "http://$HOST:$port/healthz")"
  [ "$s" = 200 ] && ok "$port /healthz 返回 200" || bad "$port /healthz 返回 $s，应为 200"
done
s="$(status "http://$HOST:5001/robots.txt")"
[ "$s" = 200 ] && ok "/robots.txt 返回 200" || bad "/robots.txt 返回 $s，应为 200"

if [ "$fail" = 0 ]; then echo "全部通过"; else echo "有检查失败"; fi
exit "$fail"
