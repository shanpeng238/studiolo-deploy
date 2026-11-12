# Studiolo - 企业版私有化部署指南

> 版本: v1.0.0 (Enterprise)
>
> 最后更新: 2026-11-04
>
> 适用对象: 系统管理员 / 运维工程师

## 1. 部署前准备 (Prerequisites)

本系统是一套完整的独立部署栈：面向用户的前端、后端 API、向量模型服务 (bge-m3)、向量数据库
(Milvus)、图数据库 (Neo4j)、关系库 (PostgreSQL)、缓存 (Redis) 与对象存储 (MinIO) 全部由
`docker-compose.yml` 一并拉起，**不依赖、也不共享任何其它产品的容器或网络**。

### 1.1 硬件配置要求

| **组件** | **最低配置 (Minimum)** | **推荐配置 (Recommended)** | **说明** |
| -------- | ---------------------- | -------------------------- | -------- |
| **CPU**  | 8 Core                 | **16 Core+**               | **必须支持 AVX2**（不支持会显著变慢）。向量化推理走 CPU，建议优先堆核数 |
| **内存** | 16 GB                  | **32 GB+**                 | 全栈常驻含向量模型服务；**低于 8 GB 会 OOM**，索引大文档时内存峰值更高 |
| **磁盘** | 200 GB SSD             | **500 GB NVMe SSD**        | 镜像约 12 GB；机械硬盘无法满足向量检索性能需求 |
| **GPU**  | (可选)                 | **NVIDIA 8 GB 显存+**      | 同时加速 embedding 推理与 Milvus 向量检索，需安装 NVIDIA Container Toolkit。**GPU 版部署请用 `docker-compose-gpu.yml`** |

> **关于 CPU 版与 GPU 版**：两套配置的服务、端口、挂载完全一致，只有向量模型服务与 Milvus
> 换成 GPU 推理。GPU 版只支持 Linux + NVIDIA 显卡；没有显卡的服务器请用 CPU 版。

### 1.2 软件与操作系统要求 (核心铁律)

> ⛔️ 严正声明: 本系统生产环境 **仅支持原生 Linux 系统**。
>
> 为了确保 License 硬件指纹的唯一性与稳定性，系统内置了内核级环境检测。
>
> **严禁** 在 Windows (Docker Desktop/WSL2) 或 macOS (Docker Desktop) 上部署生产环境，否则服务将**拒绝启动**。

#### ✅ 支持的操作系统 (Supported OS)

- **主流 Linux 发行版**: Ubuntu Server (20.04/22.04/24.04 LTS), CentOS 7.9/Stream, Debian 11/12, RHEL 8/9.
- **云服务器 (Cloud Instances)**: 阿里云 ECS, AWS EC2, 腾讯云 CVM, Huawei Cloud ECS (需运行 Linux 镜像).
- **企业虚拟化 (Virtualization)**: VMware vSphere / ESXi / KVM / OpenStack (虚拟机内部需运行 Linux Guest OS).

#### ❌ 不支持的环境 (Blocked)

- Windows (含 Docker Desktop for Windows, WSL2)
- macOS (含 Docker Desktop for Mac)

#### 容器环境依赖

- **Docker**: 版本 >= 24.0.0
- **Docker Compose**: 版本 >= 2.20.0

#### 端口与出网

| 用途 | 端口（宿主机） | 说明 |
| --- | --- | --- |
| 前端 | 3001 | 浏览器访问入口 |
| 后端 API | 8001 | 前端调用的接口地址 `/health` 可用于探活 |

- 其余服务（数据库、向量库、图库、对象存储、模型服务）**不对外发布端口**，只在容器网络内部通信。
- 部署时服务器需能访问 Docker Hub（后端 / 前端 / MinIO 等）与 `quay.io`（Etcd 镜像源）。完全离线环境见 [4. 常见问题](#4-常见问题-faq) 的 Q6。

------

## 2. 安装部署流程 (Installation)

### 2.1 获取部署包并确认文件清单

将部署包解压到服务器 `/opt` 目录：

```
cd /opt
unzip studiolo-deploy-v1.0.0.zip     # 或 git clone <仓库地址> studiolo-deploy
cd studiolo-deploy
```

请确保目录内包含以下内容：

```
studiolo-deploy/
├── docker-compose.yml        # 完整服务编排（CPU 版，含连接串自动组装）
├── docker-compose-gpu.yml    # GPU 版编排（仅 Linux + NVIDIA 使用）
├── env.example               # 环境变量模板
├── Studiolo - 企业版私有化部署指南1.0.md   # 本文件
├── init-scripts/
│   └── init.sql              # 自动建表脚本（全新库唯一建表来源）
└── secrets/
    ├── jwt-private.pem       # 会话签名密钥（仓库自带）
    ├── jwt-public.pem        # 会话验签公钥（仓库自带）
    └── studiolo.lic          # 授权文件占位（空文件，勿删）
```

首次启动后会自动创建 `data/`（数据库、向量库、图库、上传文件等持久化数据）与 `logs/` 目录。

> **⚠️ 关于 `data/`**：全新部署时该目录**必须为空**。若其中已有数据库文件（例如从别处拷贝的旧数据），
> PostgreSQL 会跳过 `init.sql` 建表，导致系统连上一个不含任何表的空库。

### 2.2 配置环境变量

```
# 1. 复制模板
cp env.example .env

# 2. 编辑配置
vim .env
```

**📝 必须修改的配置项：**

- `LICENSE_HMAC_KEY`：授权缓存加密密钥（**必填**，生成命令 `openssl rand -hex 32`；每个部署实例独立，不可复用）。
  **此项留空系统将永久无法登录**（激活接口本身可用，但授权缓存建不起来，登录始终返回「需要激活」）。
- `BACKEND_PUBLIC_URL`：**浏览器访问后端的地址**，填 `http://<服务器IP>:8001`。
  默认值是 `http://localhost:8001`，**不修改会导致页面上的附件、图片全部打不开**。
- `POSTGRES_PASSWORD`：数据库密码。
- `REDIS_PASSWORD`：Redis 密码。
- `MINIO_ROOT_PASSWORD`：对象存储密码。
- `NEO4J_PASSWORD`：图数据库密码（需与 compose 内置 Neo4j 一致）。
- `MAIL_USERNAME` / `MAIL_PASSWORD` / `MAIL_FROM`：发件邮箱与 SMTP 授权码。
  **登录验证码通过邮件发送，邮箱配置错误将无法登录系统。**

> **⚠️ 关于 `POSTGRES_DB`（库名）**：可以自定义，但**只能在全新部署时设置**。
> 若在已有数据的部署上修改库名，后端会连上一个不含任何表的空库。
> 此时须先清空 `data/postgres/` 目录再重新启动（该操作会删除全部业务数据）。

> **模型配置**：大语言模型（讲解、出题、评审等槽位）及其 API Key 统一在
> **系统管理 → 模型配置** 中设置（部署并激活后登录系统即可配置），本文件无需填写任何模型密钥。

> **注意**：请勿修改 `docker-compose.yml`，系统会自动读取 `.env` 中的密码与库名并组装连接地址。

### 2.3 检查密钥

确认 `secrets/` 目录下已包含 `jwt-private.pem`、`jwt-public.pem`（**仓库自带，克隆下来就有**，用于会话令牌签名）。
如需为本次部署换成独立密钥，用 `openssl` 生成一对覆盖即可（两个文件必须成对替换，否则旧会话全部失效）。`secrets/studiolo.lic` 是空占位文件，**不要删除**——后端激活时写入它，
删除后 Docker 会把挂载点建成目录，导致激活失败。

### 2.4 启动服务

**方案 A：通用服务器 (CPU)**

```
docker compose up -d
```

**方案 B：高性能服务器 (GPU，需已装 NVIDIA Container Toolkit)**

```
docker compose -f docker-compose-gpu.yml up -d
```

首次启动会拉取约 12 GB 镜像并初始化数据库，耗时取决于网络与磁盘；`docker compose ps` 中
`studiolo-backend` 显示 `Up (healthy)` 即表示依赖全部就绪。

> **GPU 版的后续命令**：指南中所有 `docker compose` 命令都要带上 `-f docker-compose-gpu.yml`。
> 嫌麻烦可以先执行 `export COMPOSE_FILE=docker-compose-gpu.yml`，之后的命令就与 CPU 版一致。

### 2.5 系统激活与授权

Studiolo 采用硬件绑定与在线热更新授权机制。系统启动后若检测到未授权状态，登录页会自动弹出
**授权管理**面板。

#### A. 获取机器码 (Hardware ID)

- 打开浏览器访问 `http://<服务器IP>:3001`，未激活时会自动弹出授权管理面板。
- 面板中系统会自动提取并显示当前服务器的 **机器码**，点击旁边的复制按钮。
- **⚠️ 若机器码区域显示错误信息或一直无法获取**：说明服务器环境不满足部署要求。请确认
  `docker-compose.yml` 原样保留（特别是 `- /:/host_sys:ro` 这一行挂载），然后
  `docker compose restart backend` 重试；仍失败请按 [5. 技术支持](#5-技术支持) 提供日志。

#### B. 申请授权文件

将复制到的 **机器码** 发送给供应商，您会收到一份专属于该服务器的 `xxx_studiolo.lic` 授权文件。

#### C. 在线上传激活（无需重启）

- 在登录页的授权面板中，点击上传区域或将 `.lic` 文件拖入。
- 系统会校验文件与机器指纹是否匹配；不匹配会提示「授权文件认证失败」。
- 校验通过后授权状态立即刷新，系统功能自动解锁。
- **持久化**：授权文件写入容器内的 `/app/studiolo.lic`，该路径已挂载到宿主机的
  `secrets/studiolo.lic`，**容器重建或升级后授权不丢失**。备份时请连同该文件一起备份。

### 2.6 初始化管理员账户

系统默认不预置任何特权账户。请先登录一次，再把该账户升级为管理员。

#### A. 登录账户

打开 `http://<服务器IP>:3001`，输入邮箱并获取验证码，完成登录（**首次登录即自动注册**）。

#### B. 连接数据库

在服务器终端执行：

```
docker exec -it studiolo-postgres psql -U studiolo -d studiolo_db
```

> 若您在 `.env` 里改过 `POSTGRES_USER` / `POSTGRES_DB`，请把命令里的 `studiolo` / `studiolo_db` 换成您的值。

#### C. 执行提权指令

在数据库交互界面中执行（请替换为您的登录邮箱）：

```
-- 1. 确认用户是否存在
SELECT id, email, user_type FROM users WHERE email = 'admin@yourcompany.com';

-- 2. 授予管理员权限
UPDATE users SET user_type = 'admin' WHERE email = 'admin@yourcompany.com';

-- 3. 再次确认（user_type 应为 admin）
SELECT id, email, user_type FROM users WHERE email = 'admin@yourcompany.com';

-- 4. 退出数据库
\q
```

#### D. 验证权限

回到浏览器刷新页面，点击右上角头像，应能看到「系统管理」入口。

------

## 3. 验证部署 (Verification)

### 3.1 检查容器状态

```
docker compose ps
```

- **预期结果**：`studiolo-backend`、`studiolo-frontend`、`studiolo-bge-m3-service`、`studiolo-milvus`、
  `studiolo-neo4j`、`studiolo-postgres`、`studiolo-redis`、`studiolo-minio`、`studiolo-etcd`
  的状态为 `Up` 或 `Up (healthy)`。

### 3.2 检查数据库初始化

```
docker exec studiolo-postgres psql -U studiolo -d studiolo_db -tAc \
  "select count(*) from information_schema.tables where table_schema='public' and table_name <> 'alembic_version'"
```

- **预期结果**：`25`。小于 25 说明 `init.sql` 没有执行（最常见原因是 `data/postgres/` 不是空目录，见 [2.1](#21-获取部署包并确认文件清单) 的说明）。

### 3.3 检查后端健康状态

```
curl http://127.0.0.1:8001/health
```

- **预期结果**：`{"status":"ok","checks":{"database":"ok","redis":"ok"}}`。
- 返回 `503` 且 `checks` 中某项为 `error`，说明对应依赖未就绪或密码配置不一致。
- 该接口不校验授权，可在激活前用于排查部署问题。

### 3.4 访问系统

- **前端应用**: `http://<服务器IP>:3001`
- **后端 API**: `http://<服务器IP>:8001`（生产环境默认关闭 Swagger 文档）

------

## 4. 常见问题 (FAQ)

**Q1: 启动时提示 "DATABASE_URL not found" 或后端反复重启？**

> **A**: 请确保是直接运行 `docker compose up -d`，而不是手动 `docker run` 单个容器——
> 连接串是由 compose 自动组装的。另外确认 `.env` 已从 `env.example` 复制并填写。

**Q2: Model Service 或 Milvus 启动后退出 (Exited)？**

> **A**: 绝大多数是内存不足。请确认服务器可用内存不低于 8 GB（推荐 32 GB），用
> `docker compose logs milvus` / `docker compose logs model-service` 查看具体报错。

**Q3: 如何重置系统（清空所有数据）？**

> **A**: ⚠️ **危险操作！** 执行以下命令将永久删除所有业务数据：
>
> ```
> docker compose down
> rm -rf data/
> docker compose up -d
> ```
>
> 注意 `secrets/studiolo.lic` 不会被删除，重启后授权仍然有效（机器没变就不需要重新激活）。

**Q4: 授权管理面板中机器码一直获取不到 / 显示错误信息？**

> **A**: 这不是授权文件问题，而是服务器环境不满足部署要求（最常见是没跑在 Linux 上，或
> compose 里的 `/:/host_sys:ro` 挂载被删掉）。请原样保留 `docker-compose.yml`，
> 执行 `docker compose restart backend` 重试；仍失败请按 [5. 技术支持](#5-技术支持) 提供日志。

**Q5: 注册后看不到「系统管理」？**

> **A**: 默认注册用户为普通用户。请参考 [2.6 初始化管理员账户](#26-初始化管理员账户) 手动提权。

**Q6: 服务器无外网（完全离线），怎么部署？**

> **A**: 在一台能联网的同架构（linux/amd64）机器上执行：
>
> ```
> docker compose pull
> docker save -o studiolo-images.tar $(docker compose config --images)
> ```
>
> 把 `studiolo-images.tar` 与部署包一起拷到离线服务器，然后：
>
> ```
> docker load -i studiolo-images.tar
> docker compose up -d
> ```
>
> 系统运行时不访问任何外部服务（邮箱 SMTP 与您配置的模型 API 除外）。

**Q7: 已有部署如何升级到新版本？**

> **A**: 替换部署包中的 `docker-compose.yml`（镜像 tag 会随版本变化）后执行：
>
> ```
> docker compose pull
> docker compose up -d
> ```
>
> 数据目录与 `secrets/` 保持不变即可；若有表结构变更，升级说明会另行给出对应命令。
> **升级前请备份** `data/` 与 `secrets/`。

------

## 5. 技术支持

如遇部署问题，请联系专属技术支持工程师，并提供 `docker compose logs` 导出的日志文件。

邮箱：shanpeng238@foxmail.com
