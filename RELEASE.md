# 发布说明（供应商内部使用，交付客户前可删除本文件）

部署包引用的镜像（CPU 版与 GPU 版共用同一组标签，只有 Milvus 在 GPU 版下换成官方 `-gpu` 镜像）：

| 镜像 | 来源 | 说明 |
| --- | --- | --- |
| `shanpeng238/studiolo-backend:v1.0.0` | 本仓 `backend/` 构建 | FastAPI 后端（Cython 编译），容器内 8000。**当前 Docker Hub 上还没有这个 tag，发布前必须构建推送** |
| `shanpeng238/studiolo-frontend:v1.0.0` | 本仓 `frontend/` 构建 | Next.js standalone，容器内 3000。**同上，尚未推送** |
| `shanpeng238/verimind-neo4j:5.26-amd64` | 已发布的成品镜像，**直接引用** | Neo4j 5.26 Community + GDS + APOC（插件已预装）；CPU / GPU 版共用 |
| `shanpeng238/verimind-neo4j:5.26-arm64` | 已发布的成品镜像，**直接引用** | 仅 `docker-compose-mac.yml`（Mac 开发）使用；该仓按架构分 tag，没有多架构清单 |
| `shanpeng238/verimind-bge-m3-service:v1.0.0` | 已发布的成品镜像，**直接引用** | 通用 bge-m3 embedding HTTP 服务；`v1.0.0` 是多架构标签（amd64 + arm64），另有 `-amd64` / `-arm64` 单架构标签 |

neo4j 与 bge-m3 是自封装的通用基础镜像，**沿用已经发布的 `verimind-*` 仓库名**，不再另起 `studiolo-*` 名字重新打 tag 推送（改了就要维护两套 tag，且镜像内容完全相同）。容器名、网络名与镜像名是两回事——容器仍是 `studiolo-neo4j` / `studiolo-bge-m3-service`，栈仍是 `studiolo-net`。
bge-m3 镜像在多架构下自带 CUDA 运行时，GPU 版直接复用同一个标签。

## 构建与推送

```bash
# 1. 后端（在 studiolo 仓库根目录）
docker buildx build --platform linux/amd64 \
  -t shanpeng238/studiolo-backend:v1.0.0 backend/ --push

# 2. 前端
docker buildx build --platform linux/amd64 \
  -t shanpeng238/studiolo-frontend:v1.0.0 frontend/ --push

# 3. 图数据库与向量模型服务：无需构建，compose 直接引用已发布的 verimind-* 镜像
```

> 推送是公开发布动作，由项目所有者执行，不在自动化流程内。

## 授权文件签发

签发脚本仍是 `verimind/license-manager/issue_license.py`，它产出的文件名带 `verimind` 前缀、
token 里的 `iss`/`aud` 也仍是 VeriMind 的值（`backend/app/core/license.py` 里同样没改——
改了会让已发出的授权全部验签失败）。

- **签发时加 `--product studiolo`**，产出 `<客户>_studiolo.lic`；发给客户前把文件名确认为 `studiolo.lic`。
- 客户上传后，文件被写成 `secrets/studiolo.lic`。**studiolo 只认这个名字**——`verimind.lic` 不会被读取，
  两个产品的授权文件不再互通。

> 待定：下一版可把 `LICENSE_ISSUER` / `LICENSE_AUDIENCE` 换成产品自己的值——前提是重新签发
> 全部存量授权，属于一次性的迁移决策，不在 v1.0.0 内。

## 发布前检查清单

- [ ] `backend/` 的 `make check` 全绿（含 `/health` 与授权文件名兼容的用例）
- [ ] `init-scripts/init.sql` 与当前迁移链一致：空库加载后 `alembic current` 显示 head
      （2026-11-12 由开发库 head `e3b7c92d4a10` 重新导出，空库实测 25 张业务表）
- [ ] `docker compose config` 无警告（`.env` 从 `env.example` 复制后）
- [ ] 全新 Linux 机器上按指南走通：启动 → 激活 → 登录 → 提权 → 建课
- [ ] `secrets/jwt-*.pem` 是本次发布自己的一对，不是从开发仓库直接拷的
- [ ] 交付包里不含 `.env`、`data/`、`logs/`

## 版本号约定

部署包版本（`v1.0.0`）用于镜像 tag 与指南；后端 `PROJECT_VERSION`（`app/core/config.py`）
当前仍是继承自 VeriMind 的 `2.0.0`，只在开发环境的 Swagger 标题里出现（生产环境文档已关闭），
发下一版时可一并对齐。
