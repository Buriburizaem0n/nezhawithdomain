# 2026-10-22 上游同步

本次将三个子模块的上游主分支合并到定制分支，保留 domain 管理、WHOIS、到期通知、自动续费日期滚动、自定义品牌/背景与 agentcompat 扩展。

| 子项目 | 上游提交 | 本次新增提交数 |
| --- | --- | --- |
| 管理员前端 | nezhahq/admin-frontend `caf47ddec854639380a22aaf466b1cf00099de9a` | 18 |
| 用户前端 | hamster1963/nezha-dash-v2 `576e2307948ea6a12e4cc072039906ce801b23a2`（v2.5.1） | 13 |
| 后端 | nezhahq/nezha `a20c79b75ce4c04e59e2c9cd5fe6d4a55076eb5f` | 51 |

## 管理员交互修复

- Tailwind 4 的基础样式不会自动给按钮添加手型光标；为可用按钮恢复 `cursor: pointer`。
- pnpm 锁文件保留了 Dialog 1.1.15，而 Popover 使用新版。不同的 DismissableLayer/FocusScope 实例导致弹窗内菜单继承 `pointer-events: none`，表现为无法点击、搜索或滚轮滚动。
- 将 Dialog 最低版本提高至 1.3.1，并同步 npm/pnpm 锁文件，让相关弹层使用相同的内部依赖。
- 新增独立于后端的 Playwright 回归测试，覆盖 `/dashboard` 按钮光标和勾选，以及编辑服务器分组的滚动、搜索、多选、Escape 关闭菜单和提交内容。

## 上游功能与修复

- 服务器在线会话历史、按日期分组展示与后台统计保留窗口设置。
- GPU 显存数据协议、后端状态与前台图表展示。
- 访客接口要求认证时提示登录、国旗本地打包、减少首页持续动画和翻译更新。
- JWT IP 变化配置、NAT 凭证过滤、安全边界修复、告警最新状态与通知顺序修复。
- DDNS 空地址记录删除、TSDB 低磁盘空间保护及监控启动历史处理。

## 构建与部署

要求 Go 1.26.10+、CGO/C 编译器、Node.js 22.22.2+（或 24 LTS）与 pnpm 11+。

Go 1.26.6 的 HTTP/2 明文连接在协议切换后未清除 ReadHeaderTimeout，会中断长期连接；本次测试复现后升级同系列补丁版本，同时更新 CI 和版本策略断言。参考 [Go 官方缺陷记录](https://github.com/golang/go/issues/80927)。

部署前备份数据库和配置。首次启动会自动创建在线历史表；测试使用临时数据库，未操作运行中的实例。构建产物包含重新生成的 Swagger 与两个前端资源。

## 验证

- 两个前端均完成类型检查、生产构建和 lint。
- 管理员前端 45 项单元测试，用户前端 187 项单元测试。
- 2 项 Chromium 回归测试通过，覆盖上述鼠标与分组交互。
- 后端 `go test -mod=readonly ./...`、`go vet ./...` 和 `go test -mod=readonly -race -shuffle=on -count=1 ./...` 全部通过。
- 包含两个前端资源和 Swagger 文档的 Linux amd64 后端完整构建通过。

浏览器测试可运行：`cd admin-frontend-domain && pnpm exec playwright test tests/e2e/admin-interactions.spec.ts`。首次需要 `pnpm exec playwright install --with-deps chromium`。
