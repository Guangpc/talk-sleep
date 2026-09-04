# OpenAI Next / LLM 可行性研究：朋友式中文对话可行性

> 研究目的：判断 `https://api.openai-next.com` 与 `gpt-5.6-sol`（尤其 `high` / `xhigh`）是否适合服务端理解朋友式中文对话，并比较优先中国大陆可用、中文自然、可服务端接入的官方替代模型。
>
> 观测时间：2026-09-03。官方模型、价格、动态别名和生命周期页面会变化，采购前必须重新核验。
>
> 安全声明：本报告没有读取、使用、猜测、发送或记录任何 API key、token、Cookie 或 Authorization 值；没有调用任何模型推理 API；没有把任何真实朋友对话发送给第三方；没有修改本文件以外的仓库文件。

## 1. 最终结论

### 1.1 对 `api.openai-next.com` 的结论

**暂不批准生产使用。**目前没有足够一手证据证明 `api.openai-next.com` 是 OpenAI 官方服务、获得 OpenAI 授权，或真正实现了 OpenAI-compatible API。

公开无认证探测只证明了：

- 域名在观测时点可访问；
- 根页面、`/docs`、`/redoc` 返回 Vectrust 前端页面；
- `/v1/models`、`/v1/chat/completions`、`/v1/responses` 路由存在并要求认证；
- 某个 Chat Completions OPTIONS 预检返回通用 CORS 响应。

这些现象**不能**证明：

- OpenAI 官方身份或授权关系；
- 后端真实模型是官方 GPT-5.6 Sol；
- `gpt-5.6-sol` 这个 model ID 可用；
- `high` / `xhigh` 被接受、映射正确且计费一致；
- 请求字段、响应字段、stream、tool calls、structured outputs、Responses API 与 OpenAI 一致；
- 价格、上下文、限流、SLA、数据留存、跨境和删除政策。

### 1.2 推荐顺序

若目标是中国大陆服务端生产，先建立官方直连基线：

1. **阿里云百炼北京地域 / Qwen**：本次严格核验中唯一明确给出中国大陆地域端点与模型服务证据的候选。聊天基线可用 `qwen3.7-plus`；质量上限再测当前页面列出的 `qwen3.8-max` 或其固定快照。
2. **Kimi K3**：官方 quickstart 直接写明“更擅长中文和英文的对话”，中文对话定位证据最直接；代价是始终推理、价格较高且没有 `xhigh`。
3. **DeepSeek V4-Flash / V4-Pro**：官方明确 OpenAI/Anthropic 格式兼容，价格有优势；但当前 V4 的朋友式中文自然度需要业务 A/B，不能用历史 V3 文字更新替代实测。
4. **智谱 GLM-5.3**：官方 OpenAI 兼容 API 已验证，模型文档有创作、角色和多轮语气场景；中国大陆地域 SLA、当前静态价格和朋友式自然度仍需核验。
5. **MiniMax M2-her**：保留为待补证据候选。当前没有足够官方一手材料确认其准确 model ID、API、地区、中文能力、价格或生命周期，不进入已验证生产候选。

## 2. `api.openai-next.com`：无密钥公开探测

### 2.1 探测安全边界和实际命令

所有命令均为公开 HTTPS 只读探测，不带 `Authorization`、API key、token 或 Cookie；POST 只发送空 JSON `{}`，未触发模型生成。

```text
curl -sS --connect-timeout 10 --max-time 20 -i https://api.openai-next.com/
curl -sS --connect-timeout 10 --max-time 20 -i https://api.openai-next.com/v1/models
curl -sS --connect-timeout 10 --max-time 20 -i -X OPTIONS https://api.openai-next.com/v1/models
curl -sS --connect-timeout 10 --max-time 20 -i https://api.openai-next.com/docs
curl -sS --connect-timeout 10 --max-time 20 -i https://api.openai-next.com/openapi.json
curl -sS --connect-timeout 10 --max-time 20 -i https://api.openai-next.com/swagger.json
curl -sS --connect-timeout 10 --max-time 20 -i https://api.openai-next.com/openapi.yaml
curl -sS --connect-timeout 10 --max-time 20 -i https://api.openai-next.com/api-docs
curl -sS --connect-timeout 10 --max-time 20 -i https://api.openai-next.com/redoc
curl -sS --connect-timeout 10 --max-time 20 -i -X POST https://api.openai-next.com/v1/chat/completions -H 'Content-Type: application/json' --data '{}'
curl -sS --connect-timeout 10 --max-time 20 -i -X POST https://api.openai-next.com/v1/responses -H 'Content-Type: application/json' --data '{}'
curl -sS --connect-timeout 10 --max-time 20 -i -X OPTIONS https://api.openai-next.com/v1/chat/completions -H 'Origin: https://example.invalid' -H 'Access-Control-Request-Method: POST' -H 'Access-Control-Request-Headers: content-type'
```

### 2.2 已验证响应

| 方法 / URL | 观测结果 | 仅能证明 | 明确不能证明 |
|---|---|---|---|
| `GET https://api.openai-next.com/` | HTTP 200，HTML；`<title>Vectrust</title>`；description 是 Vectrust 中文智算/平台介绍 | 域名可访问且有网页 | 不是 OpenAI 官方身份，不证明 API 或模型来源 |
| `GET https://api.openai-next.com/docs` | HTTP 200，同一 Vectrust HTML 前端壳 | 该路径被前端接管 | 不是可读 API reference |
| `GET https://api.openai-next.com/redoc` | HTTP 200，同一 Vectrust HTML 前端壳 | 该路径被前端接管 | 不是 ReDoc schema |
| `GET https://api.openai-next.com/openapi.json` | HTTP 200，`text/plain`，响应长度 0 | URL 有响应 | 没有 OpenAPI schema |
| `GET https://api.openai-next.com/swagger.json` | HTTP 200，`text/plain`，响应长度 0 | URL 有响应 | 没有 Swagger schema |
| `GET https://api.openai-next.com/openapi.yaml` | HTTP 200，但返回 Vectrust HTML 壳 | 路径被前端接管 | 不是 YAML OpenAPI |
| `GET https://api.openai-next.com/api-docs` | HTTP 404；JSON `Invalid URL (GET /api-docs)` | 该候选公开路径不存在 | 不排除未猜测的私有路径，但未找到公开 reference |
| `GET https://api.openai-next.com/v1/models` | HTTP 401；JSON error message `Invalid token`，type `shell_api_error` | 路由存在并认证拦截 | 无法读取模型清单或证明兼容 |
| `POST https://api.openai-next.com/v1/chat/completions`，空 JSON | HTTP 401；JSON error message `Invalid token` | 路由存在并认证拦截 | 无法验证 Chat schema、响应、stream、tools |
| `POST https://api.openai-next.com/v1/responses`，空 JSON | HTTP 401；JSON error message `Invalid token` | 路由存在并认证拦截 | 无法验证 Responses schema 或 reasoning |
| `OPTIONS https://api.openai-next.com/v1/models` | HTTP 404；`Invalid URL (OPTIONS /v1/models)` | 该方法/路径组合未成功 | 不能推断 GET/POST 是否兼容 |
| `OPTIONS https://api.openai-next.com/v1/chat/completions`，带示例 Origin 的预检 | HTTP 204；`Access-Control-Allow-Origin: *`、`Access-Control-Allow-Credentials: true`、允许 GET/POST/PUT/DELETE/OPTIONS、headers `*` | 网关返回通用 CORS 预检 | CORS、方法名和路径名都不是 OpenAI compatibility 证明 |

响应头中出现 Cloudflare 与 `x-shellapi-request-id`；它们只是本次观测的响应元数据，不能据此推断运营主体、OpenAI 授权或后端模型。`Access-Control-Allow-Origin: *` 与 credentials 同时出现，也应要求供应商解释实际浏览器安全策略。

### 2.3 已验证 / 未验证清单

**已验证：**公开域名在观测时点可访问；根页面标题为 Vectrust；若干 `/v1` 路由存在并认证拦截；Chat 路由对 OPTIONS 返回通用预检。

**未验证：**OpenAI 官方/授权关系；成功的 `/v1/models` 内容；`gpt-5.6-sol` 是否真实可用；后端版本；`high`/`xhigh` 映射；Chat/Responses/stream/tool/structured-output/reasoning 字段兼容；错误 schema；价格、配额、限流、SLA、状态页、故障处理、留存、删除、跨境和大陆合规。

## 3. Harness 与 agent-reach 事实

### 3.1 Harness 事实

- 当前工作区是 `/Volumes/T7Ssk/AI/deepseek`；目标仓库路径为 `/Volumes/T7Ssk/AI/deepseek/sleep-companion`。
- Harness 实现 checkout 的路径是 `/Applications/DSH Desktop.app/Contents/Resources/app.asar.unpacked/`；它与当前工作目录分离。本研究没有把该路径当工作区，也没有修改 Harness checkout。
- 本次没有启动替换服务器、没有访问或修改 DSH Web GUI、没有改动应用代码或配置。
- 用户要求只修改目标研究文件；本次写入的唯一目标是本文档。

### 3.2 agent-reach 的实际使用

用户要求先尝试 agent-reach 公开网页搜索/阅读后端。实际使用：

```text
agent-reach doctor --json
```

命令可用。Doctor 只返回渠道状态和常规诊断；没有输出任何凭据值，也没有执行会写 device-id 的 `gh auth status`。Doctor 显示 GitHub 为 warn（检测到显式认证配置但未实时验证），YouTube/Bilibili 为可用；本研究不需要登录态社交平台，因此没有调用它们，也没有打开、读取、复制或使用任何认证配置。

官方网页的公开 reader 采用：

```text
curl -sS --connect-timeout 10 --max-time 30 https://r.jina.ai/https://<官方原始 URL>
```

Jina 只是公开网页读取通道；报告中的事实引用指向页面的官方原始 URL，不把 Jina 当作权威来源。

一次用条件 shell 检查 agent-reach 的 batch smoke test 因执行器不支持该段 `if` 语法而出现 `parse error near if`；随后直接执行 `agent-reach doctor --json`，成功完成检查。该失败不是目标 API 的响应。

最后执行：

```text
agent-reach check-update
```

结果：当前版本 `v1.5.0`，已是最新版本。

## 4. OpenAI 官方模型基准

> 本节只证明 OpenAI 官方页面所描述的官方模型；不能外推到 `api.openai-next.com`。

### 4.1 GPT-5.6 Sol

来源：[GPT-5.6 Sol Model](https://developers.openai.com/api/docs/models/gpt-5.6-sol)

**已验证：**

- 官方 ID 为 `gpt-5.6-sol`；`gpt-5.6` alias 路由到 GPT-5.6 Sol；
- Sol 是 GPT-5.6 家族旗舰模型；
- `reasoning.effort` 支持 `none`、`low`、`medium`（默认）、`high`、`xhigh`、`max`；
- 上下文窗口 1,050,000 tokens，最大输出 128,000 tokens；
- 知识截止日期 2026-02-16；
- 输入 text/image，输出 text；
- 每 1M tokens 价格：输入 $4.00、缓存输入 $0.40、输出 $20.00。

来源：[Reasoning models](https://developers.openai.com/api/docs/guides/reasoning)

- effort 较低通常更快、token 用量更低；较高通常更完整但延迟/成本更高；
- 官方把 `low` 的常见用途列入 customer support / chat assistant workflows；
- `high`/`xhigh` 应在确认有质量收益后使用；
- reasoning tokens 不通过 API 展示，但占用上下文并按 output tokens 计费；
- GPT-5.6 的跨轮 reasoning context 支持也不能假定由中转站实现。

来源：[Model guidance](https://developers.openai.com/api/docs/guides/latest-model)

- reasoning、tool calling、多轮工作流推荐 Responses API；
- Chat Completions 仍支持，但 Responses 对推理通常更合适；
- Sol 旗舰、Terra 平衡、Luna 高吞吐/低成本；
- 朋友式闲聊应以 `low`/`none` 为延迟和成本基线，只有 A/B 证明收益才提高 effort。

来源：[GPT-5.6 正式发布页](https://openai.com/zh-Hans-CN/index/gpt-5-6/)

- OpenAI 页面称 GPT-5.6 已结束有限预览并正式推出 Sol、Terra、Luna；
- 这证明官方系列存在，不证明任何第三方域名的授权或实现。

### 4.2 地区政策

来源：[OpenAI API - Supported Countries and Territories](https://help.openai.com/en/articles/5347006-supported-countries-and-regions)

- OpenAI 官方说明 API 只支持清单中的国家/地区；未列入即不支持；
- 在清单外访问或提供访问可能导致账号被封禁或暂停；
- 本次抓取页面列出 Singapore，未列 China mainland；该动态页面应在采购前重新核验；
- 不应把第三方中转站当作规避 OpenAI 地区政策的方案。

## 5. 官方替代候选

### 5.1 阿里云百炼 / Qwen：大陆地域首选

#### API、地域和服务端接入

来源：[百炼简介](https://help.aliyun.com/zh/model-studio/what-is-model-studio)、[首次调用千问 API](https://help.aliyun.com/zh/model-studio/first-api-call-to-qwen)

- 百炼提供 OpenAI 兼容接口、DashScope SDK 等接入方式；
- 官方示例要求 API key，但本研究未获取、读取或使用任何 key。

来源：[OpenAI 兼容 Chat](https://help.aliyun.com/zh/model-studio/qwen-api-via-openai-chat-completions)

华北2（北京）官方配置：

```text
base_url: https://{WorkspaceId}.cn-beijing.maas.aliyuncs.com/compatible-mode/v1
POST https://{WorkspaceId}.cn-beijing.maas.aliyuncs.com/compatible-mode/v1/chat/completions
```

需要业务空间 ID；不同地域的 URL 不应混用。

来源：[OpenAI 兼容 Responses](https://help.aliyun.com/zh/model-studio/qwen-api-via-openai-responses)

- 官方提供 `/compatible-mode/v1/responses`；
- 支持字符串输入和 Chat 风格消息数组；文档说明可用 `previous_response_id` 简化上下文管理；
- 具体能力和限制按模型、地域页面为准。

来源：[地域及接入域名](https://help.aliyun.com/zh/model-studio/beijing-access-information)

- 地域决定接入点和数据存储位置；
- 服务部署范围决定推理执行位置；
- 北京地域端点是本次唯一达到严格“官方明确中国大陆地域服务”证据的候选。

这并不自动证明某一账号有配额、全部模型已开通或业务数据合规；账号权限、限流、合同和 SLA 仍需单独核验。

#### 模型、中文证据、价格和生命周期

来源：[文本生成模型选择](https://help.aliyun.com/zh/model-studio/text-generation-model)

- 官方为聊天机器人、内容生成、摘要总结、文档处理等场景给出模型选择；
- 页面将 `qwen3.7-plus` 作为能力/成本均衡选择，并将 `qwen3.8-max` 作为更强推理选择；动态页面内容应复核。

来源：[Qwen3 官方仓库](https://github.com/QwenLM/Qwen3)

- Qwen3 README 明确写到 superior human preference alignment；
- 明确擅长 creative writing、role-playing、multi-turn dialogues、instruction following，并追求更自然、投入、沉浸的对话体验；
- 支持 100+ languages and dialects；
- 这是 Qwen3 家族官方证据，不能夸大成托管 `qwen3.8-max` 的独立中文 benchmark，也不能保证具体业务 prompt 的朋友式风格。

来源：[qwen3-max](https://help.aliyun.com/zh/model-studio/model-qwen3-max)、[qwen-plus](https://help.aliyun.com/zh/model-studio/qwen-plus)、[模型调用计费](https://help.aliyun.com/zh/model-studio/model-pricing)、[文本生成价格页](https://help.aliyun.com/zh/model-studio/text-generation)

- `qwen3-max` 正式别名的功能等同快照 `qwen3-max-2026-01-23`；
- `qwen-plus-latest` 是动态别名，官方页面说明更新不会提前通知；生产若要复现应评估固定快照；
- 背景核验的北京原价表给出 `qwen-plus-latest` 分输入长度和思考模式的输入/输出价格，价格页为动态内容，采购时以控制台为准；
- 不把动态别名或历史快照自动视为永远稳定。

来源：[qwen3.8-max](https://help.aliyun.com/zh/model-studio/qwen3-8-max)

- 调用 ID：`qwen3.8-max`；
- 快照：`qwen3.8-max-0902`（别名 `qwen3.8-max-2026-09-02`）；
- 快照上下文 1M，最大输出 131,072；
- 北京原价每 1M tokens：输入 ¥12、输出 ¥36、缓存命中输入 ¥1.5、显式缓存创建 ¥15、显式缓存命中 ¥1；原价不含活动优惠；
- 动态页面和控制台价格应重新确认。

**已验证：**北京官方 Chat/Responses 接入形式；地域影响接入点和数据存储位置；Qwen 家族创作、角色扮演、多轮和 100+ 语言证据；页面列出的模型、快照、上下文与当时价格。

**未验证：**具体账号开通/配额；`qwen3.7-plus` 当前精确价格；目标 prompt 的朋友式自然度；北京网络 SLA；合同、数据处理、删除和输出安全是否满足业务。

**建议：**大陆服务端先用北京 `qwen3.7-plus` 做低延迟基线，再以 `qwen3.8-max`/快照测质量上限；生产需在动态 alias 与快照之间作有意识选择。

### 5.2 DeepSeek V4：兼容性与成本候选

来源：[DeepSeek Quick Start / Models & Pricing](https://api-docs.deepseek.com/quick_start/pricing)、[中文 Quick Start](https://api-docs.deepseek.com/zh-cn/quick_start/)

**已验证：**

- DeepSeek API 明确兼容 OpenAI/Anthropic API 格式；
- OpenAI base URL：`https://api.deepseek.com`；
- 页面列出 `deepseek-v4-flash`、`deepseek-v4-pro`，另有 `deepseek-v4-flash-vision-exp`；
- 可使用 OpenAI SDK 或兼容软件；
- 当前中文模型价格页列出 1M context、最大输出 384K、思考/非思考、JSON、Tool Calls、Responses 等能力（具体以当前页面的模型/接口矩阵为准）。

来源：[中文模型 & 价格](https://api-docs.deepseek.com/zh-cn/quick_start/pricing/)

每 1M tokens 的官方峰谷价：

| 模型 | 输入缓存命中（闲时 / 高峰） | 输入缓存未命中（闲时 / 高峰） | 输出（闲时 / 高峰） |
|---|---:|---:|---:|
| `deepseek-v4-flash` | ¥0.05 / ¥0.10 | ¥1.5 / ¥3.0 | ¥4.5 / ¥9.0 |
| `deepseek-v4-pro` | ¥0.15 / ¥0.30 | ¥4.5 / ¥9.0 | ¥13.5 / ¥27.0 |

高峰为北京时间周一至周五 09:00–12:00、14:00–18:00，其余为闲时；官方保留调整价格的权利。

来源：[DeepSeek V4/API 公告](https://api-docs.deepseek.com/zh-cn/news/news260424/)、[更新日志](https://api-docs.deepseek.com/zh-cn/updates/)

- V4-Flash、V4-Pro 已上线并可通过 OpenAI Chat Completions/Anthropic 接口访问；
- 官方公告为旧 `deepseek-chat`、`deepseek-reasoner` 给出 2026-07-24 停止使用日期；新项目应使用当前 V4 model ID；
- 生命周期与价格页面会变，应在采购前复核。

中文证据边界：

- [V3-0324 中文写作更新](https://api-docs.deepseek.com/zh-cn/news/news250325/) 明确写过中文写作、中长篇创作、多轮互动改写、翻译和中文搜索能力提升；
- 这是历史 V3 更新，不能直接当作 V4 当前朋友式对话保证；
- [DeepSeek-V4-Pro 官方模型卡](https://huggingface.co/deepseek-ai/DeepSeek-V4-Pro/blob/main/README.md)含 C-Eval、CMMLU、Chinese-SimpleQA 等中文评测列，但 benchmark 不等于自然闲聊体验。

**已验证：**官方 OpenAI/Anthropic 兼容声明、base URL、V4 model ID、能力表、生命周期公告和价格。

**未验证：**中国大陆网络可达性、大陆地域 SLA、数据存储/跨境条款、具体账号可用性、V4 朋友式中文自然度。

**建议：**把 V4-Flash 非思考模式作为低成本 A/B，V4-Pro 作为质量对照；不要新接入旧别名。

### 5.3 Moonshot / Kimi K3：中文对话候选

来源：[Kimi API Quickstart](https://platform.kimi.com/docs/api/quickstart)

**已验证：**

- 官方用 OpenAI SDK 和 Chat Completions；
- base URL：`https://api.moonshot.cn/v1`；
- model：`kimi-k3`；
- 官方 system prompt 直接写明 Kimi“更擅长中文和英文的对话”；
- 示例中出现的 key 只是官方文档占位/环境变量说明，本研究没有读取或使用任何 key。

来源：[Kimi 主要概念](https://platform.kimi.com/docs/introduction)、[API 概述](https://platform.kimi.com/docs/api/overview)

- 平台提供 Chat Completions、Responses、Messages（Anthropic 兼容）三种接口；
- `kimi-k3` 最高 1M context；
- API 无状态，多轮历史需服务端维护；
- 官方给出中文 token 的粗略说明，实际用量应以响应或 token API 为准。

来源：[Kimi 模型列表](https://platform.kimi.com/docs/models)、[Kimi K3 指南](https://platform.kimi.com/docs/guide/kimi-k3-quickstart)

- `kimi-k3` 是旗舰，原生视觉理解，1M context；
- `kimi-k2.6` 为文本/视觉、思考与非思考、对话和 Agent 模型，256K；
- `kimi-k2.7-code` 及高速版面向代码，256K；
- `kimi-k2.5` 与 `moonshot-v1` 系列于 2026-08-31 下线并返回 404；
- `kimi-k2` 系列于 2026-05-25 下线；`kimi-latest` 于 2026-01-28 下线；
- 新项目不应选择这些旧 ID。

来源：[Kimi K3 价格](https://platform.kimi.com/docs/pricing/chat-k3)、[Kimi K2.6 价格](https://platform.kimi.com/docs/pricing/chat-k26)、[Kimi K2.7 Code 价格](https://platform.kimi.com/docs/pricing/chat-k27-code)

- `kimi-k3` 每 1M：缓存命中输入 ¥2、缓存未命中输入 ¥20、输出 ¥100；窗口 1,048,576；
- `kimi-k2.6` 每 1M：缓存命中输入 ¥1.10、未命中输入 ¥6.50、输出 ¥27；窗口 262,144；
- `kimi-k2.7-code` 每 1M：缓存命中输入 ¥1.30、未命中输入 ¥6.50、输出 ¥27；高速版价格更高；
- 以上为本次读取的官方价格页数字，动态页面应复核。

来源：[Kimi 思考模型](https://platform.kimi.com/docs/guide/use-thinking-models)

- K3 始终推理；`reasoning_effort` 只有 `low` / `high` / `max`，默认 `max`；
- **没有 `xhigh`**，无法与 OpenAI `xhigh` 一比一映射；
- 朋友式闲聊应先测 `low`，评估始终推理造成的延迟和成本。

**已验证：**官方 OpenAI SDK/Chat 接入、Responses/Anthropic 兼容接口、K3 ID/上下文/价格/推理参数、中文对话明示和旧模型下线。

**未验证：**中国大陆可用性、大陆地域 SLA、数据存储/跨境条款、账号权限、具体业务自然度。

**建议：**中文自然度优先时将 K3 放入 A/B；以 `low` 为闲聊基线，不要求 `xhigh`。

### 5.4 智谱 GLM-5.3：大陆 API 兼容备选

来源：[智谱 OpenAI API 兼容](https://docs.bigmodel.cn/cn/guide/develop/openai/introduction)

**已验证：**

- 可以复用 OpenAI SDK，只改 API key 和 base URL；
- base URL：`https://open.bigmodel.cn/api/paas/v4/`；
- 官方也提醒部分场景仍存在接口差异；
- 本研究没有获取或使用任何 key。

来源：[GLM-5.3](https://docs.bigmodel.cn/cn/guide/models/text/glm-5.3)、[GLM-5.3 Markdown](https://docs.bigmodel.cn/cn/guide/models/text/glm-5.3.md)

- Chat endpoint：`https://open.bigmodel.cn/api/paas/v4/chat/completions`；
- model：`glm-5.3`；
- 仅文本模态；1M context；最大输出 128K；
- 始终开启思考；`reasoning_effort` 只有 `low` / `high` / `max`，默认 `max`；不支持 disabled，也不支持 OpenAI `xhigh`；
- 官方模型/场景描述涉及复杂任务、情感文案、角色设定和多轮语气/行为一致性；这贴合朋友式/角色化需求，但本次未找到可横向比较的中文自然度分数。

来源：[BigModel 产品价格](https://open.bigmodel.cn/pricing)

- 价格页存在，但为动态渲染；本次严格核验没有从稳定静态官方文档锁定 GLM-5.3 当前完整输入/输出价格；
- 不采用第三方价格、旧字段或动态前端残留数字；采购时以官方控制台/合同为准。

生命周期来源：[GLM-4.5](https://docs.bigmodel.cn/cn/guide/models/text/glm-4.5)、[GLM-4.5-Flash](https://docs.bigmodel.cn/cn/guide/models/free/glm-4.5-flash)

- GLM-4.5/GLM-4.5-X 页面标为即将下线；
- GLM-4.5-Flash 页面明确写 2026-01-30 下线，下线后请求自动路由到 GLM-4.7-Flash；
- 本次没有发现 GLM-5.3 固定下线日期。

**已验证：**官方兼容入口、GLM-5.3 endpoint/model ID、1M/128K、思考参数限制、中文/角色场景描述、旧模型生命周期信息。

**未验证：**当前静态价格、中国大陆地域 SLA/数据存储、账号可用性、朋友式中文自然度。

**建议：**可列入大陆 A/B，以 `low` 作为闲聊基线；新项目不要选 GLM-4.5 系列。

### 5.5 MiniMax M2-her：待补齐官方证据

本次需求指定纳入 `MiniMax M2-her`。严格按“只采信官方文档、官方 API reference、官方模型卡、官方仓库”的口径，本次没有得到足够可靠的 MiniMax 一手材料确认：

- `M2-her` 是否为 MiniMax 当前公开、准确的 model ID；
- 是否有官方服务端 API、准确 base URL、Chat Completions/Responses endpoint；
- 是否兼容 OpenAI SDK，以及兼容哪些字段/响应；
- 是否面向中国大陆、是否有大陆地域、数据留存和 SLA；
- 是否有中文、多轮、角色化对话的官方模型卡/benchmark/场景描述；
- 上下文、输出、推理参数、价格、限流和生命周期；
- 该名称是否其实是第三方转发、实验名称、内部名称或别名。

**状态：全部未验证。**不能因为搜索结果、第三方平台或某个接口接受该字符串，就把它写成 MiniMax 官方事实。

官方入口仅用于后续查找，**不构成 M2-her 已验证证据**：

- [MiniMax 官方网站](https://www.minimaxi.com/)
- [MiniMax 官方开放平台](https://platform.minimaxi.com/)

建议向 MiniMax 或转发供应商要求：官方模型列表/模型卡、准确版本/快照、API reference、地域与数据条款、OpenAI compatibility matrix、中文对话证据、当前价格、限流、SLA、生命周期与授权关系。资料补齐前不纳入生产或真实聊天 A/B。

## 6. 横向表与推荐

| 候选 | API/兼容性 | 中国大陆地域 | 中文朋友式证据 | 推理参数 | 价格/生命周期 | 建议 |
|---|---|---|---|---|---|---|
| `api.openai-next.com` + `gpt-5.6-sol` | **未验证**；无认证仅 401，schema 未找到 | 未验证 | 未验证 | 官方 Sol 有 high/xhigh；中转映射未验证 | 中转价格/条款/生命周期未验证 | 暂不生产准入 |
| OpenAI 官方 Sol | 官方 ID/参数/价格已验证 | 官方支持清单不含中国大陆，政策风险 | 官方偏专业工作，不是中文闲聊保证 | none/low/medium/high/xhigh/max | $4 / $0.40 / $20 每 1M | 能力参考，不直接作为大陆方案 |
| Qwen `qwen3.7-plus` / `qwen3.8-max` | **已验证** OpenAI-compatible Chat/Responses | **已验证**北京端点与地域/数据说明 | **已验证家族证据**：创作、角色、多轮、100+语言；具体托管模型需实测 | 按模型，Qwen3+ 常有思考/非思考 | qwen3.8-max 快照北京 ¥12/¥36，缓存 ¥1.5；latest 动态 | 大陆首选官方基线 |
| DeepSeek V4-Flash/Pro | **已验证** OpenAI/Anthropic compatible | **未验证**大陆地域 SLA | V3 历史中文写作/多轮；V4 自然度需实测 | 思考/非思考 | Flash 闲时未命中输入/输出 ¥1.5/¥4.5；Pro ¥4.5/¥13.5 | 成本/兼容性 A/B |
| Kimi `kimi-k3` | **已验证** OpenAI SDK/Chat，另有 Responses | **未验证**大陆地域 SLA | **已验证**官方示例“更擅长中文和英文的对话” | low/high/max；始终推理，无 xhigh | ¥2/¥20/¥100；旧模型已下线 | 中文自然度优先 A/B |
| GLM `glm-5.3` | **已验证** OpenAI-compatible | **未验证**大陆地域 SLA | 官方情感/角色/多轮场景；无横向自然度分数 | low/high/max；始终推理，无 xhigh | 当前静态价格未验证 | 大陆兼容备选 |
| MiniMax `M2-her` | **未验证** | **未验证** | **未验证** | **未验证** | **未验证** | 先补官方材料 |

### 推荐决策顺序

1. 暂不批准 `api.openai-next.com`；要求供应商补齐身份、授权、完整文档、可审计 schema 和合同/数据条款。
2. 中国大陆先评估百炼北京 `qwen3.7-plus`；以 `qwen3.8-max`/固定快照做质量上限。
3. 以 Kimi K3 做中文自然度对照；用 `reasoning_effort=low`，不要要求 xhigh。
4. 以 DeepSeek V4-Flash 做低成本/兼容性对照，以 V4-Pro 做质量对照。
5. 另测 GLM-5.3 的 low；不要把它或 Kimi 的参数直接当作 OpenAI high/xhigh 等价物。
6. MiniMax M2-her 只有在官方资料补齐后再进入 A/B。

## 7. 脱敏 A/B 测试设计

不调用真实模型是本研究的安全边界；后续若授权测试，使用完全脱敏、无个人隐私的固定测试集，服务端保存最小必要日志。

### 体验指标

- 口语自然：是否像朋友交流，是否过正式、说教、模板化；
- 多轮承接：是否正确理解前文偏好、情绪、指代；
- 人设稳定：10–20 轮后语气、角色、边界是否漂移；
- 中文质量：用词、语序、简繁、网络口语适度；
- 亲和但不越界：不冒充真人朋友、不操控情绪、不泄露隐私；
- 拒答体验：自然、简短、有替代建议；
- 稳定性：重复请求的一致性、长对话退化、上下文压缩行为。

### 工程指标

- 首 token、完整响应延迟；
- 429/5xx、超时、重试、流式中断；
- 输入、缓存命中、输出和 reasoning token 成本；
- Chat/Responses/stream/tool/structured output 实际字段差异；
- 动态 alias 与固定快照的漂移；
- 真实返回的 model ID、usage、finish reason 和错误码。

## 8. 风险

### 8.1 身份与授权

`api.openai-next.com` 页面显示 Vectrust，没有发现 OpenAI 官方链接或授权证明。域名含有 `openai` 字符串不能证明关联。必须要求法人主体、合同主体、OpenAI/真实模型供应商授权或转售关系、官方产品页、状态页和可审计支持渠道。

### 8.2 API 表面兼容

`/v1/models`、`/v1/chat/completions`、`/v1/responses` 路径名只是表面相似。没有成功响应不能验证模型清单、错误 schema、流式事件、工具调用、结构化输出、reasoning 参数或计费。OPTIONS、CORS、401 认证拦截和根页面都不是兼容性证明。

### 8.3 凭据与隐私

任何试用应由服务端持有最小权限、可撤销、可轮换的测试凭据；不得把真实 key/token 放到工单、聊天、浏览器前端或报告中。未完成数据处理、留存、删除、训练使用、日志访问、分包商、跨境和事故通知审查前，不上传真实朋友聊天或个人信息。

### 8.4 地区与合规

OpenAI 官方支持地区清单与中国大陆问题应单独处理；中转站不应作为规避官方政策的手段。国内厂商有北京域名也不自动等同于满足业务合规，仍需审核合同、数据分类、部署范围、审计和删除流程。

### 8.5 生命周期与模型漂移

`latest`/动态 alias 可能无预告更新；重视可复现时应锁定快照并订阅生命周期通知。不要新接入 DeepSeek 旧 `deepseek-chat`/`deepseek-reasoner`、Kimi 旧 K2/moonshot-v1/k2.5、智谱 GLM-4.5 系列。Qwen 的 latest 更新可能不提前通知，不能把动态 alias 当作固定版本。

## 9. 可直接粘贴的 ticket / 供应商回复

> 结论：目前不能可靠确认 `https://api.openai-next.com` 是 OpenAI 官方或 OpenAI-compatible 的可生产中转。我们在不携带任何认证信息的前提下对公开入口做了只读探测：`/v1/models`、`/v1/chat/completions`、`/v1/responses` 均返回 HTTP 401 `Invalid token`；`OPTIONS`/CORS 和 `/v1` 路径命名不能证明兼容。根路径、`/docs`、`/redoc` 返回的页面标题为 `Vectrust`；`/openapi.json` 和 `/swagger.json` 返回 HTTP 200 空响应，未发现可审计的公开 API reference。
>
> 请补充以下一手材料：
>
> 1. 法人主体、官方产品页、与 OpenAI/真实模型供应商的授权或转售关系；
> 2. 完整 API reference/OpenAPI schema、准确 base URL、鉴权方式和数据流说明；
> 3. Chat Completions、Responses、streaming、tool calls、structured outputs 的支持矩阵与已知差异；
> 4. 可验证的 `/v1/models` 示例、`gpt-5.6-sol` 的真实后端/版本、`high`/`xhigh` 的映射、限制和计费；
> 5. 上下文/输出上限、reasoning token 计费、价格、配额、限流、SLA、状态页、故障处理和模型下线通知；
> 6. 数据处理、留存、训练使用、跨境传输、删除、分包商、安全审计和事故通知政策；
> 7. 若 `MiniMax M2-her` 也是候选，请提供 MiniMax 官方模型列表/模型卡、准确 model ID、API reference、地域、中文/多轮/角色能力证据、价格和生命周期；不能只提供第三方平台截图或转发名称。
>
> 在供应商证据完整前，不要向工单、聊天或浏览器端提交任何真实 API key/token；不要使用真实朋友对话做验证。若目标是中国大陆生产，建议先评估官方百炼北京 Qwen、Kimi K3、DeepSeek V4-Flash/Pro 与智谱 GLM-5.3，并按中文自然度、延迟、成本、拒答、人设稳定和多轮记忆建立脱敏 A/B 测试。

## 10. 官方来源完整索引

### OpenAI

- [GPT-5.6 Sol model page](https://developers.openai.com/api/docs/models/gpt-5.6-sol)
- [Reasoning models](https://developers.openai.com/api/docs/guides/reasoning)
- [Model guidance](https://developers.openai.com/api/docs/guides/latest-model)
- [GPT-5.6 official announcement](https://openai.com/zh-Hans-CN/index/gpt-5-6/)
- [Supported countries and territories](https://help.openai.com/en/articles/5347006-supported-countries-and-regions)

### 阿里云百炼 / Qwen

- [Model Studio introduction](https://help.aliyun.com/zh/model-studio/what-is-model-studio)
- [首次调用千问 API](https://help.aliyun.com/zh/model-studio/first-api-call-to-qwen)
- [OpenAI-compatible Chat](https://help.aliyun.com/zh/model-studio/qwen-api-via-openai-chat-completions)
- [OpenAI-compatible Responses](https://help.aliyun.com/zh/model-studio/qwen-api-via-openai-responses)
- [Regions and access domains](https://help.aliyun.com/zh/model-studio/beijing-access-information)
- [Text generation model selection](https://help.aliyun.com/zh/model-studio/text-generation-model)
- [Text generation pricing](https://help.aliyun.com/zh/model-studio/text-generation)
- [Model pricing](https://help.aliyun.com/zh/model-studio/model-pricing)
- [qwen-plus](https://help.aliyun.com/zh/model-studio/qwen-plus)
- [qwen3-max](https://help.aliyun.com/zh/model-studio/model-qwen3-max)
- [qwen3.8-max](https://help.aliyun.com/zh/model-studio/qwen3-8-max)
- [Qwen3 official repository](https://github.com/QwenLM/Qwen3)

### DeepSeek

- [Official API docs index](https://api-docs.deepseek.com/)
- [Quick Start / Models & Pricing](https://api-docs.deepseek.com/quick_start/pricing)
- [中文 Quick Start](https://api-docs.deepseek.com/zh-cn/quick_start/)
- [中文模型 & 价格](https://api-docs.deepseek.com/zh-cn/quick_start/pricing/)
- [Chat Completions API](https://api-docs.deepseek.com/zh-cn/api/create-chat-completion/)
- [Models API](https://api-docs.deepseek.com/zh-cn/api/list-models/)
- [V4/API announcement](https://api-docs.deepseek.com/zh-cn/news/news260424/)
- [V3-0324 Chinese writing update](https://api-docs.deepseek.com/zh-cn/news/news250325/)
- [Change log](https://api-docs.deepseek.com/zh-cn/updates/)
- [DeepSeek V4 preview news](https://www.deepseek.com/news/v4-preview/)
- [DeepSeek official model card](https://huggingface.co/deepseek-ai/DeepSeek-V4-Pro/blob/main/README.md)

### Moonshot / Kimi

- [Kimi API introduction](https://platform.kimi.com/docs/introduction)
- [Kimi API quickstart](https://platform.kimi.com/docs/api/quickstart)
- [Kimi API overview](https://platform.kimi.com/docs/api/overview)
- [OpenAI compatibility migration](https://platform.kimi.com/docs/guide/migrating-from-openai-to-kimi)
- [Kimi model list](https://platform.kimi.com/docs/models)
- [Kimi K3 guide](https://platform.kimi.com/docs/guide/kimi-k3-quickstart)
- [Kimi multi-turn conversations](https://platform.kimi.com/docs/guide/engage-in-multi-turn-conversations-using-kimi-api)
- [Kimi thinking models](https://platform.kimi.com/docs/guide/use-thinking-models)
- [Kimi pricing index](https://platform.kimi.com/docs/pricing/chat)
- [Kimi K3 pricing](https://platform.kimi.com/docs/pricing/chat-k3)
- [Kimi K3 pricing Markdown](https://platform.kimi.com/docs/pricing/chat-k3.md)
- [Kimi K2.6 pricing](https://platform.kimi.com/docs/pricing/chat-k26)
- [Kimi K2.7 Code pricing](https://platform.kimi.com/docs/pricing/chat-k27-code)
- [kimi-latest lifecycle](https://platform.kimi.com/docs/changelog/changelog/kimi-latest)

### 智谱

- [OpenAI API compatibility](https://docs.bigmodel.cn/cn/guide/develop/openai/introduction)
- [Model migration](https://docs.bigmodel.cn/cn/guide/platform/model-migration)
- [GLM-5.3](https://docs.bigmodel.cn/cn/guide/models/text/glm-5.3)
- [GLM-5.3 Markdown](https://docs.bigmodel.cn/cn/guide/models/text/glm-5.3.md)
- [GLM-5](https://docs.bigmodel.cn/cn/guide/models/text/glm-5)
- [GLM-4.5](https://docs.bigmodel.cn/cn/guide/models/text/glm-4.5)
- [GLM-4.5-Flash lifecycle](https://docs.bigmodel.cn/cn/guide/models/free/glm-4.5-flash)
- [BigModel pricing](https://open.bigmodel.cn/pricing)

### MiniMax（入口，不是 M2-her 证据）

- [MiniMax official website](https://www.minimaxi.com/)
- [MiniMax official platform](https://platform.minimaxi.com/)

## 11. 研究限制

- 官方页面经常动态渲染，价格、模型列表、alias、上下文和下线日期必须在采购前复核。
- 没有调用模型 API，因此无法声称任何候选已经通过朋友式中文自然度测试；“中文自然”均按官方明示能力/场景或 benchmark 证据标注，并保留实测未验证边界。
- 无认证 HTTP 探测无法验证成功请求 schema；下一步若要端到端测试，应使用脱敏数据、服务端最小权限、可撤销凭据，并先取得供应商文档/合同确认。
- 第三方博客、媒体、论坛、聚合模型页和搜索摘要没有作为事实来源；所有事实引用均指向官方文档、官方 API reference、官方模型卡或官方仓库。
