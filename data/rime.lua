-- rime.lua
-- AI 智能补全插件

-- ============================================================================
-- 全局状态管理
-- ============================================================================

-- 输入历史记录（用于 AI 上下文）
local input_history = {}
local context_window_minutes = 10  -- 改为 10 分钟

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

-- AI 配置（从 schema 读取）
local ai_config = {
    enabled = true,
    -- GPT-4o-mini 配置（用于联想和问题生成）
    base_url = "https://api.openai.com/v1/chat/completions",
    api_key = "YOUR_API_KEY_HERE",
    model_name = "gpt-4o-mini",
    -- Grok 配置（用于问题回答）
    grok_base_url = "https://api.x.ai/v1/chat/completions",
    grok_api_key = "YOUR_GROK_API_KEY_HERE",
    grok_model_name = "grok-4-fast",
    max_candidates = 3,
    system_prompt = [[你是一个中文输入法的联想与补全助手，主要目标是帮助用户更快输入自然、简洁的短语。

使用场景：
- 用户正在电脑或手机上打字，使用拼音输入法。
- 你只负责根据用户的历史输入和当前拼音，给出若干联想候选。

你会得到：
1. 最近 10 分钟内用户已经输入的中文文本（上下文）
2. 当前正在输入的拼音串（例如 nihao、wojiao 等）

你的任务：
- 正确理解该拼音对应的中文词语或短语。
- 结合上下文，联想出用户很可能想继续输入的内容。
- 每个联想结果都必须包含这个中文词语或短语（或其自然变体），并尽量放在句子或短语的开头。
- 优先生成适合直接上屏的短语或简短句子，而不是很长的段落。
- 严格避免跑题，不要引入与上下文和当前拼音无关的话题。

示例澄清：
- 拼音：ruhexiazaipython
  应理解为“如何下载 Python（软件本身）”，合适的联想可以是“如何下载并安装 Python？”、“在哪里可以下载 Python 官方安装包？”等；
  不要改写成“如何在 Python 中实现下载功能”等改变语义的表达。

输出格式：
- 严格返回 3 行文本，每行一个候选。
- 每行只包含候选内容本身，不要任何说明性文字。
- 禁止输出任何形式的序号或项目符号（例如 "1."、"①"、"- "、"(1)"、"【】" 等），也不要使用类似“候选1:”“建议：”之类的前缀。
- 内容要自然、口语化或书面化均可，但需要适合直接作为输入法候选上屏。
- 在满足上述条件的前提下，每个候选建议控制在约 8～20 个汉字。]]
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

-- 生成有价值的问题
local function generate_question(pinyin)
    debug_log("=== Generating Questions ===")
    debug_log("Pinyin: " .. pinyin)

    local system_prompt = [[你是一个中文输入法中的“出题助手”，根据用户正在输入的拼音，给出几个值得思考或检索的中文问题。

使用场景：
- 用户输入一个词语或短语的拼音，你需要理解它最常见、最合理的含义。
- 你要围绕这个含义，生成若干有价值、自然的中文问句，方便用户继续输入或搜索。

处理原则：
1. 先判断拼音最常见、最合理的中文含义，可以是人名、地名、专有名词、技术术语或普通词语。
2. 如果存在多种同音含义，优先选择日常使用中最常见、最合理的那个，不要生造冷僻解释。
3. 围绕选定含义，从不同角度设计问题，例如背景信息、使用方法、影响、优缺点等。
4. 问句要具体、有信息量，避免“是什么？”这类过于空泛的提问。

注意事项：
- 可以识别并正确书写名人、品牌、技术术语等，但不要过度强行往这些方向猜。
- 结合常见搭配和使用场景，保证问句自然、符合中文表达习惯。
- 不要简单地把拼音逐字拆开解释，要理解它在真实语境下最可能指代的东西。

特别示例：
- 当拼音是 ruhexiazaipython 时，应理解为“如何下载 Python（软件本身）”，而不是“如何在 Python 中实现下载功能”。在类似结构下，优先保持“如何下载 X”这种动宾关系的语义，不要改写成“在 X 中如何实现下载”。 

输出格式：
- 严格返回 3 行中文，每行一个独立的问句。
- 不要在行首添加任何序号、项目符号或其它前缀（例如 "1."、"①"、"- "、"(1)"、"【】" 等），也不要使用类似“问题1:”“问题：”之类的文字说明。
- 每个问题是完整的句子，以问号结尾，信息尽量具体、有价值。]]

    local user_prompt = string.format(
        "拼音：%s\n\n请先判断这个拼音在日常语境下最常见、最合理的中文含义，然后围绕这个含义生成 3 个有价值的中文问题。问题要具体、有信息量，并以问号结尾。严格按 3 行输出，每行一个问题，不要加任何序号、项目符号或其它前缀。",
        pinyin
    )

    local request_body = string.format([[{
        "model": "%s",
        "messages": [
            {"role": "system", "content": "%s"},
            {"role": "user", "content": "%s"}
        ],
        "temperature": 0.1,
        "max_tokens": 300
    }]],
        ai_config.model_name,
        system_prompt:gsub('"', '\\"'):gsub('\n', '\\n'),
        user_prompt:gsub('"', '\\"'):gsub('\n', '\\n')
    )

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

    local system_prompt = [[你是一个专业、友好的中文问答助手，用于在输入法中为用户提供简洁但有用的答案。

回答任务：
- 用户会给出一个中文问题，你需要给出一个直接、清晰的回答。
- 重点是快速传达核心信息，而不是写长篇大论。

回答原则：
1. 准确性：尽量提供真实、可靠的信息；不确定时可简要说明不确定性。
2. 完整性：覆盖问题中最重要的 1–3 个信息点。
3. 简洁性：用 1–2 句话说明白，避免冗长解释。
4. 实用性：优先给出对用户有帮助、可执行或可理解的内容。

输出格式：
- 返回一个连续的中文回答段落（通常 1–2 句话）。
- 不要使用任何序号、列表符号或多行结构。
- 直接输出答案内容，不要解释你的思考过程，不要重复“问题是……”，不要添加“回答：”“回答1:” 等前缀。]]

    local user_prompt = string.format(
        "问题：%s\n\n请用 1–2 句话给出一个准确、简洁、信息量足够的回答。只输出答案本身，不要重复问题，也不要添加任何序号、项目符号或分点说明。",
        question
    )

    local request_body = string.format([[{
        "model": "%s",
        "messages": [
            {"role": "system", "content": "%s"},
            {"role": "user", "content": "%s"}
        ],
        "temperature": 0.7,
        "max_tokens": 500
    }]],
        ai_config.model_name,
        system_prompt:gsub('"', '\\"'):gsub('\n', '\\n'),
        user_prompt:gsub('"', '\\"'):gsub('\n', '\\n')
    )

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

    -- 检查是否包含中文内容
    if not content:match("[\228-\233]") then
        debug_log("ERROR: No Chinese content in answer")
        return nil
    end

    debug_log("Complete answer: " .. content)

    -- 返回单个完整答案（作为数组，保持接口一致）
    return {content}
end

-- 调用 AI API
local function call_ai_api(current_pinyin, history_context)
    debug_log("=== AI API Call Start ===")
    debug_log("Current pinyin input: " .. current_pinyin)
    debug_log("History context: " .. history_context)

    if not ai_config.enabled then
        debug_log("AI disabled")
        return nil
    end

    -- 构建优化的提示词
    local user_prompt
    if history_context == "" then
        -- 没有历史记录时
        user_prompt = string.format(
            "拼音：%s\n\n请根据该拼音对应的中文词语，生成 3 个联想候选。每个候选必须包含该中文词语（或其自然变体），并尽量放在开头；候选应为简短的短语或短句，不要太长。严格按 3 行输出，每行一个候选，禁止任何序号、项目符号或解释。",
            current_pinyin
        )
    else
        -- 有历史记录时
        user_prompt = string.format(
            "【上下文】\n%s\n\n【拼音】\n%s\n\n请基于以上上下文，使用该拼音对应的中文词语，生成 3 个可能的续写候选。每个候选必须包含该中文词语（或其自然变体），并尽量放在短语或句子的开头；候选应为简短的短语或短句，紧扣上下文含义，不要跑题。严格按 3 行输出，每行一个候选，禁止任何序号、项目符号或解释。",
            history_context,
            current_pinyin
        )
    end

    -- 构建请求体
    local request_body = string.format([[{
        "model": "%s",
        "messages": [
            {"role": "system", "content": "%s"},
            {"role": "user", "content": "%s"}
        ],
        "temperature": 0.9,
        "max_tokens": 200
    }]],
        ai_config.model_name,
        ai_config.system_prompt:gsub('"', '\\"'):gsub('\n', '\\n'),
        user_prompt:gsub('"', '\\"'):gsub('\n', '\\n')
    )

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

    -- 处理 Command 键
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
                -- 第一次按 Command：生成3个有价值的问题
                debug_log("Generating valuable questions...")
                local questions = generate_question(input)

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

            -- 调用 AI API
            local candidates = call_ai_api(input, history)

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

    -- 根据问答状态决定显示的标记
    local comment_label
    if qa_state.mode == "question" then
        comment_label = "❓ 问题"
    elseif qa_state.mode == "none" and qa_state.question then
        comment_label = "💡 回答"
    else
        comment_label = "🤖 AI"
    end

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

-- 全局变量：保存上一次的候选列表
local last_candidates = {}

-- 简化的历史记录捕获：记录所有候选，在提交时查找
function ai_history_filter(input, env)
    -- 清空上次的候选列表
    last_candidates = {}

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
