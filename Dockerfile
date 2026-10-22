# 带 DNS 插件的 Caddy，仅在用 DNS-01 申请证书（ACME_DNS=cloudflare 或 dnspod）时需要。
# 默认部署直接使用官方镜像 caddy:2.11.7-alpine，不需要构建。
#
#   docker build -t registry-mirrors-caddy:2.11.7 .
#   国内构建可加：--build-arg GOPROXY=https://goproxy.cn,direct
#
# 插件版本均已固定：caddy-dns/dnspod 的最新标签 v0.0.4 不兼容 Caddy 2.10 起使用的 libdns 1.x，
# 因此固定到修复了这一问题的提交（2026-03-25）。
ARG CADDY_VERSION=2.11.7

FROM caddy:${CADDY_VERSION}-builder-alpine AS builder
ARG GOPROXY=https://proxy.golang.org,direct
ENV GOPROXY=${GOPROXY}
RUN xcaddy build \
    --with github.com/caddy-dns/cloudflare@v0.2.4 \
    --with github.com/caddy-dns/dnspod@fb7cc31cc04c68a304b8d2672c3e5d9f2ad3d7ba

FROM caddy:${CADDY_VERSION}-alpine
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
