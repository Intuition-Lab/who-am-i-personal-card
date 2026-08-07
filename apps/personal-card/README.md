# Personal Card V5

同一套 Personal Card UI，可以在一个浏览器会话中安全切换不同的
Personal Model。当前包含：

- 本机 `LocalPersomeProvider`；
- Cecilia 与 Lin 两套可复现 fixture；
- 带 Bearer 鉴权、超时和安全错误边界的远程 Provider；
- Owner、Authorized Viewer、Public Visitor 三种服务端权限投影；
- 按 `modelId / connectorId / sessionId / grantId` 隔离的 Connector、
  Report 与 Evidence。

V5 的 Card、Spotlight、过去 / 现在 / 未来、Rewind、Memory Sky、
Identity、Swipe 动效和 Notion 式 Report 保持原来的视觉与交互。

## 内测用户安装

从产品仓库根目录执行：

```bash
bash install.sh --interactive
```

安装器会安装 `runtime.lock` 固定的 Personal Model commit（其包元数据为
0.3.2）、产品私有 Node.js、依赖和
`~/Applications/Who Am I.app`。用户完成 macOS 权限后，首次打开只需输入
自己的姓名和 handle；服务会生成稳定随机的本机 `modelId`，并从该 macOS
账户自己的 Persome 读取内容。

生产模式不注册 Cecilia 或 Lin，也不会在 Runtime 不可用时回退他人的
fixture。未安装、未授权、模型形成中和不可用都会显示真实引导状态。

## 开发与双模型验证

在本目录启动开发服务：

```bash
npm ci
npm start
```

可直接打开：

- Cecilia：`http://127.0.0.1:8772/?model=cecilia`
- Lin：`http://127.0.0.1:8772/?model=lin-demo`
- 运行时切换器：`http://127.0.0.1:8772/?dev=1&model=cecilia`
- Lin Public Visitor：`http://127.0.0.1:8772/?model=lin-demo&public=1`

开发切换器只在 `?dev=1` 且服务端允许开发模式时出现。默认页面不会增加
常驻控件。Lin 的开发 Grant 仅在开发模式签发；生产环境必须传入真实、
未过期且 model-bound 的 Grant。

固定使用 fixture 时：

```bash
WHOAMI_PROVIDER_MODE=fixture npm start
```

## 验证

```bash
npm test
npm run test:browser
npm run test:production-browser
```

- `npm test` 覆盖 Schema、Provider contract、activeModel 原子切换、
  Grant/Scope、会话、Connector/Event/Report/Evidence 隔离和服务端六模块
  串线回归，以及生产环境创建并重启恢复任意本机 owner。
- `npm run test:browser` 使用同一组件树实际完成 Cecilia → Lin → Cecilia
  无刷新切换，并操作 Rewind、Identity、Swipe、其他 Agent、Report、
  Evidence 和 Public Visitor 403。
- `npm run test:production-browser` 证明首次创建自己的 Card、生产不注册
  fixture，以及服务重启后恢复同一个稳定本机 owner。
- `npm run visual:baseline` 在 `1440×1000 @ DPR 1` 重新生成当前开发截图到
  `tests/visual/current/`；迁移前基线保存在 `tests/visual/baselines/`。

修改 `WhoAmI v5.template.html` 或 `WhoAmI v5.logic.js` 后，执行：

```bash
npm run build
```

它会把源模板与逻辑同步进 `WhoAmI v5.dc.html` 和浏览器实际加载的
`WhoAmI v5 · Persome Live.html`。

## 安全边界

- 服务只监听 `127.0.0.1`。
- 每个浏览器得到独立的 `HttpOnly; SameSite=Strict` 会话 Cookie。
- 模型切换只在完整 Snapshot 校验和权限投影成功后原子提交。
- 后续 API 从会话读取 `activeModelId`；请求体或 Query 不能覆盖模型。
- 未授权字段不会下发到浏览器，Public Projection 只包含 Card 与 Identity。
- Evidence reference 必须带当前 `modelId`。
- 模型切换会撤销旧 Connector Session、Coast allowlist，并关闭旧 Report、
  Rewind、Evidence、Share 与 Connector Picker。
- Provider、本机路径和远程响应中的敏感错误不会透传给浏览器。

数据契约见 `src/contracts/`，Provider 见 `src/providers/`，权限与会话见
`src/auth/`，Connector/Report/Evidence 隔离见 `src/connectors/` 与
`src/evidence/`。
