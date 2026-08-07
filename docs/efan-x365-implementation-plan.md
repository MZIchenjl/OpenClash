# Efan 登录、配置转换与 Mihomo x365 实施计划

## 目标与原则

- 在 OpenClash 中完成 Efan 账号密码登录、服务发现、配置拉取和 Mihomo 配置转换。
- 账号缓存命名为 `/etc/openclash/efan-${user}.json`，配置命名为 `/etc/openclash/config/efan-${user}-${service}.yaml`。
- 每个 service 保留独立配置，并额外生成 `/etc/openclash/config/efan-${user}-all.yaml`；汇总配置提供服务级和节点级可选策略组。
- 密码只用于一次登录请求，永不落盘；账号缓存只保存后续刷新所需的服务 token 和服务元数据。
- 登出或确认鉴权失效时删除账号缓存；最后一份验证成功的 YAML 配置始终保留。
- 在 Mihomo 中原生实现 `type: x365`，不依赖闭源 `core.dylib`。
- 接口字段、解密方式和协议行为必须有静态二进制或动态抓包依据；未确认的行为不得作为兼容逻辑提交。

## 第一阶段：逆向分析与证据固化

1. 固化 efanapp 1.0.40 DMG、Flutter AOT 和 `core.dylib` 的版本、哈希及导出符号。
2. 记录并复验 API：
   - `POST https://app.eod621808.com/v1/login`
   - JSON 请求字段 `email`、`password`
   - 登录响应中的 `data.my_services[].access_token`
   - `GET /v1/app?flag=wassvpn`
   - `Authorization` 使用服务 `access_token` 原值，不添加 `Bearer`
3. 定位 `proxy` 的解密、解压及节点模板合并逻辑，确认 `proxy`、`servers`、`user` 的关联关系。
4. 静态分析并动态验证 `x365://` 节点实际使用的 x365 v1 TCP、UDP、HTTP/2、REALITY、padding、连接池及错误码行为。x365v2 是 `core.dylib` 中独立的 HTTP/2/HTTP/3 多路径协议，不混入本次 `type: x365`。
5. 文档中的结论标记为“静态确认”“动态确认”或“未确认”；生产实现只使用前两类。

交付文档：

- `docs/efanapp-openapi.yaml`
- `docs/efanapp-flow.md`
- `docs/x365-protocol.md`
- 脱敏协议帧及转换测试向量

## 第二阶段：OpenClash 登录与缓存

在 `feature/x365` 分支新增独立 Efan 管理入口和以下 LuCI 操作：

- 登录
- 查询登录状态与服务列表
- 拉取或更新指定服务配置
- 登出

缓存规则：

- `${user}` 取规范化邮箱；保留 `@._+-`，过滤路径字符并限制长度。
- `${service}` 使用稳定、唯一的服务 ID，显示名称保存在 JSON/YAML 内容中。
- `/etc/openclash` 下的账号文件权限为 `0600`；临时目录和敏感缓存目录权限为 `0700`。
- 使用同目录临时文件、刷新数据、文件校验和原子重命名，禁止半写入覆盖有效缓存。
- HTTP 401/403 或明确的鉴权失败业务码删除账号缓存；网络错误、超时、TLS 错误和 5xx 不删除。
- 登出只销毁账号/token 缓存和临时文件，不删除已经生成的 YAML。
- 服务端未确认 logout 接口前，登出定义为本地凭据销毁。

账号缓存 schema：

```json
{
  "schema": 1,
  "email": "user@example.com",
  "services": [
    {
      "id": "service-id",
      "name": "service-name",
      "status": 1,
      "access_token": "<sensitive>"
    }
  ],
  "updated_at": 0
}
```

## 第三阶段：配置解密与转换

1. 对每个 `my_services[]` 使用其 `access_token` 拉取 `/v1/app?flag=wassvpn`。
2. 验证 `code`、`proxy`、`servers`、`user`，按已确认算法解密和解压 `proxy`。
3. 合并用户参数、服务器元数据和节点模板；过滤隐藏、禁用或缺少必需字段的节点，并按 `sort_order` 稳定排序。
4. 输出包含 `proxies`、服务级选择组和默认 `MATCH` 规则的 YAML。
5. 汇总所有已缓存服务，输出 `efan-${user}-all.yaml`：首层 `Efan Services` 选择服务，第二层可手选节点或进入自动测速组。
6. 使用目标 Mihomo 校验临时配置；只有校验成功才原子替换旧缓存。

目标节点 schema：

```yaml
proxies:
  - name: 香港01
    type: x365
    server: example.com
    port: 443
    uuid: 00000000-0000-0000-0000-000000000000
    host: authority.example.com
    path: /example
    sni: reality.example.com
    transport: h2
    reality-opts:
      public-key: base64url-key
      short-id: 0123456789abcdef
    udp: true
```

## 第四阶段：Mihomo x365 原生实现

在 `feat/x365` 分支新增 `transport/x365` 和 outbound adapter：

- URI和 YAML 参数解析、严格校验与脱敏错误。
- x365 请求首包及 `X365 + status` 响应前导。
- TCP 双向流、UDP 数据报和 HTTP/2 连接池。`x365://` 的 v1 实现不宣称兼容独立的 x365v2/H3 协议。
- REALITY 握手复用 Mihomo 现有实现；x365 使用静态确认的客户端版本 `1.8.1`，不改变其他协议默认值。
- 支持 `dialer-proxy`、接口、routing mark、TFO/MPTCP、取消、超时和资源释放。
- 在 adapter parser 和 `AdapterType` 中注册 `type: x365`。

已确认的 x365 v1 首包：

```text
0       4    "X365"
4       1    version = 1
5       1    1=TCP, 2=UDP
6       16   UUID
22      2    目标端口，大端
24      1    2=域名, 3=IP
25      ...  地址
```

响应前导为 `X365 <status>`，状态 0 表示成功。

## 测试与完成标准

- OpenClash 覆盖正确/错误登录、多服务、缓存权限、原子更新、登出、401/403、5xx、超时、Unicode 和路径穿越测试。
- Mihomo 覆盖 URI/YAML、IPv4/IPv6/域名首包、TCP/UDP、响应错误、H2、REALITY 1.8.1、连接池、取消和超时测试。
- 使用真实账号逐服务生成配置，但不保存密码；所有配置通过 `mihomo -t -f`。
- 验证 HTTP、HTTPS、DNS/UDP 和并发连接。
- 密码和 token 不出现在日志、进程参数、调试包、测试夹具或 Git 记录中。
- 登出或鉴权失效后账号缓存消失，但最后一份有效配置仍可使用。

最终验收必须在 OpenWrt Docker 环境中执行，不以宿主机单元测试替代：

1. 构建本次修改后的 Mihomo（Clash Meta）Linux 核心，并安装完整 OpenClash 包及其运行依赖。
2. 启动可重复创建的 OpenWrt 容器，挂载独立的 `/etc/openclash` 持久化目录，记录镜像、架构和包版本。
3. 通过 OpenClash 的正式入口完成账号密码登录，确认 `data.my_services[]` 中每个 service 都独立拉取并生成对应的 `efan-${user}-${service}.yaml`，同时生成带服务/节点选择组的 `efan-${user}-all.yaml`。
4. 由 OpenClash 调用目标 Mihomo 核心校验并加载每份配置，检查进程状态、控制器状态、日志脱敏及所有文件权限。
5. 对每个 service 至少验证 TCP/HTTP、TLS/HTTPS、DNS/UDP，并验证多 service 部分失败不会覆盖其他 service 的有效配置。
6. 验证容器重启后的 token/config 缓存行为；验证登出及 401/403 会删除账号缓存但保留 YAML，5xx、超时和断网不会误删 token。
7. 将无凭据、无 token 的测试命令、结果摘要和可复现步骤写入验收文档；敏感值只允许存在于容器内 `0600` 临时文件，并在测试结束后清除。
