-- rime.lua
-- AI 智能补全插件

-- ============================================================================
-- 全局状态管理
-- ============================================================================

-- 输入历史记录（用于 AI 上下文）
input_history = input_history or {}
context_window_minutes = context_window_minutes or 10  -- 可由 ai_pinyin.custom.yaml 覆盖

-- AI 候选缓存（按 Tab 时触发 AI，缓存结果）
local ai_candidates_cache = {
    input = nil,
    candidates = nil,
    timestamp = 0
}

-- Command 键问答状态管理
local qa_state = {
    mode = "none",        -- "none" | "question" | "answer"
    question = nil,       -- 保存生成的问题
    last_input = nil,     -- 保存触发问题的拼音
    timestamp = 0
}

ai_config = ai_config or {
    enabled = true,
    -- 默认使用 OpenAI 兼容接口，实际值由前端配置写入 ai_pinyin.custom.yaml 后由 ai_completion.lua 同步覆盖
    base_url = "https://api.openai.com/v1/chat/completions",
    api_key = "",
    model_name = "gpt-4o-mini",
    -- Grok 配置（用于问题回答）
    grok_base_url = "https://api.x.ai/v1/chat/completions",
    grok_api_key = "YOUR_GROK_API_KEY_HERE",
    grok_model_name = "grok-4-fast",
    max_candidates = 3,
    system_prompt = [[你是一个中文输入法的句子级联想与补全助手，主要目标是帮助用户把「正在输入的这句话」自然地补完，而不是随意联想别的话题。

使用场景：
- 用户正在电脑或手机上打字，使用拼音输入法。
- 你只负责根据用户的历史输入和当前拼音，给出若干「当前这句话的续写」候选。

你会得到：
1. 最近 10 分钟内用户已经输入的中文文本（上下文）
2. 当前正在输入的拼音串（例如 nihao、wojiao 等）

你的任务：
- 正确理解该拼音在当前上下文中的最常见、最合理含义，不要故意玩梗或生造冷僻解释。
- 判断用户此刻最可能想说完的一整句话或短句，而不是换一个话题。
- 每个联想结果都应当是一个可以直接上屏的完整短句，尽量包含该词语或其自然变体，并保持原本说话的语气和意图。
- 续写要紧贴上下文，优先补全当前句子剩余部分，而不是开启新的句子或话题。
- 严格避免跑题，不要引入与上下文和当前拼音无直接关系的新话题或长篇说明。

输出格式：
- 严格返回 3 行文本，每行一个候选。
- 每行只包含候选内容本身，不要任何说明性文字。
- 禁止输出任何形式的序号或项目符号（例如 "1."、"①"、"- "、"(1)」、「【】」等），也不要使用类似「候选1:」「建议：」「标题是：」「网址是：」之类的前缀。
- 内容要自然、接近真实用户语气，适合直接作为输入法候选上屏。
- 在满足上述条件的前提下，每个候选建议控制在约 8～25 个汉字。]]
}

-- ============================================================================
-- 工具函数
-- ============================================================================

-- 获取当前时间戳（秒）
local function get_timestamp()
    return os.time()
end

-- 清理过期的历史记录
local function cleanup_history()
    local now = get_timestamp()
    local cutoff = now - (context_window_minutes * 60)

    local new_history = {}
    for _, entry in ipairs(input_history) do
        if entry.timestamp >= cutoff then
            table.insert(new_history, entry)
        end
    end
    input_history = new_history
end

-- 添加到历史记录
local function add_to_history(text)
    if text and text ~= "" then
        cleanup_history()
        table.insert(input_history, {
            text = text,
            timestamp = get_timestamp()
        })

        -- 限制历史记录数量（最多100条）
        if #input_history > 100 then
            table.remove(input_history, 1)
        end
    end
end

-- 获取历史上下文字符串
local function get_history_context()
    cleanup_history()

    local context_parts = {}
    for _, entry in ipairs(input_history) do
        table.insert(context_parts, entry.text)
    end

    return table.concat(context_parts, " ")
end

-- 从 ai_pinyin.custom.yaml 读取 AI 配置（前端界面生成）
local function load_ai_config_from_file()
    local home = os.getenv("HOME") or ""
    if home == "" then
        return
    end
    local path = home .. "/Library/Rime/ai_pinyin.custom.yaml"
    local f = io.open(path, "r")
    if not f then
        return
    end
    local content = f:read("*a")
    f:close()

    local function extract(key)
        -- 同时兼容有引号和无引号两种写法，并忽略前导空白
        local value = content:match(key .. '%s*:%s*"(.-)"')
        if not value then
            value = content:match(key .. '%s*:%s*([^%c#"]+)')
        end
        if value then
            value = value:gsub("%s+$", "")
        end
        return value
    end

    local base_url = extract("ai_completion/base_url")
    if base_url and base_url ~= "" then
        ai_config.base_url = base_url
    end

    local api_key = extract("ai_completion/api_key")
    if api_key and api_key ~= "" then
        ai_config.api_key = api_key
    end

    local model_name = extract("ai_completion/model_name")
    if model_name and model_name ~= "" then
        ai_config.model_name = model_name
    end
end

load_ai_config_from_file()

-- ============================================================================
-- 请求构建与 Provider 检测
-- ============================================================================

local function escape_json(str)
    if not str then
        return ""
    end
    str = str:gsub("\\", "\\\\")
    str = str:gsub('"', '\\"')
    str = str:gsub("\n", "\\n")
    str = str:gsub("\r", "\\r")
    str = str:gsub("\t", "\\t")
    return str
end

local function is_grok_provider()
    local base = (ai_config.base_url or ""):lower()
    local model = (ai_config.model_name or ""):lower()
    return base:find("api.x.ai", 1, true) ~= nil
        or base:find("/responses", 1, true) ~= nil
        or model:find("grok", 1, true) ~= nil
end

local function load_tools_config()
    local home = os.getenv("HOME") or ""
    if home == "" then
        return nil
    end
    local path = home .. "/Library/Rime/ai_pinyin.tools.json"
    local f = io.open(path, "r")
    if not f then
        return nil
    end
    local content = f:read("*a")
    f:close()
    if not content or content:gsub("%s+", "") == "" then
        return nil
    end

    local trimmed = content:match("^%s*(.-)%s*$") or content
    -- 支持三种形式：
    -- 1) 纯数组: [ {...} ]
    -- 2) 带键对象: { "tools": [ ... ] }
    -- 3) 键值片段: "tools": [ ... ]
    if trimmed:sub(1, 1) == "[" then
        return trimmed
    end
    local array_part = trimmed:match('"tools"%s*:%s*(%b[])')
    if array_part then
        return array_part
    end
    local array_in_object = trimmed:match('{%s*"tools"%s*:%s*(%b[])%s*}')
    if array_in_object then
        return array_in_object
    end
    return nil
end

-- enable_tools 仅在「第二次 Command 回答问题」时为 true
local function build_request_body(system_prompt, user_prompt, temperature, max_tokens, enable_tools)
    if is_grok_provider() then
        local tools_part = ""
        if enable_tools then
            local tools_json = load_tools_config()
            if tools_json and tools_json ~= "" then
                tools_part = string.format(', "tools": %s', tools_json)
            end
        end
        return string.format([[{
            "model": "%s",
            "input": [
                {"role": "system", "content": "%s"},
                {"role": "user", "content": "%s"}
            ],
            "temperature": %.2f,
            "max_output_tokens": %d,
            "max_tokens": %d%s
        }]],
            ai_config.model_name,
            escape_json(system_prompt),
            escape_json(user_prompt),
            temperature or 0,
            max_tokens or 200,
            max_tokens or 200,
            tools_part
        )
    end

    return string.format([[{
        "model": "%s",
        "messages": [
            {"role": "system", "content": "%s"},
            {"role": "user", "content": "%s"}
        ],
        "temperature": %.2f,
        "max_tokens": %d
    }]],
        ai_config.model_name,
        escape_json(system_prompt),
        escape_json(user_prompt),
        temperature or 0,
        max_tokens or 200
    )
end

-- 写入调试日志
local function debug_log(message)
    local log_file = os.getenv("HOME") .. "/Library/Rime/ai_debug.log"
    local f = io.open(log_file, "a")
    if f then
        f:write(os.date("%Y-%m-%d %H:%M:%S") .. " - " .. message .. "\n")
        f:close()
    end
end

-- HTTP POST 请求（使用临时脚本文件）
local function http_post(url, headers, body)
    local home = os.getenv("HOME")
    local script_file = home .. "/Library/Rime/curl_request.sh"
    local output_file = home .. "/Library/Rime/curl_output.txt"

    -- 构建 curl 命令（添加超时参数避免阻塞）
    local cmd = string.format('curl -s --connect-timeout 10 --max-time 30 -X POST "%s"', url)

    -- 添加 headers
    for key, value in pairs(headers) do
        cmd = cmd .. string.format(' -H "%s: %s"', key, value)
    end

    -- 添加 body - 保存到临时文件
    local body_file = home .. "/Library/Rime/curl_body.json"
    local f = io.open(body_file, "w")
    if not f then
        debug_log("ERROR: Cannot create body file")
        return nil, "Cannot create body file"
    end
    f:write(body)
    f:close()

    cmd = cmd .. string.format(' -d @"%s" > "%s" 2>&1', body_file, output_file)

    -- 写入脚本文件
    local script = io.open(script_file, "w")
    if not script then
        debug_log("ERROR: Cannot create script file")
        return nil, "Cannot create script file"
    end
    script:write("#!/bin/bash\n")
    script:write(cmd .. "\n")
    script:close()

    -- 设置执行权限并执行
    os.execute(string.format('chmod +x "%s"', script_file))

    debug_log("Executing: " .. cmd)
    local exit_code = os.execute(string.format('"%s"', script_file))
    debug_log("Exit code: " .. tostring(exit_code))

    -- 读取输出
    local output = io.open(output_file, "r")
    if not output then
        debug_log("ERROR: Cannot read output file")
        return nil, "Cannot read output file"
    end

    local result = output:read("*a")
    output:close()

    -- 记录响应
    debug_log("Response: " .. (result or "nil"))

    -- 清理临时文件
    os.remove(script_file)
    os.remove(body_file)
    os.remove(output_file)

    return result, nil
end

-- 解析 JSON 响应（改进的实现）
local function parse_json_response(json_str)
    if not json_str or json_str == "" then
        debug_log("ERROR: Empty JSON response")
        return nil
    end

    -- 记录原始响应用于调试
    debug_log("Parsing JSON, length: " .. #json_str)

    -- Grok /responses: 优先解析 output_text / content 数组
    local outputs = {}
    -- 情形 1：{"type":"output_text","text":"..."}
    for text in json_str:gmatch('"type"%s*:%s*"output_text"%s*,%s*"text"%s*:%s*"(.-)"') do
        table.insert(outputs, text)
    end
    -- 情形 2：{"text":"...","type":"output_text"}
    if #outputs == 0 then
        for text in json_str:gmatch('"text"%s*:%s*"(.-)"%s*,%s*"type"%s*:%s*"output_text"') do
            table.insert(outputs, text)
        end
    end
    if #outputs == 0 then
        local output_section = json_str:match('"output_text"%s*:%s*%[(.-)%]')
        if output_section then
            for text in output_section:gmatch('"(.-)"') do
                table.insert(outputs, text)
            end
        end
    end
    if #outputs == 0 then
        local content_section = json_str:match('"content"%s*:%s*%[(.-)%]')
        if content_section then
            for text in content_section:gmatch('"text"%s*:%s*"(.-)"') do
                table.insert(outputs, text)
            end
        end
    end
    if #outputs > 0 then
        local combined = table.concat(outputs, "\n")
        combined = combined:gsub('\\n', '\n'):gsub('\\r', '\r'):gsub('\\t', '\t'):gsub('\\"', '"'):gsub('\\\\', '\\')
        combined = combined:gsub("^%s*", ""):gsub("%s*$", "")
        debug_log("Parsed grok content length: " .. #combined)
        if combined ~= "" then
            return combined
        end
    end

    -- 尝试多种方式提取 content
    -- 方法1: 匹配带转义的 content
    local content = json_str:match('"content"%s*:%s*"(.-)"[,%s]*"role"')

    if not content then
        -- 方法2: 更宽松的匹配
        content = json_str:match('"content"%s*:%s*"(.-)"')
    end

    if not content then
        -- 方法3: 处理可能的多行内容
        content = json_str:match('"content"%s*:%s*"(.+)"[,%}]')
    end

    if content then
        -- 反转义常见的 JSON 转义字符
        content = content:gsub('\\n', '\n')
        content = content:gsub('\\r', '\r')
        content = content:gsub('\\t', '\t')
        content = content:gsub('\\"', '"')
        content = content:gsub('\\\\', '\\')
        content = content:gsub('\\/', '/')

        -- 去除首尾空白
        content = content:gsub("^%s*", ""):gsub("%s*$", "")

        debug_log("Parsed content length: " .. #content)
        return content
    end

    debug_log("ERROR: Failed to parse content from JSON")
    return nil
end

-- 生成贴本意的查询/请求补全（用于第一次 Command），只参考当前拼音和候选列表（不使用历史上下文）
local function generate_question(pinyin, raw_candidates)
    debug_log("=== Generating Query Completions ===")
    debug_log("Pinyin: " .. pinyin)
    debug_log("Raw candidate count: " .. tostring(raw_candidates and #raw_candidates or 0))

    -- 构造候选列表文本，帮助模型理解当前 IME 给出的结果
    local candidates_text = ""
    if raw_candidates and #raw_candidates > 0 then
        local parts = {}
        local max_show = math.min(#raw_candidates, 5)
        for i = 1, max_show do
            debug_log(string.format("Raw candidate[%d]: %s", i, tostring(raw_candidates[i])))
            table.insert(parts, string.format("%d. %s", i, raw_candidates[i]))
        end
        candidates_text = table.concat(parts, "\n")
    end

    local system_prompt = [[你是一个中文输入法中的「意图补全助手」，根据用户正在输入的拼音和当前候选列表，给出几个紧贴本意的中文句子，用于作为真正要提交给问答或搜索系统的查询/请求。

使用场景：
- 用户输入一段拼音，输入法已经给出若干候选，你可以看到这些候选。
- 你的任务是基于拼音和候选，推断用户最真实的意图，并把它补全成自然、简短、完整的中文句子。
- 注意：当前候选只是输入法给出的「猜测」，可能包含错别字、错分词或错误音译（例如把 youtubeshipin 错写成「有图比尔视频」），不能完全当成真实意图。

处理原则：
1. 优先相信「拼音串本身」所表达的含义，再把候选当作参考快照，而不是权威答案。
2. 如果候选和拼音高度一致，就可以复用候选中的表达；如果候选里有明显别字/错分词/怪异音译，而拼音清楚指向另一个更自然的词或短语（尤其是英文串，如 youtube、openai、chatgpt 等），请按拼音进行纠正，然后再据此生成句子。
3. 当拼音和候选明显是在询问信息本身（例如包含“网址/链接/官网/价格/作者/名字/时间/地点”等），优先使用“是多少/是什么/是谁/在哪里/什么时候”等直接、基础的问法，避免“是什么样的”“怎么看待……”这类评价性或元问题。
4. 当拼音更像是一个请求或祈使句（例如“讲个笑话”“写一条祝福语”），保持这一意图，生成自然的请求句或简短说明句，不要把它改写成别的问题。
5. 严格保持语义等价或非常接近：不要改变说话对象、时态和核心需求，不要加入用户没有提到的新条件或新任务。
6. 句子要简洁，适合作为搜索或问答的查询，通常控制在 8～25 个汉字之内。

示例（纠正明显错误候选）：
- 拼音：bangwoxieyigeyoutubeshipinbiaoti
- 候选：帮我写一个有图比尔视频标题
你的处理：识别「youtubeshipin」应该是 “YouTube 视频”，把「有图比尔视频」纠正为「YouTube 视频」或「油管视频」，再在此基础上生成自然的查询句。

输出格式：
- 严格返回 3 行中文，每行一个独立的句子。
- 每行只包含句子本身，不要任何说明性文字。
- 禁止输出任何形式的序号或项目符号（例如 "1."、「①」、「- 」、「(1)」、「【】」等），也不要使用类似「问题1:」「建议：」「查询：」之类的前缀。]]

    local user_prompt = string.format([[
【拼音】
%s

【当前候选（最多前 5 个）】
%s

请判断这段拼音在日常语境下最常见、最合理的中文含义，结合当前候选，生成 3 个语义高度贴近的中文句子，作为用户真正想输入的查询/请求。句子要简洁自然，严格贴合原意，不要无端联想或扩展到其它话题。按 3 行输出，每行一个句子，不要加任何序号或前缀。]],
        pinyin,
        candidates_text
    )

    -- 生成问题阶段：只做意图澄清，限制长度在 500 tokens 内
    local request_body = build_request_body(system_prompt, user_prompt, 0.1, 500, false)

    local headers = {
        ["Content-Type"] = "application/json",
        ["Authorization"] = "Bearer " .. ai_config.api_key
    }

    local response, err = http_post(ai_config.base_url, headers, request_body)
    if err or not response then
        debug_log("ERROR: Failed to generate questions")
        return nil
    end

    local content = parse_json_response(response)
    if not content or content == "" then
        debug_log("ERROR: Empty content from parse_json_response")
        return nil
    end

    debug_log("Raw question content: " .. content:sub(1, 200))

    -- 分割成多个问题
    local questions = {}
    for line in content:gmatch("[^\n]+") do
        line = line:gsub("^%s*", ""):gsub("%s*$", "")
        -- 过滤掉空行、太短的行和非中文内容
        if line ~= "" and #line >= 3 and line:match("[\228-\233]") then
            table.insert(questions, line)
            debug_log("Question " .. #questions .. ": " .. line)
            if #questions >= 3 then
                break
            end
        end
    end

    if #questions == 0 then
        debug_log("ERROR: No valid questions generated")
        return nil
    end

    debug_log("Generated " .. #questions .. " questions")
    return questions
end

-- 回答问题
local function answer_question(question)
    debug_log("=== Answering Question ===")
    debug_log("Question: " .. question)

    local system_prompt = [[你是一名集成在中文输入法中的回答助手。用户在同一段输入上连续按下两次 Command 键时，表示希望你基于当前这句话给出一个「可以直接上屏」的最终答案。

【你的角色】
- 以中文回答为主，语气自然克制，不自报身份，不寒暄。
- 你的输出会直接插入用户正在编辑的文本或对话，不能像聊天机器人那样啰嗦。

【你会收到什么】
- 一段已经尽量还原用户真实意图的中文句子或短语（可能来自拼音转写、也可能是用户原文），例如：
  - 事实性问题（“杭州现在天气怎么样”“马斯克多少岁了”）
  - 信息检索类请求（“比亚迪最新股价”“ChatGPT 4.0 发布时间”）
  - 内容生成类请求（“写一条生日祝福给同事”“讲一个冷笑话”）
  - 主题短语（“辛亥革命简介”“区块链优缺点”）等。

【工具和实时信息（重点）】
- 你可以通过 web_search 等工具获取最新信息。(注意，今年是2025年)
- 当问题明确涉及「现在/当前/今天/实时/最新」等时间敏感内容时，你应当优先使用这些工具，而不要凭记忆或常识猜测。
  典型需要使用工具的场景包括但不限于：
  - 实时天气、温度、空气质量（例如“杭州现在天气怎么样”“今天上海要下雨吗”）
  - 汇率、股价、基金净值、币价（例如“现在美元对人民币汇率”“比亚迪最新股价”）
  - 实时新闻、最新进展、赛事比分、排期/发售时间等（例如“苹果最新发布会有什么内容”“昨天湖人比赛比分”）。
- 如果工具不可用、超时或信息高度不确定，你应简洁说明不确定性，例如：
  - “无法确定当前的具体天气情况，可以打开天气类 App 查看实时信息。”
  - “股价等金融数据随时波动，请以交易软件或官网为准。”
- 在这类场景下，禁止编造一个看起来很具体、但没有根据的数字或描述（例如捏造温度、价格、准确时间等）。

【回答内容】
1. 准确性优先：尽量基于可靠来源回答，不确定就说明不确定，而不是装作确定。
2. 重点突出：覆盖当前意图下最重要的 1–3 个信息点，避免与问题无关的扩展。
3. 简洁实用：通常用 1–2 句说清楚，或在适当场景下只返回一个词语、短语、标题或网址本身。
4. 直接可用：当用户在找“标题 / 名称 / 链接 / 网址”等时，请直接给出对应内容（例如 `www.example.com` 或一个标题字符串），不要加「标题是：」「网址是：」之类的前缀。
5. 内容生成类请求（如笑话、祝福语、文案等），请直接给出一份质量较高、可以直接上屏使用的结果，不需要解释你的创作思路。

【输出约束】
- 输出一个连续的中文或中英混合文本片段：
  - 通常为 1–2 句话；
  - 某些场景下可以只输出一个词、短语、标题或网址。
- 不要使用任何序号、列表符号或多行分点结构。
- 不要在开头或结尾添加「好的，下面是」「希望对你有帮助」「作为一个 AI 助手」等客套或说明性语句。
- 不要在输出中出现诸如「这是一个问题意图」「用户想知道……」之类的分析性说明，这些判断只保留在你的内部思考中。]]

    local user_prompt = string.format(
        "用户输入：%s\n\n直接给出用户真正想要的内容本身。可以是 1–2 句话，也可以在合适时仅返回一个词语、短语、标题或网址。严格按照以下要求输出：只输出答案本身，不要重复或改写用户输入，不要添加任何序号、项目符号、分点说明，也不要出现“好的，下面是：”“标题是：”“网址是：”之类的前缀或客套话。",
        question
    )

    -- 回答阶段：允许更长回答，最多约 1000 tokens，并可启用 web_search 等 tools
    local request_body = build_request_body(system_prompt, user_prompt, 0.3, 1000, true)

    local headers = {
        ["Content-Type"] = "application/json",
        ["Authorization"] = "Bearer " .. ai_config.api_key
    }

    local response, err = http_post(ai_config.base_url, headers, request_body)
    if err or not response then
        debug_log("ERROR: Failed to answer question")
        return nil
    end

    local content = parse_json_response(response)
    if not content or content == "" then
        debug_log("ERROR: Empty content from parse_json_response")
        return nil
    end

    debug_log("Raw answer content: " .. content:sub(1, 200))  -- 记录前200个字符

    -- 清理回答内容，去除多余的空白和换行
    content = content:gsub("^%s*", ""):gsub("%s*$", "")

    -- 尝试去掉明显的「意图说明」行，比如“这是一个问题意图。”
    local cleaned_lines = {}
    for line in content:gmatch("[^\n]+") do
        local trimmed = line:gsub("^%s*", ""):gsub("%s*$", "")
        local lower = trimmed
        -- 过滤典型的 meta 说明句
        local is_meta =
            trimmed == "" or
            trimmed:find("意图", 1, true) ~= nil or
            trimmed:match("^这是一?个.+[意类]图[。？！?!]?$")
        if not is_meta then
            table.insert(cleaned_lines, trimmed)
        end
    end
    if #cleaned_lines > 0 then
        content = table.concat(cleaned_lines, "\n")
    end

    -- 不再强制要求包含中文，允许纯网址、标题等 ASCII 内容
    if content == "" then
        debug_log("ERROR: Empty answer after trimming")
        return nil
    end

    debug_log("Complete answer: " .. content)

    -- 返回单个完整答案（作为数组，保持接口一致）
    return {content}
end

-- 调用 AI API
local function call_ai_api(current_pinyin, history_context, raw_candidates)
    debug_log("=== AI API Call Start ===")
    debug_log("Current pinyin input: " .. current_pinyin)
    debug_log("History context: " .. history_context)

    if not ai_config.enabled then
        debug_log("AI disabled")
        return nil
    end

    -- 构建候选列表文本，提供给模型用于“验证与纠正”
    local candidates_text = ""
    if raw_candidates and #raw_candidates > 0 then
        local parts = {}
        local max_show = math.min(#raw_candidates, 5)
        for i = 1, max_show do
            table.insert(parts, string.format("%d. %s", i, raw_candidates[i]))
        end
        candidates_text = table.concat(parts, "\n")
    end

    debug_log("AI candidate snapshot for pinyin '" .. current_pinyin .. "':\n" .. (candidates_text ~= "" and candidates_text or "(no candidates)"))

    -- 构建优化的提示词：强调“候选验证 + 轻量纠正 + 句子联想”
    local user_prompt
    if history_context == "" then
        user_prompt = string.format([[
【拼音】
%s

【当前候选（最多前 5 个）】
%s

请根据以上拼音和候选，先判断哪些候选最贴近用户本意，并在此基础上给出 1～3 个更好的候选，这些候选可以是经过小幅修正或适度续写后的完整短句。

要求：
1. 优先复用已有候选中最合理的表达，只有在明显不自然或不准确时才改写。
2. 在贴合原意的前提下，你可以对好的候选做适度联想和续写，让句子更加完整或信息更充分，但不要偏离原本语义。
3. 严格输出 1～3 行中文，每行一个候选，按推荐顺序排列，不要添加任何解释、编号或前缀。]],
            current_pinyin,
            candidates_text
        )
    else
        user_prompt = string.format([[
【上下文】
%s

【拼音】
%s

【当前候选（最多前 5 个）】
%s

请结合上下文和候选，判断用户最可能想表达的句子或短语，并据此给出 1～3 个按优先级排序的候选，这些候选可以在原有候选的基础上做轻微修正或续写，使整句更加自然、完整。

要求：
1. 优先复用已有候选中最合理的表达，必要时可对其做小幅修改以更贴合上下文。
2. 在不改变核心语义的前提下，可以对句子进行适度延伸，补充自然的后半句或常见搭配。
3. 避免发散到无关话题，不要引入上下文中没有的新意图。
4. 严格输出 1～3 行中文，每行一个候选，按推荐顺序排列，不要添加任何解释、编号或前缀。]],
            history_context,
            current_pinyin,
            candidates_text
        )
    end

    -- 构建请求体：Tab 联想 / 第一次 Command，统一限制在 500 tokens 内
    local request_body = build_request_body(ai_config.system_prompt, user_prompt, 0.2, 500, false)

    debug_log("Request body: " .. request_body)

    -- 发送请求
    local headers = {
        ["Content-Type"] = "application/json",
        ["Authorization"] = "Bearer " .. ai_config.api_key
    }

    local response, err = http_post(ai_config.base_url, headers, request_body)
    if err or not response then
        debug_log("ERROR: HTTP request failed - " .. (err or "no response"))
        return nil
    end

    -- 解析响应
    local content = parse_json_response(response)
    if not content then
        debug_log("ERROR: Failed to parse JSON response")
        return nil
    end

    debug_log("Parsed content: " .. content)

    -- 分割成多个候选，并清理空白字符
    local candidates = {}
    for line in content:gmatch("[^\n]+") do
        -- 去除首尾空白和特殊字符
        line = line:gsub("^%s*", ""):gsub("%s*$", "")
        -- 过滤掉空行和非中文内容（保留中文、标点符号）
        if line ~= "" and line:match("[\228-\233]") then  -- 简单的中文字符检测
            table.insert(candidates, line)
            debug_log("Candidate " .. #candidates .. ": " .. line)
            if #candidates >= ai_config.max_candidates then
                break
            end
        end
    end

    debug_log("Total candidates: " .. #candidates)
    debug_log("=== AI API Call End ===")

    return candidates
end

-- ============================================================================
-- Rime Processor（按键处理）
-- ============================================================================

function ai_completion_processor(key, env)
    local engine = env.engine
    local context = engine.context

    -- 检测按键 - 使用 key:repr() 函数调用
    local key_repr = key:repr()
    local input = context.input

    -- 处理 Command 键：两段式问答（先出题，再回答选中的题目）
    -- macOS 的 Command 键被识别为 Super+Super_L 或 Super+Super_R
    if key_repr == "Super+Super_L" or key_repr == "Super+Super_R" or
       key_repr == "Super_L" or key_repr == "Super_R" then
        if input and input ~= "" then
            debug_log("Command pressed with input: " .. input)

            local now = get_timestamp()

            -- 检查是否在同一次输入（30秒内）- 延长时间以便用户选择
            local is_same_session = (qa_state.last_input == input and (now - qa_state.timestamp) < 30)

            debug_log("QA State - mode: " .. qa_state.mode .. ", is_same_session: " .. tostring(is_same_session))
            debug_log("Time diff: " .. tostring(now - qa_state.timestamp) .. " seconds")

            if qa_state.mode == "none" or not is_same_session then
                -- 第一次按 Command：基于拼音 + 当前候选生成贴本意的查询/请求候选（不考虑历史上下文）
                debug_log("Generating query completions from candidates (no history)...")
                -- 这里不再依赖 ai_history_filter 的缓存，直接从当前高亮候选读取一个代表性候选
                local raw_candidates = {}
                local selected = context:get_selected_candidate()
                if selected and selected.text and selected.text ~= "" then
                    raw_candidates = { selected.text }
                    debug_log("Using selected candidate for Command-1: " .. selected.text)
                else
                    debug_log("No selected candidate available for Command-1")
                end
                local questions = generate_question(input, raw_candidates)

                if questions and #questions > 0 then
                    -- 保存状态
                    qa_state.mode = "question"
                    qa_state.question = questions[1]  -- 保存第一个问题用于回答
                    qa_state.last_input = input
                    qa_state.timestamp = now

                    -- 缓存3个问题作为候选
                    ai_candidates_cache.input = input
                    ai_candidates_cache.candidates = questions
                    ai_candidates_cache.timestamp = now

                    context:refresh_non_confirmed_composition()
                    return 1  -- kAccepted
                end

            elseif qa_state.mode == "question" and is_same_session then
                -- 第二次按 Command：回答用户选中的问题
                debug_log("Second Command press - answering question")

                -- 尝试获取当前选中的候选
                local composition = context.composition
                local segment = composition:back()
                local selected_question = nil

                if segment then
                    local selected_index = segment.selected_index
                    debug_log("Selected index from segment: " .. tostring(selected_index))
                    debug_log("Cache candidates count: " .. tostring(ai_candidates_cache.candidates and #ai_candidates_cache.candidates or "nil"))

                    if ai_candidates_cache.candidates then
                        for i, q in ipairs(ai_candidates_cache.candidates) do
                            debug_log("Cached question [" .. i .. "]: " .. q)
                        end
                    end

                    -- 从缓存中获取对应的问题
                    if ai_candidates_cache.candidates and selected_index >= 0 and selected_index < #ai_candidates_cache.candidates then
                        selected_question = ai_candidates_cache.candidates[selected_index + 1]
                        debug_log("Selected question from cache: " .. selected_question)
                    else
                        debug_log("Condition failed - candidates: " .. tostring(ai_candidates_cache.candidates ~= nil) ..
                                  ", index >= 0: " .. tostring(selected_index >= 0) ..
                                  ", index < count: " .. tostring(selected_index < #ai_candidates_cache.candidates))
                    end
                else
                    debug_log("No segment available")
                end

                -- 如果没有获取到选中的问题，使用第一个问题作为默认
                if not selected_question then
                    selected_question = qa_state.question
                    debug_log("Using default (first) question: " .. selected_question)
                end

                debug_log("About to call answer_question with: " .. selected_question)
                local answers = answer_question(selected_question)
                debug_log("answer_question returned: " .. tostring(answers and #answers or "nil"))

                if answers and #answers > 0 then
                    -- 缓存答案作为候选
                    ai_candidates_cache.input = input
                    ai_candidates_cache.candidates = answers
                    ai_candidates_cache.timestamp = now

                    -- 重置状态
                    qa_state.mode = "none"
                    qa_state.question = nil

                    context:refresh_non_confirmed_composition()
                    return 1  -- kAccepted
                else
                    debug_log("ERROR: Failed to get answers or answers is empty")
                end
            end
        end

        return 2  -- kNoop
    end

    -- 处理 Tab 键
    if key_repr == "Tab" or key.keycode == 0xff09 then
        if input and input ~= "" then
            debug_log("Tab pressed with input: " .. input)

            -- 重置问答状态
            qa_state.mode = "none"
            qa_state.question = nil

            -- 获取历史上下文
            local history = get_history_context()

            -- 获取当前候选列表（用于“验证与纠正 + 联想”），仅在编码一致时使用，避免读取上一句话的候选
            local raw_candidates = {}
            -- 同样不再依赖 last_candidates，直接使用当前高亮候选
            local selected = context:get_selected_candidate()
            if selected and selected.text and selected.text ~= "" then
                raw_candidates = { selected.text }
                debug_log("Using selected candidate for Tab: " .. selected.text)
            else
                debug_log("No selected candidate available for Tab")
            end

            -- 调用 AI API（传入拼音、上下文以及当前候选列表）
            local candidates = call_ai_api(input, history, raw_candidates)

            if candidates and #candidates > 0 then
                -- 缓存 AI 候选结果
                ai_candidates_cache.input = input
                ai_candidates_cache.candidates = candidates
                ai_candidates_cache.timestamp = get_timestamp()

                debug_log("AI candidates cached: " .. #candidates .. " items")

                -- 刷新候选列表，让 translator 显示 AI 候选
                context:refresh_non_confirmed_composition()

                return 1  -- kAccepted - 阻止 Tab 的默认行为
            else
                debug_log("AI call returned no candidates")
                -- 不做任何操作，让 Tab 键正常工作
                return 2  -- kNoop
            end
        end
    end

    return 2  -- kNoop
end

-- ============================================================================
-- Rime Translator（生成候选词）
-- ============================================================================

function ai_completion_translator(input, seg, env)
    -- 检查是否有缓存的 AI 候选
    if not ai_candidates_cache.candidates then
        return
    end

    -- 检查缓存是否匹配当前输入
    if ai_candidates_cache.input ~= input then
        return
    end

    -- 检查缓存是否过期（30秒）- 给用户足够时间选择
    local now = get_timestamp()
    if now - ai_candidates_cache.timestamp > 30 then
        ai_candidates_cache.candidates = nil
        return
    end

    debug_log("Generating AI candidates for: " .. input)

    -- 不在候选上显示任何 AI 标记，使外观与普通候选一致
    local comment_label = ""

    -- 生成 AI 候选项
    for i, text in ipairs(ai_candidates_cache.candidates) do
        local cand = Candidate("ai_completion", seg.start, seg._end, text, comment_label)
        cand.quality = 1000 + i  -- 高优先级，显示在最前面
        yield(cand)
        debug_log("Yielded candidate: " .. text)
    end

    -- 不要立即清空缓存，保留缓存以便第二次 Command 时使用
    -- 缓存会在过期时自动清空（30秒）或在新的输入时被覆盖
end

-- ============================================================================
-- 初始化和提交钩子
-- ============================================================================

-- 全局变量：保存上一次的候选列表（供提交时使用），以及当时的编码
local last_candidates = {}
local last_candidates_input = ""

-- 简化的历史记录捕获：记录所有候选，在提交时查找
function ai_history_filter(input, env)
    -- 清空上次的候选列表
    last_candidates = {}
    -- 记录当前编码，用于判断候选是否与当前输入匹配
    last_candidates_input = env.engine.context.input or ""

    -- 收集所有候选
    for cand in input:iter() do
        -- 保存候选文本（用于后续匹配）
        table.insert(last_candidates, cand.text)
        yield(cand)
    end
end

-- 使用 processor 在提交前捕获文本
function ai_history_processor(key, env)
    -- 简单测试：记录所有按键
    local success, err = pcall(function()
        -- key:repr() 是函数调用，不是属性
        local key_repr = key:repr()
        debug_log("ai_history_processor called, key: " .. tostring(key_repr))

        local engine = env.engine
        local context = engine.context

        -- 检测提交键（空格、回车、数字键1-9）
        local is_space = (key_repr == "space")
        local is_return = (key_repr == "Return")
        local is_number = (key_repr >= "1" and key_repr <= "9")
        local is_commit_key = is_space or is_return or is_number

        if is_commit_key and #last_candidates > 0 then
            debug_log("Commit key detected, candidates: " .. #last_candidates)

            -- 空格键默认选择第一个候选（索引0）
            local selected_index = 0

            -- 数字键对应相应索引
            if is_number then
                selected_index = tonumber(key_repr) - 1
            end

            -- 从候选列表中获取对应的文本
            if selected_index >= 0 and selected_index < #last_candidates then
                local text = last_candidates[selected_index + 1]
                if text and text ~= "" then
                    debug_log("Committing: " .. text)
                    add_to_history(text)
                end
            end
        end
    end)

    if not success then
        debug_log("ERROR in ai_history_processor: " .. tostring(err))
    end

    return 2  -- kNoop - 让其他 processor 继续处理
end
