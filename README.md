<p>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://openlinkos.com/brand/linkos-mirrors/github/readme-dark.svg">
    <img alt="LinkOS Mirrors" src="https://openlinkos.com/brand/linkos-mirrors/github/readme-light.svg" height="48">
  </picture>
</p>

# LinkOS Registry Mirrors - Caddy

LinkOS 公益运营的镜像仓库加速服务，使用 Caddy 作为反向代理，支持 Docker Hub、Google GCR、GitHub GHCR、RedHat Quay、Kubernetes Registry 镜像加速。

使用 Caddy 反向代理的优点：对服务器硬盘空间需求极小，可在小硬盘服务器上快速部署，在多点部署的情况下实现分布式镜像加速服务。





## 项目进展：开发中

> 当前处于开发中，当前 LinkOS Registry Mirrors（Caddy）版本可能存在不稳定性，建议等待正式 release 后使用。

**进行中：**

1. docker 构建
2. docker 部署文档编写
3. 非 https 版 Caddyfile 配置改造（应对本机前方再次外挂 反代/WAF 场景，此时可无需 https）

**待办：**

1. 集成 GitHub Action，并支持多架构构建
2. docker compose 部署文档编写





## 服务列表

当前 LinkOS 镜像加速（Caddy 反代版）提供下面列表中的容器镜像加速服务：

| 镜像 Mirror 地址          | 镜像说明                              | 使用示例                                                     |
| ------------------------- | ------------------------------------- | ------------------------------------------------------------ |
| https://docker.linkos.org | docker.io - Docker Hub 镜像加速       | docker pull docker.linkos.org/library/mysql:5.7              |
| https://gcr.linkos.org    | gcr.io - Google 镜像加速              | docker pull gcr.linkos.org/kubebuilder/kube-rbac-proxy:v0.13.1 |
| https://ghcr.linkos.org   | ghcr.io - GitHub 镜像加速             | docker pull ghcr.linkos.org/nikiforovall/dotnet-script:latest |
| https://quay.linkos.org   | quay.io - RedHat Quay 镜像加速        | docker pull quay.linkos.org/coreos/etcd:v3.4.11              |
| https://k8s.linkos.org    | registry.k8s.io - Kubernetes 镜像加速 | docker pull k8s.linkos.org/kube-apiserver:v1.26.9            |



## 快速使用

以 Docker Hub 镜像加速为例，用户当前需要下载使用存储在 Docker Hub 上的 mysql:5.7 镜像：

1. 拉取加速镜像：

   ```bash
   docker pull docker.linkos.org/library/mysql:5.7
   ```

2. 重新打标签：

   ```bash
   docker tag docker.linkos.org/library/mysql:5.7 mysql:5.7
   ```

3. 删除加速镜像：

   ```bash
   docker rmi docker.linkos.org/library/mysql:5.7
   ```



## 镜像加速

### docker hub 镜像加速

```bash
常规镜像代理
官方命令：docker pull username/image:tag
代理命令：docker pull docker.linkos.org/username/image:tag

根镜像代理
官方命令：docker pull mysql:5.7
代理命令：docker pull docker.linkos.org/library/mysql:5.7
```



### gcr 镜像加速

```bash
常规镜像代理
官方命令：docker pull gcr.io/username/image:tag
代理命令：docker pull gcr.linkos.org/username/image:tag
```



### ghcr 镜像加速

```bash
常规镜像代理
官方命令：docker pull ghcr.io/username/image:tag
代理命令：docker pull ghcr.linkos.org/username/image:tag
```



### quay 镜像加速

```bash
常规镜像代理
官方命令：docker pull quay.io/username/image:tag
代理命令：docker pull quay.linkos.org/username/image:tag
```



### kubernetes 镜像加速

```bash
常规镜像代理
官方命令：docker pull k8s.gcr.io/username/image:tag
官方命令：docker pull registry.k8s.io/username/image:tag
代理命令：docker pull k8s.linkos.org/username/image:tag

根镜像代理
官方命令：docker pull k8s.gcr.io/image:tag
官方命令：docker pull registry.k8s.io/image:tag
代理命令：docker pull k8s.linkos.org/image:tag
```





## 部署文档

本项目提供 systemd、docker、docker-compose 三种搭建方式，可根据实际需要进行选择，如单台服务器只部署该镜像加速，可直接以 systemd 形式快速部署，且具有更好的性能和稳定性，如想和其他服务共用服务器推荐使用 docker 或 docker-compose 方式容器化部署。



### Systemd 部署

➡️ [deploy-in-systemd.md](./docs/deploy-in-systemd.md)



### Docker 部署

➡️ [deploy-in-docker.md](./docs/deploy-in-docker.md)



### Docker Compose 部署

➡️ [deploy-in-docker-compose.md](./docs/deploy-in-docker-compose.md)
