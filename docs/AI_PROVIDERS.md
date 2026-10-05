# User-connected AI providers

Pokfu can send the Moodle Tutor prompt and the locally prepared Moodle context
to one provider chosen by the user. Pokfu does not proxy requests through a
Pokfu server and does not contain a shared API key.

## In the app

1. Open **Settings → AI Providers**.
2. Choose **Qwen**, **GLM**, **Doubao**, **DeepSeek**, or **OpenRouter**.
3. Create a provider API key using the provider's console.
4. Paste the key into Pokfu. The endpoint and model are prefilled, but both
   can be changed for a regional endpoint, a workspace URL, or a different
   model.
5. Tap **Save connection**, then **Test connection**.
6. Return to **AI Providers** and select the connected provider as **Active**.

The API key is stored in the iOS Keychain. Endpoint/model settings are stored
locally in UserDefaults. Disconnecting a provider deletes its key from the
Keychain. With no active provider, the tutor falls back to Apple Intelligence
when available and then the system share sheet.

## Default endpoints

| Provider | Default base URL | Model field |
| --- | --- | --- |
| Qwen | `https://dashscope-intl.aliyuncs.com/compatible-mode/v1` | A DashScope model such as `qwen-plus` |
| GLM | `https://open.bigmodel.cn/api/paas/v4` | A model enabled in the Zhipu console |
| Doubao | `https://ark.cn-beijing.volces.com/api/v3` | The Ark endpoint/model ID shown in the console |
| DeepSeek | `https://api.deepseek.com` | For example `deepseek-chat` |
| OpenRouter | `https://openrouter.ai/api/v1` | Any current OpenRouter model ID, including a `:free` model |

Pokfu appends `/chat/completions` to a base URL. A full
`.../chat/completions` URL is also accepted. Only HTTPS endpoints are
accepted.

## Provider notes

- **Qwen:** create the key in the same region as the endpoint. Alibaba Cloud
  exposes a **Free Quota Only** safety option; enable it if you do not want
  requests to continue into paid quota.
- **GLM:** use the model name displayed by the Zhipu account. Promotional
  trial quotas are account- and time-dependent.
- **Doubao:** Ark commonly identifies a deployed endpoint with an endpoint ID;
  copy that exact value into the model field instead of assuming the display
  name is callable.
- **DeepSeek:** this is not treated as a permanently free API. Configure
  account spending limits before using it.
- **OpenRouter:** the free-model list and limits change. Copy a currently
  available model ID from OpenRouter, usually one ending in `:free`.

## Official setup links

- [Qwen OpenAI-compatible API](https://www.alibabacloud.com/help/en/model-studio/compatibility-of-openai-with-dashscope)
- [Qwen free quota](https://www.alibabacloud.com/help/en/model-studio/new-free-quota)
- [GLM console](https://open.bigmodel.cn/console)
- [Doubao/Volcengine Ark](https://www.volcengine.com/docs/82379/1399008)
- [DeepSeek API pricing and limits](https://api-docs.deepseek.com/quick_start/pricing/)
- [OpenRouter pricing and free plan](https://openrouter.ai/pricing/)

## Privacy boundary

When the tutor is used with a connected provider, Pokfu sends the student's
question, ranked Moodle search results, and extracted text from selected
course files. It does not send the Moodle password or Moodle API tokens.
Students should check the selected provider's retention and data-use policy
before sending sensitive course material.
