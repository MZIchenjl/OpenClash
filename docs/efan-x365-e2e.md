# Efan x365 / OpenClash 端到端验收

验收日期：2026-08-07。所有账号、密码、service token、真实 UUID、公钥、short ID、节点 URI、服务器地址和 OpenClash 本地认证值均已从本文档及 Git 排除。

## 被测对象

- OpenWrt：24.10.8，`armsr/armv8`，`aarch64_generic`，Docker 原生 ARM64。
- OpenClash：0.47.152 加本仓库 Efan 多 service 实现；最终验收包 `luci-app-openclash_0.47.152-x365_all.ipk` 的 SHA-256 为 `b614bd4b200fd80099bbaf577a552e9755c50ce6ef7a14c411b884a17d4bb920`。
- Mihomo：`cd4e8fa2`，Linux ARM64，`type: x365`；二进制 SHA-256 为 `f8b08b5480e9da61067b47149d2799d6392e890896c8d5088b1ea211886d3b4a`。
- OpenClash 测试容器：完整 LuCI、dnsmasq-full、firewall4、Ruby 3.3 及 OpenClash 运行依赖；不是仅运行转换脚本的最小容器。

x86_64 也完成了 OpenWrt 24.10.8、完整 OpenClash IPK 和修改后 Mihomo 的安装/启动检查；x86 核心 SHA-256 为 `90e82d31e399f46b43f5d6316b391d84a94beed5f5a3b90c1f4cd902558eef14`。ARM Mac 上的 Docker/QEMU x86 模拟环境中，OpenWrt 的 Ruby 3.3 在执行 `ruby -v` 时即发生解释器级段错误，因此真实登录功能验收改在原生 ARM64 容器完成。该限制不发生在 ARM64 容器。

## 真实账号验收结果

| 项目 | 结果 | 证据摘要 |
|---|---|---|
| LuCI 登录端点 | 通过 | HTTP 200，`application/json`，`session_state=logged_in` |
| 路由器记住账号 | 通过 | 后端不传 email 的 `status` 可从路由器缓存发现账号 |
| 全 service 拉取 | 通过 | 测试账号当前返回 1 个 service；1/1 更新成功 |
| 多 service 逻辑 | 通过 | 单元测试模拟 2 个 service，验证分别使用各自 token、分别写文件并合并 |
| 节点转换 | 通过 | 当前 service 转换出 110 个节点，类型全部为 `x365` |
| 单 service YAML | 通过 | 110 个代理、1 个 select、1 个 url-test，目标 Mihomo 校验成功 |
| all YAML | 通过 | 110 个代理、`Efan Services` + service select + url-test，目标 Mihomo 校验成功 |
| 缓存权限 | 通过 | 账号 JSON 与全部 YAML 均为 0600；敏感临时目录为 0700 |
| 密码不缓存 | 通过 | 账号 JSON 无 password key；登录临时文件数为 0 |
| Mihomo 原生代理 | 通过 | 抽测第 1/56/110 个节点，HTTPS 均返回 204 |
| 分组与节点选择 | 通过 | REST PUT 切换 service 内具体节点均返回 204，`now` 与选择值一致 |
| 完整 OpenClash 启动 | 通过 | 六阶段启动完成，日志为 `OpenClash Start Successful` |
| OpenClash 管理代理 | 通过 | 使用 OpenClash 生成的入口/认证，经 7890 访问 HTTPS 返回 204 |
| 运行中刷新 | 通过 | OpenClash 开启路由器自身代理时仍为 1/1 更新成功，随后代理继续返回 204 |
| 最终 IPK 回装 | 通过 | 强制回装后账号缓存、2 份原始 YAML 和 x365 核心均保留；缓存 token 刷新及目标 Mihomo 校验成功 |
| 重启持久化 | 通过 | 账号/原始 YAML SHA-256 精确一致；状态恢复为已登录；rc.d 自动启动后代理返回 204 |
| 页面状态机 | 通过 | 未登录/登录中/已登录/刷新中/失效/错误的 DOM 状态测试通过；LuCI 状态端点为 JSON |
| 退出清理 | 通过 | LuCI 返回 `logged_out`；账号 JSON 为 0，2 份 YAML 哈希不变，已加载代理继续返回 204 |

## OpenClash 实际运行配置

OpenClash 读取 `efan-${user}-all.yaml` 后生成自己的活动配置。脱敏后的结构验证结果：

- HTTP 7890、SOCKS 7891、redir 7892、mixed 7893、tproxy 7895。
- DNS 监听 7874；REST 控制器监听 9090。
- 110 个代理全部保留 `type: x365` 及 `host`、`path`、`sni`、`transport`、`client-fingerprint`、`reality-opts`、`udp` 字段。
- 3 个组：`Efan Services`、service select、service url-test。
- API host 的精确 DIRECT 规则位于 `MATCH,Efan Services` 之前。
- OpenClash 增加的 dashboard secret 和本地 HTTP/SOCKS authentication 由 OpenClash 自己持久化，不写入 Efan 账号缓存。

## 运行时发现并修复的问题

1. OpenWrt 24.10 的 LuCI ucode bridge 不接受旧式数值 `chmod` 参数。改为字符串 `"0700"`/`"0600"` 后，登录端点由 HTTP 500 恢复为 JSON。
2. OpenWrt Ruby 3.3 在读取空 curl stderr 文件时可能返回 nil。读取结果显式 `to_s` 后，不再误报 network_error。
3. 路由器自身代理会递归接管 API 控制请求。curl 子进程改用 OpenClash 防火墙明确预留的 GID 65534 旁路，并在配置首条加入 API host DIRECT 规则；OpenClash 运行中刷新已通过。
4. OpenClash 会生成自己的本地代理认证。代理验收从 UCI 内部读取该值，不在命令输出、文档或 Git 中暴露。

## UDP 状态

本地 HTTP/2 集成测试已覆盖 x365 UDP 首包、两字节大端长度帧、回包、截断排空和最大长度。真实节点经 SOCKS5 UDP 向公共 DNS 发包时 12 秒内没有回包；OpenClash 日志中的 NTP UDP 也只有发出记录。因此本文档不宣称当前线上 service 开通 UDP 转发。TCP/HTTPS 代理功能已由多个真实节点动态确认。

## 自动化检查

```text
OpenClash Ruby tests: 10 tests, 55 assertions, 0 failures
LuCI state tests:     efan_luci_ui_tests: ok
Mihomo targeted Go:   transport/x365, adapter/outbound, adapter, constant, component/tls
```

敏感值只进入 LuCI POST body 和权限 0600 的一次性请求文件；后端在成功或失败后均删除该文件。验收响应只读取状态、数量、类型、权限和 HTTP 状态，不输出 token 或真实节点字段。最终真实注销已经删除容器内账号及 service token 缓存，最后有效 YAML 按设计保留。
