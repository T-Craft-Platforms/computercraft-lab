-- shakespereBot
-- Offline Siri-style assistant for CC:Tweaked with keyword+priority routing.
-- No external services, no LLMs, fully local learning + persistence.

local BOT_NAME = "shakespereBot"
local BOT_VERSION = "2.0.0"
local DATA_DIR = "/.shakespereBot"
local DB_FILE = fs.combine(DATA_DIR, "knowledge.db")
local MAX_HISTORY = 150

local STOP_WORDS = {
    ["a"] = true, ["an"] = true, ["the"] = true, ["is"] = true, ["are"] = true,
    ["was"] = true, ["were"] = true, ["am"] = true, ["be"] = true, ["to"] = true,
    ["of"] = true, ["in"] = true, ["on"] = true, ["at"] = true, ["for"] = true,
    ["and"] = true, ["or"] = true, ["with"] = true, ["from"] = true, ["as"] = true,
    ["my"] = true, ["your"] = true, ["our"] = true, ["their"] = true, ["this"] = true,
    ["that"] = true, ["it"] = true, ["i"] = true, ["you"] = true, ["me"] = true,
    ["we"] = true, ["they"] = true, ["he"] = true, ["she"] = true, ["what"] = true,
    ["who"] = true, ["why"] = true, ["when"] = true, ["where"] = true, ["how"] = true,
    ["do"] = true, ["does"] = true, ["did"] = true, ["can"] = true, ["could"] = true,
    ["would"] = true, ["should"] = true, ["please"] = true, ["tell"] = true,
}

local function trim(s)
    return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function lower(s)
    return string.lower(s or "")
end

local function normalize(s)
    local x = lower(s)
    x = x:gsub("[^%w%s]", " ")
    x = x:gsub("%s+", " ")
    return trim(x)
end

local function strip_end_punct(s)
    return trim((s or ""):gsub("[%?!%.]+$", ""))
end

local function contains(haystack, needle)
    return haystack:find(needle, 1, true) ~= nil
end

local function clock_string()
    if textutils and textutils.formatTime and os.time then
        return textutils.formatTime(os.time(), true)
    end
    return "unknown time"
end

local function day_string()
    if os.day then
        return "day " .. tostring(os.day())
    end
    return "unknown day"
end

local function now_string()
    if os.date then
        return os.date("%Y-%m-%d %H:%M:%S")
    end
    if os.epoch then
        return tostring(math.floor(os.epoch("utc") / 1000))
    end
    return tostring(os.time() or 0)
end

local function tokenize(text)
    local out = {}
    for word in normalize(text):gmatch("%w+") do
        out[#out + 1] = word
    end
    return out
end

local function keyword_list(text)
    local seen, out = {}, {}
    for _, word in ipairs(tokenize(text)) do
        if #word > 2 and not STOP_WORDS[word] and not seen[word] then
            seen[word] = true
            out[#out + 1] = word
        end
    end
    return out
end

local function keyword_set(text)
    local set = {}
    for _, word in ipairs(keyword_list(text)) do
        set[word] = true
    end
    return set
end

local function overlap_score(a_words, b_words)
    local a, b = {}, {}
    for _, w in ipairs(a_words) do a[w] = true end
    for _, w in ipairs(b_words) do b[w] = true end

    local common, total = 0, 0
    for w in pairs(a) do
        total = total + 1
        if b[w] then common = common + 1 end
    end
    for w in pairs(b) do
        if not a[w] then total = total + 1 end
    end
    if total == 0 then
        return 0
    end
    return common / total
end

local function pick(options)
    return options[math.random(1, #options)]
end

local function mk_default_db()
    return {
        version = 2,
        qa = {},
        facts = {},
        history = {},
        next_qa_id = 1,
        stats = {
            interactions = 0,
            learned_facts = 0,
            taught_answers = 0,
        }
    }
end

local function validate_db(db)
    if type(db) ~= "table" then
        return mk_default_db()
    end
    db.version = tonumber(db.version) or 2
    db.qa = type(db.qa) == "table" and db.qa or {}
    db.facts = type(db.facts) == "table" and db.facts or {}
    db.history = type(db.history) == "table" and db.history or {}
    db.next_qa_id = tonumber(db.next_qa_id) or 1
    db.stats = type(db.stats) == "table" and db.stats or {}
    db.stats.interactions = tonumber(db.stats.interactions) or 0
    db.stats.learned_facts = tonumber(db.stats.learned_facts) or 0
    db.stats.taught_answers = tonumber(db.stats.taught_answers) or 0
    return db
end

local function load_db()
    if not fs.exists(DB_FILE) then
        return mk_default_db()
    end

    local f = fs.open(DB_FILE, "r")
    if not f then
        return mk_default_db()
    end
    local raw = f.readAll()
    f.close()
    if not raw or raw == "" then
        return mk_default_db()
    end

    local ok, data = pcall(textutils.unserialize, raw)
    if not ok then
        return mk_default_db()
    end

    return validate_db(data)
end

local function save_db(db)
    if not fs.exists(DATA_DIR) then
        fs.makeDir(DATA_DIR)
    end

    local f = fs.open(DB_FILE, "w")
    if not f then
        return false, "cannot open db file"
    end
    f.write(textutils.serialize(db))
    f.close()
    return true
end

local db = load_db()

local function remember(role, text)
    db.history[#db.history + 1] = { role = role, text = text, at = now_string() }
    while #db.history > MAX_HISTORY do
        table.remove(db.history, 1)
    end
end

local function fact_subject_key(subject)
    local key = normalize(subject)
    if key == "me" or key == "myself" or key == "i" then
        return "user"
    end
    if key == "you" or key == "yourself" then
        return BOT_NAME
    end
    return key
end

local function learn_fact(subject, relation, object_text)
    local s = trim(subject)
    local r = normalize(relation)
    local o = strip_end_punct(object_text)
    local key = fact_subject_key(s)
    if key == "" or r == "" or o == "" then
        return false
    end

    local rec = db.facts[key]
    if not rec then
        rec = { subject = s, relations = {} }
        db.facts[key] = rec
    end
    if rec.subject == "" then
        rec.subject = s
    end

    local list = rec.relations[r]
    if not list then
        list = {}
        rec.relations[r] = list
    end

    local o_norm = normalize(o)
    for _, entry in ipairs(list) do
        if normalize(entry.value) == o_norm then
            return false
        end
    end

    list[#list + 1] = {
        value = o,
        at = now_string(),
        priority = 55,
    }
    db.stats.learned_facts = db.stats.learned_facts + 1
    return true
end

local function parse_fact_statement(text)
    local clean = lower(strip_end_punct(text))
    local patterns = {
        { "^(.+)%s+is%s+(.+)$", "is" },
        { "^(.+)%s+are%s+(.+)$", "are" },
        { "^(.+)%s+likes%s+(.+)$", "likes" },
        { "^(.+)%s+has%s+(.+)$", "has" },
        { "^(.+)%s+lives%s+in%s+(.+)$", "lives in" },
    }
    for _, p in ipairs(patterns) do
        local a, b = clean:match(p[1])
        if a and b then
            return trim(a), p[2], trim(b)
        end
    end
    return nil
end

local function facts_about(subject)
    local key = fact_subject_key(subject)
    local rec = db.facts[key]
    if not rec then
        return nil
    end
    local bits = {}
    for rel, values in pairs(rec.relations) do
        local latest = values[#values]
        if latest and latest.value then
            bits[#bits + 1] = rel .. " " .. latest.value
        end
    end
    table.sort(bits)
    if #bits == 0 then
        return nil
    end
    if #bits == 1 then
        return rec.subject .. " " .. bits[1] .. "."
    end
    return rec.subject .. ": " .. table.concat(bits, "; ") .. "."
end

local function parse_teach_command(raw_body)
    local q, a, meta = raw_body:match("^(.-)%s*=>%s*(.-)%s*::%s*(.+)$")
    if not q then
        q, a = raw_body:match("^(.-)%s*=>%s*(.+)$")
    end
    if not q or not a then
        return nil, "Format: :teach <question> => <answer> [:: p=80; k=word1,word2]"
    end

    q = trim(q)
    a = trim(a)
    if q == "" or a == "" then
        return nil, "Question and answer must not be empty."
    end

    local priority = 60
    local kws = keyword_list(q)

    if meta and meta ~= "" then
        for part in meta:gmatch("[^;]+") do
            local k, v = trim(part):match("^(%w+)%s*=%s*(.+)$")
            if k and v then
                k = lower(trim(k))
                v = trim(v)
                if k == "p" or k == "priority" then
                    local n = tonumber(v)
                    if n then
                        if n < 1 then n = 1 end
                        if n > 120 then n = 120 end
                        priority = math.floor(n)
                    end
                elseif k == "k" or k == "keywords" then
                    kws = {}
                    local seen = {}
                    for kw in v:gmatch("[^,%s]+") do
                        local word = normalize(kw)
                        if word ~= "" and not seen[word] then
                            seen[word] = true
                            kws[#kws + 1] = word
                        end
                    end
                end
            end
        end
    end

    return {
        question = q,
        answer = a,
        priority = priority,
        keywords = kws,
        normalized = normalize(q),
    }
end

local function teach_qa(item)
    for _, entry in ipairs(db.qa) do
        if entry.normalized == item.normalized then
            entry.answer = item.answer
            entry.priority = item.priority
            entry.keywords = item.keywords
            entry.updated_at = now_string()
            return "Updated taught answer #" .. tostring(entry.id) .. "."
        end
    end

    item.id = db.next_qa_id
    db.next_qa_id = db.next_qa_id + 1
    item.taught_at = now_string()
    db.qa[#db.qa + 1] = item
    db.stats.taught_answers = db.stats.taught_answers + 1
    return "Learned answer #" .. tostring(item.id) .. "."
end

local function forget_memory(arg)
    local target = trim(arg or "")
    if target == "" then
        return "Format: :forget <qa-id|question|subject>"
    end

    local num = tonumber(target)
    if num then
        for i, entry in ipairs(db.qa) do
            if entry.id == num then
                table.remove(db.qa, i)
                return "Forgot taught answer #" .. tostring(num) .. "."
            end
        end
    end

    local norm = normalize(target)
    for i, entry in ipairs(db.qa) do
        if entry.normalized == norm then
            table.remove(db.qa, i)
            return "Forgot taught answer: " .. entry.question
        end
    end

    local fact_key = fact_subject_key(target)
    if db.facts[fact_key] then
        db.facts[fact_key] = nil
        return "Forgot facts about " .. target .. "."
    end

    return "No memory matched that."
end

local function list_summary()
    local fact_count = 0
    for _ in pairs(db.facts) do fact_count = fact_count + 1 end
    local lines = {
        "Knowledge summary:",
        "facts: " .. tostring(fact_count),
        "taught answers: " .. tostring(#db.qa),
        "interactions: " .. tostring(db.stats.interactions),
    }
    if #db.qa > 0 then
        lines[#lines + 1] = "Top taught answers:"
        local shown = math.min(8, #db.qa)
        for i = 1, shown do
            local e = db.qa[i]
            lines[#lines + 1] = "#" .. tostring(e.id) .. " p=" .. tostring(e.priority) .. " :: " .. e.question
        end
    end
    return table.concat(lines, "\n")
end

local function help_text()
    return table.concat({
        "Commands:",
        ":teach <question> => <answer>",
        ":teach <question> => <answer> :: p=80; k=redstone,logic",
        ":forget <qa-id|question|subject>",
        ":recall <subject>",
        ":list",
        ":stats",
        ":save",
        ":help",
        ":exit",
        "Natural learning:",
        "Say facts like: 'redstone is useful' or 'turtles are robots'.",
    }, "\n")
end

local function eval_math(text)
    local q = lower(strip_end_punct(text))
    local expr =
        q:match("^what%s+is%s+(.+)$") or
        q:match("^calculate%s+(.+)$") or
        q:match("^solve%s+(.+)$")

    if not expr then return nil end
    expr = trim(expr)
    if not expr:match("[%d]") then return nil end
    if not expr:match("^[%d%s%+%-%*/%%%^%(%)%.]+$") then
        return nil
    end

    local fn = load("return (" .. expr .. ")", "expr", "t", {})
    if not fn then
        return "That sum is malformed."
    end
    local ok, result = pcall(fn)
    if not ok then
        return "I cannot solve that expression."
    end
    if type(result) ~= "number" then
        return "That was no number."
    end
    return "The reckoning yields " .. tostring(result) .. "."
end

local function score_rule(rule, norm, tokens)
    local score = rule.priority or 0
    local hit = false

    if rule.phrases then
        for _, p in ipairs(rule.phrases) do
            if contains(norm, p) then
                score = score + 15
                hit = true
            end
        end
    end

    if rule.any then
        local matched_any = false
        for _, want in ipairs(rule.any) do
            for _, got in ipairs(tokens) do
                if got == want then
                    score = score + 8
                    matched_any = true
                    hit = true
                    break
                end
            end
        end
        if rule.require_any and not matched_any then
            return nil
        end
    end

    if rule.all then
        local all_hit = true
        for _, need in ipairs(rule.all) do
            local found = false
            for _, got in ipairs(tokens) do
                if got == need then
                    found = true
                    break
                end
            end
            if not found then
                all_hit = false
                break
            end
        end
        if all_hit then
            score = score + 15
            hit = true
        else
            return nil
        end
    end

    if rule.prefixes then
        for _, pre in ipairs(rule.prefixes) do
            if norm:sub(1, #pre) == pre then
                score = score + 12
                hit = true
            end
        end
    end

    if not hit then
        return nil
    end

    return score
end

local INTENTS = {
    {
        name = "identity",
        priority = 85,
        phrases = {"who are you", "your name"},
        run = function()
            return "I am " .. BOT_NAME .. ", thy humble answering engine."
        end
    },
    {
        name = "help",
        priority = 92,
        phrases = {"help", "what can you do", "commands"},
        any = {"help", "commands"},
        run = function()
            return help_text()
        end
    },
    {
        name = "thanks",
        priority = 70,
        all = {"thank", "you"},
        run = function()
            return pick({
                "I am thy servant in this.",
                "Freely given, with good will.",
                "Thou art welcome, good friend.",
            })
        end
    },
    {
        name = "greet",
        priority = 68,
        any = {"hello", "hi", "hey", "greetings"},
        require_any = true,
        run = function()
            return pick({
                "Well met. What seekest thou?",
                "Hail. Ask, and I shall answer.",
                "Good morrow. How may I serve?",
            })
        end
    },
    {
        name = "time",
        priority = 90,
        phrases = {"what time", "time is it", "tell me the time"},
        run = function()
            return "The clock doth show " .. clock_string() .. "."
        end
    },
    {
        name = "day",
        priority = 88,
        phrases = {"what day", "which day", "today"},
        run = function()
            return "It is " .. day_string() .. "."
        end
    },
}

local function best_taught_answer(user_text)
    local norm = normalize(user_text)
    local user_words = keyword_list(user_text)
    local best, best_score

    for _, entry in ipairs(db.qa) do
        local score = entry.priority or 60
        local hit = false

        if entry.normalized == norm then
            score = score + 100
            hit = true
        else
            local ov = overlap_score(user_words, entry.keywords or {})
            if ov > 0 then
                score = score + (ov * 60)
                hit = true
            end

            local sim = overlap_score(tokenize(norm), tokenize(entry.normalized or entry.question or ""))
            if sim > 0.20 then
                score = score + (sim * 35)
                hit = true
            end
        end

        if hit then
            if not best or score > best_score then
                best = entry
                best_score = score
            end
        end
    end

    if best and best_score >= 72 then
        return best.answer, best_score
    end
    return nil
end

local function answer_fact_question(text)
    local q = lower(strip_end_punct(text))
    local subject =
        q:match("^what%s+do%s+you%s+know%s+about%s+(.+)$") or
        q:match("^tell%s+me%s+about%s+(.+)$") or
        q:match("^who%s+is%s+(.+)$") or
        q:match("^what%s+is%s+(.+)$")

    if normalize(q) == "who am i" or normalize(q) == "what do you know about me" then
        subject = "user"
    end

    if subject then
        local info = facts_about(subject)
        if info then
            return info
        end
    end
    return nil
end

local function route_question(user_text)
    local norm = normalize(user_text)
    local tokens = tokenize(norm)
    local candidates = {}

    local taught, taught_score = best_taught_answer(user_text)
    if taught then
        candidates[#candidates + 1] = {
            score = taught_score,
            answer = taught
        }
    end

    local math = eval_math(user_text)
    if math then
        candidates[#candidates + 1] = {
            score = 91,
            answer = math
        }
    end

    local fact = answer_fact_question(user_text)
    if fact then
        candidates[#candidates + 1] = {
            score = 80,
            answer = fact
        }
    end

    for _, rule in ipairs(INTENTS) do
        local score = score_rule(rule, norm, tokens)
        if score then
            candidates[#candidates + 1] = {
                score = score,
                answer = rule.run(),
            }
        end
    end

    local best = nil
    for _, c in ipairs(candidates) do
        if not best or c.score > best.score then
            best = c
        end
    end

    if best then
        return best.answer
    end

    return "I know not yet. Teach me thus: :teach <question> => <answer>"
end

local function handle_command(raw)
    local cmd, rest = raw:match("^:(%S+)%s*(.*)$")
    if not cmd then
        return nil, false
    end

    cmd = lower(cmd)
    rest = trim(rest)

    if cmd == "exit" or cmd == "quit" then
        return "Fare thee well.", true
    end

    if cmd == "help" then
        return help_text(), false
    end

    if cmd == "save" then
        local ok, err = save_db(db)
        if ok then
            return "Memory is saved.", false
        end
        return "Save failed: " .. tostring(err), false
    end

    if cmd == "stats" then
        local fact_count = 0
        for _ in pairs(db.facts) do fact_count = fact_count + 1 end
        return "Interactions: " .. tostring(db.stats.interactions) ..
            ", facts: " .. tostring(fact_count) ..
            ", taught answers: " .. tostring(#db.qa) .. ".", false
    end

    if cmd == "list" then
        return list_summary(), false
    end

    if cmd == "recall" then
        if rest == "" then
            return "Format: :recall <subject>", false
        end
        local got = facts_about(rest)
        if got then
            return got, false
        end
        return "No memory of that subject.", false
    end

    if cmd == "forget" then
        return forget_memory(rest), false
    end

    if cmd == "teach" then
        local item, err = parse_teach_command(rest)
        if not item then
            return err, false
        end
        return teach_qa(item), false
    end

    return "Unknown command. Use :help", false
end

local function handle_input(input)
    local raw = trim(input)
    if raw == "" then
        return "Speak, and I shall attend thee.", false
    end

    if raw:sub(1, 1) == ":" then
        return handle_command(raw)
    end

    local plain = normalize(raw)
    if plain == "bye" or plain == "goodbye" then
        return "Fare thee well.", true
    end

    local s, r, o = parse_fact_statement(raw)
    if s and r and o then
        local ok = learn_fact(s, r, o)
        if ok then
            return pick({
                "Marked in memory.",
                "So I shall remember.",
                "The lesson is now stored.",
            }), false
        end
        return "That I knew already.", false
    end

    return route_question(raw), false
end

local function seed_rng()
    if os.epoch then
        math.randomseed(os.epoch("utc"))
    else
        math.randomseed((os.time() or 0) * 997)
    end
    math.random()
    math.random()
end

seed_rng()

term.clear()
term.setCursorPos(1, 1)
print(BOT_NAME .. " v" .. BOT_VERSION)
print("CC:Tweaked offline assistant (keywords + priorities + learning).")
print("Ask as with Siri, teach with :teach, quit with :exit.")
print("Memory loaded: facts=" .. tostring((function()
    local c = 0
    for _ in pairs(db.facts) do c = c + 1 end
    return c
end)()) .. ", taught answers=" .. tostring(#db.qa))
print("")

while true do
    write("you> ")
    local input = read()
    if input == nil then
        break
    end

    local answer, should_exit = handle_input(input)
    db.stats.interactions = db.stats.interactions + 1
    remember("user", input)
    remember("bot", answer)
    print(BOT_NAME .. "> " .. answer)

    if db.stats.interactions % 5 == 0 then
        save_db(db)
    end

    if should_exit then
        break
    end
end

local ok, err = save_db(db)
if not ok then
    print("Warning: save failed: " .. tostring(err))
end
