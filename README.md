# Studiolo 部署包

[Studiolo](https://github.com/shanpeng238/studiolo) 私有化部署所用的容器编排与初始化脚本。业务代码在
[`shanpeng238/studiolo`](https://github.com/shanpeng238/studiolo)，本仓只放**部署面**。

## 目录

| 路径 | 作用 |
| --- | --- |
| `docker-compose.yml` | Linux CPU 部署栈（交付客户用这个） |
| `docker-compose-gpu.yml` | Linux GPU 部署栈（Milvus 换 `-gpu` 镜像） |
| `docker-compose-mac.yml` | macOS 本机开发栈（容器名 `studiolo-*`，数据落 `data/`） |
| `env.example` | 配置模板，交付前 `cp env.example .env` 并填必填项 |
| `init-scripts/init.sql` | 空库初始化：建库建表 + 写入 Alembic 版本号 |
| `secrets/` | 运行时挂载目录。仓库只带**空的** `studiolo.lic` 占位文件，授权与 JWT 密钥由部署时生成，不入库 |
| `Studiolo - 企业版私有化部署指南1.0.md` | 面向客户的完整部署步骤 |
| `RELEASE.md` | 供应商内部：镜像来源与构建推送、发布前检查清单 |

## 快速开始

```bash
cp env.example .env      # 填 LICENSE_HMAC_KEY、各密码、SMTP 账号
docker compose up -d     # Linux；macOS 用 -f docker-compose-mac.yml
```

详细步骤（激活、首管理员、常见故障）见部署指南。

## 镜像

后端与前端镜像随版本发布在 Docker Hub（`shanpeng238/studiolo-backend` / `studiolo-frontend`）；
Neo4j 与 bge-m3 是自封装的通用基础镜像，沿用已发布的 `verimind-*` 仓库名，理由见 `RELEASE.md`。
