<p>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://openlinkos.com/brand/linkos-mirrors/github/readme-dark.svg">
    <img alt="LinkOS Mirrors" src="https://openlinkos.com/brand/linkos-mirrors/github/readme-light.svg" height="48">
  </picture>
</p>

# LinkOS Mirrors · Caddy 零磁盘版

[LinkOS Mirrors](https://github.com/openlinkos/registry-mirrors) 是由 [LinkOS 团队](https://linkos.io) 运营的免费容器镜像加速服务。本仓库是它的另一种部署方式：只用一个 Caddy，不在本地缓存镜像，几乎不占磁盘，适合在小硬盘服务器上快速搭建，或在多个地点分布部署。

服务状态：[uptime.linkos.org](https://uptime.linkos.org)

## 选哪个版本

| | 本仓库（零磁盘） | [registry-mirrors](https://github.com/openlinkos/registry-mirrors)（缓存） |
| --- | --- | --- |
| 组成 | 一个 Caddy | 每个上游一个 CNCF Distribution 拉取缓存，前面加一个 nginx |
| 磁盘 | 只存日志和证书 | 缓存镜像，随拉取量增长 |
| 回源 | 每次拉取都回源 | 同一镜像只回源一次 |
| Docker Hub 匿名限额 | 每次拉取都计入服务器出口 IP 的限额 | 已缓存的镜像不再消耗 |
| TLS | 内置自动 HTTPS，也可放在 CDN 之后 | 需要在前面另加 TLS 反向代理或 CDN |

用户较多，或者需要节省上游流量和 Docker Hub 限额时，用 registry-mirrors。磁盘小、想快速搭一套，或者前面已有 CDN 时，用本仓库。

## 服务列表

| 加速地址 | 上游 | 示例 |
| --- | --- | --- |
| `docker.linkos.org` | Docker Hub（docker.io） | `docker pull docker.linkos.org/library/mysql:5.7` |
| `gcr.linkos.org` | gcr.io | `docker pull gcr.linkos.org/distroless/static:nonroot` |
| `ghcr.linkos.org` | ghcr.io | `docker pull ghcr.linkos.org/containerd/busybox:1.36` |
| `quay.linkos.org` | quay.io | `docker pull quay.linkos.org/coreos/etcd:v3.5.0` |
| `k8s.linkos.org` | registry.k8s.io | `docker pull k8s.linkos.org/pause:3.10` |

使用时，把镜像地址里的上游域名换成对应的加速地址即可。Docker Hub 的官方镜像（如 `mysql`、`nginx`）要写成 `library/<名称>`。`k8s.gcr.io` 已于 2023 年冻结，Kubernetes 镜像请使用 `registry.k8s.io`，对应 `k8s.linkos.org`。

## 快速使用

以 Docker Hub 上的 `mysql:5.7` 为例：

```bash
docker pull docker.linkos.org/library/mysql:5.7       # 通过加速地址拉取
docker tag docker.linkos.org/library/mysql:5.7 mysql:5.7
docker rmi docker.linkos.org/library/mysql:5.7        # 删除加速地址的标签，镜像本身保留
```

其他上游同理：

```bash
docker pull ghcr.linkos.org/<用户>/<镜像>:<标签>        # 对应 ghcr.io/<用户>/<镜像>:<标签>
docker pull quay.linkos.org/<用户>/<镜像>:<标签>        # 对应 quay.io/<用户>/<镜像>:<标签>
docker pull gcr.linkos.org/<项目>/<镜像>:<标签>         # 对应 gcr.io/<项目>/<镜像>:<标签>
docker pull k8s.linkos.org/<镜像>:<标签>               # 对应 registry.k8s.io/<镜像>:<标签>
```

## 配置 Docker 镜像加速

在 `/etc/docker/daemon.json` 中加入以下内容（文件已有内容时请合并，不要整体覆盖）：

```json
{
  "registry-mirrors": ["https://docker.linkos.org"]
}
```

然后重启 Docker：`sudo systemctl restart docker`。之后 `docker pull mysql:5.7` 会自动经过加速。

注意：Docker 的 `registry-mirrors` **只对 Docker Hub 生效**。ghcr.io、quay.io、gcr.io、registry.k8s.io 的镜像仍需按上面的方式改写地址。

## 工作原理

- 只放行拉取请求（GET、HEAD）。其他方法返回 405，`/v2/_catalog` 返回 404。
- 本服务会把上游的认证质询（`Www-Authenticate`）改写为指向自己，令牌请求也由本服务转发。客户端只需要能访问加速地址。
- 上游常把镜像层（blob）重定向到 CDN 或对象存储，例如 Docker Hub 的 `production.cloudfront.docker.com`、quay.io 的 `cdnNN.quay.io`、registry.k8s.io 的 `cdn.registry.k8s.io` 和 `*-docker.pkg.dev`。Caddy 会在服务端跟随这些重定向，最多 3 跳，再把内容直接转发给客户端，客户端不会被引向这些地址。
- Caddy 只跟随该上游白名单内的 https 地址。白名单外的重定向会原样交给客户端，客户端会直连该地址：可能较慢，但仍能拉取。各上游的白名单见 [`caddy/upstreams.caddy`](caddy/upstreams.caddy)。访问日志的 `redirect1`–`redirect3` 字段记录了每一跳实际跟随的主机。

## 自行部署

需要一台能正常访问上述上游的 Linux 服务器，并装好 Docker 和 Docker Compose。默认使用官方镜像 `caddy:2.11.7-alpine`，支持 amd64、arm64 等架构，不需要另外构建。

```bash
git clone https://github.com/openlinkos/registry-mirrors-caddy.git
cd registry-mirrors-caddy
cp .env.sample .env    # 按下面的说明修改
docker compose up -d
```

容器使用宿主机网络。证书保存在 `./data`。访问日志在 `./logs/access.log`（JSON 格式，每 100 MiB 轮转一次，最多保留 10 个文件、30 天）。

### 方式一：直接对外（默认，MODE=tls）

1. 为 `docker`、`gcr`、`ghcr`、`k8s`、`quay` 五个子域名添加 A/AAAA 记录，指向服务器，例如 `docker.example.com`。
2. 在 `.env` 中设置 `DOMAIN=example.com`。
3. 确保 80、443 端口能从公网访问，然后执行 `docker compose up -d`。Caddy 会为每个子域名单独申请证书（HTTP-01 / TLS-ALPN-01），不需要通配符证书，也不需要 DNS 服务商的 API 密钥。
4. 测试：`docker pull docker.example.com/library/hello-world`。

如果 80 端口无法从公网访问，可以改用 DNS-01 验证，但需要带 DNS 插件的镜像：

```bash
docker build -t registry-mirrors-caddy:2.11.7 .   # 编入 cloudflare、dnspod 插件
```

然后在 `.env` 中设置 `CADDY_IMAGE=registry-mirrors-caddy:2.11.7`，并设置 `ACME_DNS=cloudflare` 和 `CLOUDFLARE_API_TOKEN`，或 `ACME_DNS=dnspod` 和 `DNSPOD_TOKEN`。

### 方式二：放在 CDN 或反向代理之后（MODE=http）

此时 Caddy 只监听明文端口，由前面的 CDN 或反向代理负责 TLS。端口约定与 registry-mirrors 相同：

| 端口 | 上游 |
| --- | --- |
| 5001 | Docker Hub |
| 5002 | gcr.io |
| 5003 | ghcr.io |
| 5004 | registry.k8s.io |
| 5005 | quay.io |

在 `.env` 中设置 `MODE=http`，然后把每个加速域名回源到对应端口。注意以下几点：

- 回源时要保留客户端访问的域名（Host 头），本服务据此生成认证地址。
- 前面要对客户端提供 HTTPS。如果只用明文访问，需设置 `PUBLIC_SCHEME=http`。
- 想在访问日志里记录真实客户端 IP，请把 CDN 的回源地址段写进 `TRUSTED_PROXIES`。
- 反向代理与本服务在同一台机器上时，可以设置 `BIND=127.0.0.1`，避免这些端口暴露到公网。

本地试用：

```bash
MODE=http PUBLIC_SCHEME=http BIND=127.0.0.1 docker compose up -d
docker pull localhost:5001/library/hello-world   # Docker 默认允许以明文访问 localhost
scripts/smoke.sh                                 # 自检：五个上游各拉一个镜像并与上游比对摘要，确认镜像层经由本服务下载、只放行拉取
```

### 不用 Docker

默认配置只用到 Caddy 的标准模块，Caddy 2.11 或更新版本都能运行（本仓库在 2.11.7 上测试过）。安装方法见 [caddyserver.com/docs/install](https://caddyserver.com/docs/install)。以 Debian/Ubuntu 的官方软件包为例：

```bash
sudo cp -r caddy/* /etc/caddy/
sudo mkdir -p /var/log/caddy && sudo chown caddy:caddy /var/log/caddy
sudo systemctl edit caddy      # 写入下面两行后保存
# [Service]
# Environment="MODE=tls" "DOMAIN=example.com"
sudo systemctl restart caddy
```

### 日志与监控

- 访问日志：记录客户端 IP、请求的镜像、状态码，以及每一跳跟随的主机。
- 指标：Prometheus 格式，地址为 `http://127.0.0.1:9180/metrics`，只在本机监听。
- 管理接口：`localhost:2019`，只在本机监听。修改配置后执行 `docker compose restart` 即可生效。

## 安全说明

- **只读**：只放行 GET、HEAD，拒绝任何写入，并关闭 `/v2/_catalog`。
- **不是开放代理**：每个加速地址只转发到固定的上游。跟随重定向时，目标地址来自上游的响应，并且必须在白名单内，客户端无法指定。
- **令牌不发给 CDN**：客户端的 `Authorization` 头只发给上游 registry 本身。跟随重定向访问 CDN 或对象存储时不会携带它；这些地址自带签名，不需要令牌。
- **不透露用户 IP**：发往上游的请求不带 `X-Forwarded-For` 等头，也不带 Cookie。
- **管理接口和指标只在本机监听。**
- **2026-10 之前的版本有以下问题**：上游 CDN 地址变化后，镜像层会被重定向到未经改写的地址，从而绕过代理；`/metrics` 对公网开放；还需要额外的 `*-auth`、`*-storage` 子域名和 Cloudflare API 令牌。自建过的用户请更新到当前配置，旧的子域名解析可以删除。

## 限制

- **不缓存**：每次拉取都会回源，服务器的入站、出站流量都约等于拉取量。
- **Docker Hub 匿名拉取有频率限制**：按服务器的出口 IP 计算，所有用户共用这一个限额。用户较多时请改用 registry-mirrors。
- **上游的 CDN 地址会变**：出现白名单外的新地址时，拉取不会失败，但客户端需要直连该地址才能下载镜像层。请根据访问日志补充 `caddy/upstreams.caddy` 中的白名单。
- **registry.k8s.io 的去向因地而异**：它按请求来源 IP 选择后端（cdn.registry.k8s.io、AWS S3 或 pkg.dev），服务器所在位置不同，跟随的地址也不同。
- **尚未内置限流。**

## 使用须知

- 本服务免费提供、尽力维护，**不保证可用性和速度**，可能随时调整、限流或停止。生产环境请自行评估，或自建一套。
- 镜像内容来自各上游仓库，版权和责任归原作者；使用时请遵守上游的服务条款（如 Docker Hub、GitHub、Quay 的条款）。
- 不得利用本服务分发违法或侵权内容。对滥用行为，我们会限流或屏蔽。
- 问题反馈：[提交 issue](https://github.com/openlinkos/registry-mirrors-caddy/issues)，或发送邮件至 admin@linkos.io。
- 违规与侵权举报：发送邮件至 abuse@linkos.io，需要写明的信息见[举报与投诉](https://linkos.org/zh/abuse)。
- 服务会记录访问日志（IP、请求的镜像、时间），仅用于运维和防止滥用。

## 许可

配置与文档以 [Apache License 2.0](LICENSE) 发布。LinkOS 与 OpenLinkOS 的名称和标志不在该许可范围内，使用规范见 [openlinkos.com/zh/brand](https://openlinkos.com/zh/brand)。
