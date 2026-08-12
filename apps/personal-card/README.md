# Persome Desktop

Persome 是正式的 macOS Electron App，不是让用户打开的 HTML 页面。
HTML 原型只保留为视觉基线；生产界面由 React、TypeScript、Base UI、
Tailwind 和 Electron 窗口代码实现。

## 产品入口

- 启动 App 或再次点击 Dock 图标，最先出现的是独立 Spotlight / Quick Box。
- Quick Box 的 `Open app`、`Today`、`This week`、`This month` 和 `Map`
  才展开无系统红黄绿控制点的完整 Dashboard；Personal Card 在首页上方。
- `⌘⇧Space` 打开独立 Quick Box 窗口；它不是 App 内的模拟弹层。
- 菜单栏常驻 Persome 图标，可打开 Quick Box、Map、Rewind、Swipe 和设置。

完整 App 内包含 Personal Card 正反面、Jot / Ask、活动热力图、Map 星云图、
Living Model、日 / 周 / 月 / 年 Rewind、Remind、Swipe Your Card、MCP Grant、
Agent Report、Evidence、数据权限和本地导出。Week、Month 和 Year 只显示真实
采集日期；没有数据的日期保持为空，不会复制同一天来填满界面。

## App 架构

- `electron/main.mjs`：无系统窗口控制点的 Dashboard、启动即出现的独立 Quick
  Box、菜单栏、全局快捷键、权限、
  本地导出和后台服务生命周期。
- `electron/preload.cjs`：最小化、类型明确的 IPC 桥；Renderer 无 Node 权限。
- `renderer/`：React / TypeScript 组件和完整视觉系统。
- `persome-card-server.mjs`：仅监听 loopback 的产品后端。
- `src/providers/`：本机、远程和 Snapshot Provider。
- `src/auth/`：Owner / Grant / Scope / Viewer Session。
- `src/connectors/` 与 `src/evidence/`：按 model、connector、session 和 grant
  隔离的连接、报告与证据。

生产 App 使用 `8773` 的私有 loopback 服务，避免把旧的 `8772` HTML 预览
误认为 Electron 后端。产品 Profile 存在 Electron 自己的 owner-local
`userData` 目录，不从下载包携带任何人的 Card。Cecilia 和 Lin 只存在于
测试 fixture，永远不会在生产启动时注册。

## 本地开发

```bash
npm ci
npm run desktop
```

需要前后端热更新时，分别运行：

```bash
npm start
npm run dev
npm run dev:electron
```

## 构建 App

```bash
npm run typecheck
npm test
npm run pack:electron
npm run dist:electron
```

`pack:electron` 生成可直接打开的 `Persome.app`；`dist:electron` 生成 DMG 和
ZIP。公开分发仍需要 Apple Developer ID 签名与 notarization。没有证书时，
本地构建会保持未签名，只适合开发验收。

App 内含同仓库的锁定 Runtime 安装入口。已有安全、owner-controlled 的
Personal Model 会直接连接；没有 Runtime 时，首次启动引导会调用
`runtime.lock` 固定版本的安装器，并保持当前 Persome App bundle 不变。

## 必须通过的验证

```bash
npm run typecheck
npm test
```

测试覆盖 Provider contract、activeModel 原子切换、Cecilia / Lin 六模块不串
线、Grant / Scope、Connector / Report / Evidence、不同 macOS owner 隔离、
生产包无 demo 身份、Electron 安全配置和内置 Runtime 安装入口。

## 安全边界

- 后端只监听 `127.0.0.1`。
- `contextIsolation`、Chromium sandbox 和 `webSecurity` 始终开启，
  `nodeIntegration` 始终关闭。
- 模型切换只在完整 Snapshot 校验与权限投影成功后原子提交。
- 请求体和 Query 不能覆盖会话中的 active model。
- Public Projection 只包含 Card 与 Identity。
- Evidence reference 必须绑定当前 `modelId`。
- 模型切换会撤销旧 Connector Session 和 Evidence allowlist。
- Provider、路径与远程响应中的敏感错误不会透传到 Renderer。
