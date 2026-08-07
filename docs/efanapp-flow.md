# Efan 登录、配置拉取与 OpenClash 转换

本文档针对 efanapp 1.0.40 macOS arm64。接口和字段来自应用静态分析及真实成功请求，不包含猜测字段。

## 证据基线

- DMG SHA-256：`a14e2224bafcd152836efd8e4cbe0b4695d30a4e929d9056abeb1a811dd33c9e`
- `core.dylib` SHA-256：`c15a0e31b1b1baa549976e0ff538bd5f46da26ff6e0db57c18f15a537a953939`
- API host：静态 TLS SNI 和真实请求均确认 `https://app.eod621808.com`
- 完整请求/响应 schema：见 `docs/efanapp-openapi.yaml`

## 处理流程

```text
账号 + 密码
    │ POST /v1/login, JSON {email,password}
    ▼
data.my_services[]
    │ 每个 service 使用自己的 access_token
    │ GET /v1/app?flag=wassvpn
    ▼
{proxy, servers, user}
    │ proxy: Base64 → RSA 分块解密 → zlib → YAML
    │ servers: show 过滤、sort_order/id 排序
    ▼
x365 节点 → Mihomo YAML
    ├─ efan-${user}-${service-id}.yaml
    └─ efan-${user}-all.yaml
```

### 1. 登录

```http
POST /v1/login HTTP/1.1
Host: app.eod621808.com
Content-Type: application/json

{"email":"user@example.com","password":"<password>"}
```

成功响应使用以下已确认字段：

- `data.token`：账号级 token；当前配置拉取不用它。
- `data.user`：账号对象。
- `data.my_services[]`：服务列表。
- `data.my_services[].id`：稳定的服务 ID，用于文件名。
- `data.my_services[].service_name`：显示名称。
- `data.my_services[].access_token`：该服务配置拉取所用 token。

密码只存在于 LuCI 请求、权限 `0600` 的一次性 JSON 文件和 HTTPS 登录请求中。客户端完成登录后删除请求文件，账号缓存不写入密码，也不保存当前流程不需要的账号级 token。

### 2. 拉取所有服务

一个账号可以有多个 service。实现遍历完整的 `data.my_services[]`，逐个请求：

```http
GET /v1/app?flag=wassvpn HTTP/1.1
Host: app.eod621808.com
Authorization: <当前 service 的 access_token 原值>
Accept: application/json
```

`Authorization` 不是 Bearer scheme，不能自行添加 `Bearer `。每个 service 独立拉取、转换和写文件；一个服务失败不阻止其他服务更新。

成功响应根对象直接包含：

- `proxy`：Base64 字符串，不是 JSON 对象。
- `servers[]`：节点显示和排序元数据。
- `user`：该服务的用户参数对象。

### 3. 解密 `proxy`

对应 `protocolabs-comm/comm.DecryptConfigData` 的已确认算法：

1. 严格 Base64 解码。
2. 密文长度必须是 256 的正整数倍。
3. 每 256 字节使用内嵌 RSA-2048 私钥和 PKCS#1 v1.5 padding 解密。
4. 按原顺序拼接每块明文。
5. zlib inflate。
6. 将结果作为 UTF-8 YAML 解析。

真实响应解出的是 YAML 根对象，已观察字段包括 `proxies`、`port`、`direct_domain`、`proxy_domain`、`domain_resolver`、`local_dns`、`dns` 和 `fallback_mode`。其中 `proxies` 是“显示名称 → 一个或多个 `x365://` URI”的映射。

### 4. 转换

转换器使用 `servers[].name` 对齐解密后的 `proxies`：

- `show == 0` 的节点不输出。
- 先按 `sort_order`，再按 `id` 和名称稳定排序。
- 一个名称包含多个 URI 时，用 `#2` 等后缀保证节点名唯一。
- URI 只接受已确认参数 `path`、`host`、`sni`、`pbk`、`sid`；缺失、重复或出现未知参数均拒绝。
- 输出节点 `type: x365`，协议细节见 `docs/x365-protocol.md`。

## 最终配置长什么样

单服务文件是标准 Mihomo YAML，OpenClash 加载后可以像其他节点类型一样选择策略组和代理：

```yaml
proxies:
  - name: 香港01
    type: x365
    server: edge.example.com
    port: 443
    uuid: 00000000-0000-0000-0000-000000000000
    host: authority.example.com
    path: /hk1
    sni: reality.example.com
    transport: h2
    client-fingerprint: chrome
    reality-opts:
      public-key: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
      short-id: 0123456789abcdef
    udp: true

proxy-groups:
  - name: Efan - 主服务
    type: select
    proxies: [Efan - 主服务 Auto, 香港01]
  - name: Efan - 主服务 Auto
    type: url-test
    url: https://www.gstatic.com/generate_204
    interval: 300
    proxies: [香港01]

rules:
  - MATCH,Efan - 主服务
```

汇总文件 `efan-${user}-all.yaml` 的首层组是 `Efan Services`。它引用每个服务的选择组；每个服务组又包含自动测速入口和该服务全部可见节点。因此同一个活动配置中可以先选服务，再手选节点。

## 缓存和失效规则

- 账号缓存：`/etc/openclash/efan-${user}.json`，权限 `0600`。
- 单服务配置：`/etc/openclash/config/efan-${user}-${service-id}.yaml`，权限 `0600`。
- 汇总配置：`/etc/openclash/config/efan-${user}-all.yaml`，权限 `0600`。
- 写入使用同目录临时文件、`fsync` 和原子 rename。
- 登出删除账号缓存，保留全部 YAML。
- 任一服务明确返回 HTTP 401/403 时删除账号缓存，保留最后有效 YAML。
- 网络失败、TLS 错误、超时和 5xx 不删除账号缓存，也不覆盖最后有效 YAML。
