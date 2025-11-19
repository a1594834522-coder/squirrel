-- ai_completion.lua
-- AI 智能补全插件
-- 阶段二：集成真实 AI API

local M = {}

-- ==================== JSON 工具函数 ====================

-- 简单的 JSON 编码（仅支持字符串和表）
local function json_encode(obj)
    local function escape_str(s)
        s = string.gsub(s, '\\', '\\\\')
        s = string.gsub(s, '"', '\\"')
        s = string.gsub(s, '\n', '\\n')
        s = string.gsub(s, '\r', '\\r')
        s = string.gsub(s, '\t', '\\t')
        return s
    end

    local function encode_value(v)
        local t = type(v)
        if t == "string" then
            return '"' .. escape_str(v) .. '"'
        elseif t == "number" or t == "boolean" then
            return tostring(v)
        elseif t == "table" then
            local is_array = true
            local max_index = 0
            for k, _ in pairs(v) do
                if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
                    is_array = false
                    break
                end
                max_index = math.max(max_index, k)
            end

            if is_array and max_index == #v then
                -- 数组
                local parts = {}
                for i, item in ipairs(v) do
                    table.insert(parts, encode_value(item))
                end
                return "[" .. table.concat(parts, ",") .. "]"
            else
                -- 对象
                local parts = {}
                for k, val in pairs(v) do
                    table.insert(parts, '"' .. escape_str(tostring(k)) .. '":' .. encode_value(val))
                end
                return "{" .. table.concat(parts, ",") .. "}"
            end
        else
            return "null"
        end
    end

    return encode_value(obj)
end

-- 简单的 JSON 解析（仅支持基本结构）
local function json_decode(str)
    -- 移除多余空白
    str = string.gsub(str, "^%s+", "")
    str = string.gsub(str, "%s+$", "")

    -- 简单的字符串提取
    local function extract_string(s, pos)
        local start_pos = pos + 1
        local end_pos = start_pos
        while end_pos <= #s do
            local c = string.sub(s, end_pos, end_pos)
            if c == '"' and string.sub(s, end_pos - 1, end_pos - 1) ~= '\\' then
                return string.sub(s, start_pos, end_pos - 1), end_pos + 1
            end
            end_pos = end_pos + 1
        end
        return nil, pos
    end

    -- 提取对象中的字段（非常简化的实现）
    local function extract_field(s, field_name)
        local pattern = '"' .. field_name .. '"%s*:%s*"([^"]*)"'
        local value = string.match(s, pattern)
        if value then
            -- 处理转义字符
            value = string.gsub(value, '\\n', '\n')
            value = string.gsub(value, '\\r', '\r')
            value = string.gsub(value, '\\t', '\t')
            value = string.gsub(value, '\\"', '"')
            value = string.gsub(value, '\\\\', '\\')
            return value
        end
        return nil
    end

    return {
        extract_field = extract_field
    }
end

-- 全局配置（后续从 yaml 读取）
local config = {
    enabled = true,
    trigger_key = "Control+space",  -- 改为 Control+space，Tab 键已被占用
    base_url = "https://api.openai.com/v1/chat/completions",
    api_key = "",
    model_name = "gpt-3.5-turbo",
    context_window_minutes = 5,
    max_candidates = 3,
    max_tokens = 200
}

-- 输入历史缓冲区（用于保存最近的输入）
local input_history = {}
local MAX_HISTORY_SIZE = 100

local function should_normalize_base_url(url)
    if not url then
        return false
    end
    local host = url:match("^https?://([^/]+)")
    if not host then
        return false
    end
    host = host:lower()
    return host == "api.openai.com" or host == "api.x.ai"
end

local function join_paths(base, suffix)
    local has_slash_base = base:sub(-1) == "/"
    local has_slash_suffix = suffix:sub(1, 1) == "/"
    if has_slash_base and has_slash_suffix then
        return base .. suffix:sub(2)
    elseif not has_slash_base and not has_slash_suffix then
        return base .. "/" .. suffix
    end
    return base .. suffix
end

local function normalize_base_url(url)
    if not url or url == "" then
        return url
    end
    local trimmed = url:gsub("^%s+", ""):gsub("%s+$", "")
    local lower = trimmed:lower()
    if lower:find("/chat/completions", 1, true) then
        return trimmed
    end
    if not should_normalize_base_url(trimmed) then
        return trimmed
    end
    if lower:match("/chat/?$") then
        return join_paths(trimmed, "/completions")
    end
    if lower:match("/v1/?$") then
        return join_paths(trimmed, "/chat/completions")
    end
    return join_paths(trimmed, "/v1/chat/completions")
end

config.base_url = normalize_base_url(config.base_url)

-- 添加输入到历史记录
local function add_to_history(text)
    local timestamp = os.time()
    table.insert(input_history, {
        text = text,
        time = timestamp
    })

    -- 保持历史记录在合理大小
    while #input_history > MAX_HISTORY_SIZE do
        table.remove(input_history, 1)
    end
end

-- 获取最近 N 分钟的输入历史
local function get_recent_context(minutes)
    local now = os.time()
    local cutoff = now - (minutes * 60)
    local context_parts = {}

    for i = #input_history, 1, -1 do
        local entry = input_history[i]
        if entry.time >= cutoff then
            table.insert(context_parts, 1, entry.text)
        else
            break
        end
    end

    return table.concat(context_parts, " ")
end

-- ==================== AI API 调用 ====================
local function is_gemini_model()
    local base = string.lower(config.base_url or "")
    local model = string.lower(config.model_name or "")
    if string.find(base, "generativelanguage.googleapis.com", 1, true) ~= nil then
        return true
    end
    if string.find(base, ":generatecontent", 1, true) ~= nil then
        return true
    end
    return string.find(model, "gemini", 1, true) ~= nil
end

local function resolve_gemini_endpoint()
    local model = config.model_name or "gemini-2.5-flash"
    return "https://generativelanguage.googleapis.com/v1beta/models/" .. model .. ":generateContent"
end

local function extract_gemini_text(response)
    local start_idx = string.find(response or "", '"candidates"')
    if not start_idx then
        return nil
    end
    local texts = {}
    for text in string.gmatch(string.sub(response, start_idx), '"text"%s*:%s*"(.-)"') do
        local cleaned = text
        cleaned = string.gsub(cleaned, '\\n', '\n')
        cleaned = string.gsub(cleaned, '\\r', '\r')
        cleaned = string.gsub(cleaned, '\\t', '\t')
        cleaned = string.gsub(cleaned, '\\"', '"')
        cleaned = string.gsub(cleaned, '\\\\', '\\')
        cleaned = string.gsub(cleaned, "^%s+", "")
        cleaned = string.gsub(cleaned, "%s+$", "")
        if cleaned ~= "" then
            table.insert(texts, cleaned)
        end
    end
    if #texts == 0 then
        return nil
    end
    return table.concat(texts, "\n")
end

-- 使用 curl 调用 AI API
local function call_ai_api(context, current_input)
    -- 检查 API Key
    if not config.api_key or config.api_key == "" then
        return nil, "API Key 未配置"
    end

    -- 构建 prompt
    local prompt = "根据以下上下文，补全用户当前的输入。只返回补全结果，每个结果一行，最多" .. config.max_candidates .. "个结果。\n\n"

    if context and context ~= "" then
        prompt = prompt .. "上下文：" .. context .. "\n\n"
    end

    prompt = prompt .. "当前输入：" .. current_input .. "\n\n补全："

    local url = config.base_url
    local header_parts
    local payload

    if is_gemini_model() then
        payload = {
            contents = {
                {
                    role = "user",
                    parts = {
                        { text = prompt }
                    }
                }
            },
            generationConfig = {
                maxOutputTokens = config.max_tokens or 200,
                temperature = 0.7
            }
        }
        url = resolve_gemini_endpoint()
        header_parts = {
            '-H "Content-Type: application/json"',
            string.format('-H "x-goog-api-key: %s"', config.api_key)
        }
    else
        payload = {
            model = config.model_name,
            messages = {
                {
                    role = "system",
                    content = "你是一个智能输入法助手。根据用户的输入历史和当前输入，提供简洁的补全建议。每个建议一行，不要编号，不要额外解释。"
                },
                {
                    role = "user",
                    content = prompt
                }
            },
            max_tokens = config.max_tokens or 200,
            temperature = 0.7,
            n = 1
        }
        header_parts = {
            '-H "Content-Type: application/json"',
            string.format('-H "Authorization: Bearer %s"', config.api_key)
        }
    end

    local json_payload = json_encode(payload)

    -- 创建临时文件保存 payload
    local temp_file = os.tmpname()
    local f = io.open(temp_file, "w")
    if not f then
        return nil, "无法创建临时文件"
    end
    f:write(json_payload)
    f:close()

    -- 使用 curl 发送请求
    local curl_cmd = string.format(
        'curl -s -m 5 -X POST "%s" %s -d @%s',
        url,
        table.concat(header_parts, " "),
        temp_file
    )

    local handle = io.popen(curl_cmd)
    if not handle then
        os.remove(temp_file)
        return nil, "无法执行 curl 命令"
    end

    local response = handle:read("*a")
    handle:close()
    os.remove(temp_file)

    -- 检查响应
    if not response or response == "" then
        return nil, "API 无响应"
    end

    local content
    if is_gemini_model() then
        content = extract_gemini_text(response)
        if not content then
            return nil, "API 返回内容为空"
        end
    else
        local decoder = json_decode(response)
        content = decoder.extract_field(response, "content")
        if not content then
            local error_msg = decoder.extract_field(response, "error") or
                             decoder.extract_field(response, "message") or
                             "API 返回格式错误"
            return nil, error_msg
        end
    end

    -- 将内容分割成多个候选项
    local candidates = {}
    for line in string.gmatch(content, "[^\r\n]+") do
        line = string.gsub(line, "^%s+", "")  -- 去除前导空白
        line = string.gsub(line, "%s+$", "")  -- 去除尾随空白
        line = string.gsub(line, "^%d+[%.、]%s*", "")  -- 去除编号

        if line ~= "" and #line > 0 then
            table.insert(candidates, line)
            if #candidates >= config.max_candidates then
                break
            end
        end
    end

    return candidates, nil
end

-- Processor: 捕获快捷键
function M.processor(key, env)
    -- 如果全局定义了 ai_completion_processor（在 rime.lua 中），则直接委托给它，
    -- 以便复用统一的 AI 逻辑（包括 Tab 联想和 Command 问答）。
    if _G.ai_completion_processor then
        return _G.ai_completion_processor(key, env)
    end

    -- 回退到本地实现（早期版本）
    local engine = env.engine
    local context = engine.context
    if key.repr == config.trigger_key then
        local input = context.input
        if input and input ~= "" then
            context:set_property("ai_completion_trigger", "true")
            return 2
        end
    end
    return 2
end

-- Translator: 生成 AI 补全候选项
function M.translator(input, seg, env)
    -- 如果全局定义了 ai_completion_translator（在 rime.lua 中），则直接委托给它，
    -- 使用统一的候选生成与标注逻辑。
    if _G.ai_completion_translator then
        return _G.ai_completion_translator(input, seg, env)
    end

    local context = env.engine.context

    -- 检查是否触发了 AI 补全
    local trigger = context:get_property("ai_completion_trigger")
    if trigger ~= "true" then
        return
    end

    -- 清除触发标记
    context:set_property("ai_completion_trigger", "")

    -- 检查是否启用
    if not config.enabled then
        return
    end

    -- 获取最近的输入历史作为上下文
    local recent_context = get_recent_context(config.context_window_minutes)

    -- 调用 AI API
    local candidates, error_msg = call_ai_api(recent_context, input)

    if error_msg then
        -- API 调用失败时静默返回，不插入带有特殊标记的候选，避免打扰用户
        return
    end

    if not candidates or #candidates == 0 then
        -- 没有返回候选项，静默失败
        return
    end

    -- 生成候选项（不添加任何 AI 标记，使其外观与普通候选一致）
    for i, text in ipairs(candidates) do
        local cand = Candidate("ai_completion", seg.start, seg._end, text, "")
        cand.quality = 1000 - i  -- 高优先级，第一个候选项质量最高
        yield(cand)
    end
end

-- Filter: 过滤和排序候选项（可选）
function M.filter(input, env)
    -- 暂时不需要过滤
    for cand in input:iter() do
        yield(cand)
    end
end

-- 初始化函数
function M.init(env)
    -- 从当前 schema 的配置读取设置（包括前端写入的 ai_pinyin.custom.yaml）
    local conf = env.engine.schema.config

    if conf then
        local enabled = conf:get_bool("ai_completion/enabled")
        if enabled ~= nil then
            config.enabled = enabled
        end

        local trigger_key = conf:get_string("ai_completion/trigger_key")
        if trigger_key and trigger_key ~= "" then
            config.trigger_key = trigger_key
        end

        local base_url = conf:get_string("ai_completion/base_url")
        if base_url and base_url ~= "" then
            config.base_url = normalize_base_url(base_url)
        end

        local api_key = conf:get_string("ai_completion/api_key")
        if api_key and api_key ~= "" then
            config.api_key = api_key
        end

        local model_name = conf:get_string("ai_completion/model_name")
        if model_name and model_name ~= "" then
            config.model_name = model_name
        end

        local context_window = conf:get_int("ai_completion/context_window_minutes")
        if context_window and context_window > 0 then
            config.context_window_minutes = context_window
        end

        local max_tokens = conf:get_int("ai_completion/max_tokens")
        if max_tokens and max_tokens > 0 then
            config.max_tokens = max_tokens
        end
    end

    -- 将读取到的配置同步到全局 ai_config / context_window_minutes（由 rime.lua 使用）
    if _G.ai_config then
        _G.ai_config.enabled = config.enabled
        if config.base_url and config.base_url ~= "" then
            _G.ai_config.base_url = config.base_url
        end
        if config.api_key and config.api_key ~= "" then
            _G.ai_config.api_key = config.api_key
        end
        if config.model_name and config.model_name ~= "" then
            _G.ai_config.model_name = config.model_name
        end
        if config.max_candidates then
            _G.ai_config.max_candidates = config.max_candidates
        end
        if config.max_tokens then
            _G.ai_config.max_tokens = config.max_tokens
        end
    end
    if _G.context_window_minutes and config.context_window_minutes then
        _G.context_window_minutes = config.context_window_minutes
    end

    -- 注册提交监听器（用于记录输入历史）
    local function on_commit(ctx)
        local commit_text = ctx:get_commit_text()
        if commit_text and commit_text ~= "" then
            add_to_history(commit_text)
        end
    end

    -- 连接提交信号
    env.commit_connection = env.engine.context.commit_notifier:connect(on_commit)
end

-- 清理函数
function M.fini(env)
    if env.commit_connection then
        env.commit_connection:disconnect()
    end
end

return M
