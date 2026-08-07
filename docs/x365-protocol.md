# x365 v1 协议实现说明

本说明覆盖配置中 `x365://` URI 使用的 x365 v1。efanapp 的 `core.dylib` 还包含独立的 `X365V2Outbound`（HTTP/2、HTTP/3 和多路径），它不是同一个 wire protocol，本次 `type: x365` 不宣称兼容 x365v2。

## 配置字段

```yaml
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
```

- `server`、`port`：底层 TCP 和 REALITY 连接目标。
- `sni`：REALITY/TLS server name。
- `host`：HTTP/2 `:authority`，与 `server`、`sni` 分开处理。
- `path`：HTTP/2 POST path。
- `uuid`：首包中的 16 字节用户 ID。
- `reality-opts`：Mihomo 现有 REALITY 公钥和 short ID。
- `transport`：v1 固定为 `h2`。
- `udp`：允许 Mihomo 调用 x365 UDP stream。

实现对字段做严格校验，不补造未见于官方 URI 的参数。

## 传输层

每个代理连接使用一个双向 HTTP/2 POST stream：

```text
URL          https://<server>:<port><path>
:authority   <host>
method       POST
content-type application/grpc
user-agent   Mozilla/5.0 ... Chrome/120.0.0.0 ...
referer      https://<server>:<port><path>?padding=<100..999 个字符 "0">
```

底层 TLS 使用 REALITY 和 ALPN `h2`。efanapp 1.0.40 的 x365 REALITY client version 静态确认为 `1.8.1`。HTTP/2 transport 在同一节点的多个 stream 间复用底层连接；每个目标连接仍有独立的 POST stream。

## 请求首包

`m4a8cbf22/pcb7c32._ms`（`core.dylib` 地址 `0x68eea0`）构造首包：

| 偏移 | 长度 | 内容 |
|---:|---:|---|
| 0 | 4 | ASCII `X365` |
| 4 | 1 | version，固定 `0x01` |
| 5 | 1 | network：TCP=`0x01`，UDP=`0x02` |
| 6 | 16 | UUID 原始 16 字节 |
| 22 | 2 | 目标端口，大端 |
| 24 | 1 | 地址类型：域名=`0x02`，IP=`0x03` |
| 25 | 可变 | 地址内容 |

域名地址内容是“一字节长度 + 域名字节”，最大 255 字节。IP 地址内容固定为 16 字节；IPv4 放在前 4 字节，后 12 字节为零，不使用 IPv4-mapped IPv6 表示。

## 响应首包

客户端第一次读取响应时消费 5 字节：

```text
58 33 36 35 SS
 X  3  6  5 status
```

前四字节必须为 `X365`，`status == 0` 表示成功。状态检查延迟到第一次 `Read`；这允许调用方在 UDP stream 上先发送首个数据报，行为与官方 `(*_mz).Read` 一致。

## TCP

请求首包之后，POST request body 和 response body 都是无额外分帧的 TCP 字节流。连接关闭时取消 HTTP 请求并关闭请求/响应流。

真实节点动态验证：修改后的 Mihomo 通过 x365 v1 完成 HTTPS CONNECT，访问 `https://www.gstatic.com/generate_204` 返回 HTTP 204。

## UDP

UDP 仍是一条绑定单一目标地址和端口的 HTTP/2 stream。每个数据报使用两字节大端长度：

```text
0       2   payload_length，0..65535
2       N   UDP payload
```

该格式由 `(*_mz).Read`（`0x693080`）和 `(*_mz).Write`（`0x693460`）静态确认。若接收缓冲区小于数据报，官方行为是返回可容纳的前缀并丢弃该数据报剩余字节，以保持下一帧对齐；Mihomo 实现保持相同行为。

本地 HTTP/2 双向集成测试覆盖 UDP 首包、延迟状态响应、长度封装、回包、截断排空和 65535 字节上限。当前测试账号的一台真实节点对三个公共 DNS 目标均未返回 UDP 数据报，因此不能把“该服务节点已开放 UDP 转发”写成动态确认；这不改变 wire format 的静态证据和本地互操作测试结果。

## Mihomo 开发入口

- `transport/x365/frame.go`：首包、响应状态和地址编码。
- `transport/x365/client.go`：REALITY 之上的双向 HTTP/2 stream、连接池和 UDP 分帧。
- `adapter/outbound/x365.go`：Mihomo outbound、TCP/UDP adapter 和 YAML 字段。
- `adapter/parser.go`：注册 `type: x365`。
- `constant/adapters.go`：注册 `X365` adapter type。

测试向量和 HTTP/2 互操作测试位于 `transport/x365/*_test.go` 与 `adapter/outbound/x365_test.go`，全部使用非生产 UUID、公钥、域名和本地 TLS server。
