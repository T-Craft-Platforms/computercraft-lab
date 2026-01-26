local Database = require "database"

local function print_help()
    print([[
Commands:
  load mem:<name>             Create in-memory DB with given name
  load file:<path>|<path>     Load DB from file (name = filename without extension)
  save <name> <file>          Save DB with given name to file
  unload <name>               Unload DB by name
  switch <name>               Switch active DB
  list                        List all loaded DBs (* = active)
  query <sql>                 Execute SQL/CCQL statement on active DB
  exit                        Quit client
  help                        Show this help
]])
end

local function print_result(result)
    if type(result) ~= "table" then
        print(tostring(result))
        return
    end
    for _, row in ipairs(result) do
        local out = {}
        for k, v in pairs(row) do
            table.insert(out, tostring(k) .. ":" .. tostring(v))
        end
        print(table.concat(out, ", "))
    end
end

-- State
local databases = {}
local current_db_name = "default"
databases[current_db_name] = Database.new()

print("myCCQL Terminal Client")
print("Type 'help' for commands")

while true do
    io.write("> ")
    local line = io.read("*l")
    if not line then break end
    local cmd, rest = line:match("^(%S+)%s*(.*)$")
    if not cmd then goto continue end

    if cmd == "help" then
        print_help()

    elseif cmd == "exit" then
        print("Exiting...")
        break

    elseif cmd == "load" then
        if rest == "" then
            print("Usage: load mem:<name> | file:<path> | <path>")
        else
            local name
            if rest:match("^mem:") then
                name = rest:match("^mem:(.+)")
                if not name then
                    print("Invalid mem: syntax")
                elseif databases[name] then
                    print("Database with name '"..name.."' already exists")
                else
                    databases[name] = Database.new()
                    current_db_name = name
                    print("Created in-memory DB '"..name.."'")
                    print("Switched to DB '"..name.."'")
                end
            else
                local path = rest:gsub("^file:", "")
                name = path:match("([^/\\]+)%.%w+$") or path
                if databases[name] then
                    print("Database with name '"..name.."' already exists")
                else
                    local db = Database.new()
                    local ok, err = pcall(function() db:load(path) end)
                    if ok then
                        databases[name] = db
                        current_db_name = name
                        print("Database '"..name.."' loaded from " .. path)
                        print("Switched to DB '"..name.."'")
                    else
                        print("Error: " .. err)
                    end
                end
            end
        end

    elseif cmd == "save" then
        local dbname, path = rest:match("^(%S+)%s+(%S+)$")
        if not dbname or not path then
            print("Usage: save <name> <file>")
        elseif not databases[dbname] then
            print("Database '"..dbname.."' not loaded")
        else
            local ok, err = pcall(function() databases[dbname]:save(path) end)
            if ok then
                print("Database '"..dbname.."' saved to " .. path)
            else
                print("Error: " .. err)
            end
        end

    elseif cmd == "unload" then
        if rest == "" then
            print("Usage: unload <name>")
        elseif not databases[rest] then
            print("Database '"..rest.."' not loaded")
        else
            databases[rest] = nil
            if current_db_name == rest then
                current_db_name = "default"
            end
            print("Database '"..rest.."' unloaded")
        end

    elseif cmd == "switch" then
        if rest == "" then
            print("Usage: switch <name>")
        elseif not databases[rest] then
            print("Database '"..rest.."' not loaded")
        else
            current_db_name = rest
            print("Switched to DB '"..rest.."'")
        end

    elseif cmd == "list" then
        print("Loaded databases:")
        for name, _ in pairs(databases) do
            local marker = (name == current_db_name) and "*" or " "
            print(marker .. " " .. name)
        end

    elseif cmd == "query" then
        local db = databases[current_db_name]
        if not db then
            print("No active database")
        elseif rest == "" then
            print("Usage: query <sql>")
        else
            local ok, result = pcall(function() return db:execute(rest) end)
            if ok then
                if result then
                    print_result(result)
                else
                    print("OK")
                end
            else
                print("Error: " .. result)
            end
        end

    elseif cmd == "queryg" then
    local db = databases[current_db_name]
    if not db then
        print("No active database")
    elseif rest == "" then
        print("Usage: queryg <sql>")
    else
        local ok, result = pcall(function() return db:execute(rest) end)
        if not ok then
            print("Error: " .. result)
        elseif not result or #result == 0 then
            print("No results")
        else
            -- Open GUI table view
            local w, h = term.getSize()
            term.clear()
            term.setCursorPos(1,1)
            term.setTextColor(colors.white)
            term.setBackgroundColor(colors.black)

            -- Collect columns
            local columns = {}
            for k,_ in pairs(result[1]) do table.insert(columns, k) end
            table.sort(columns)

            local function drawTable(offset)
                term.clear()
                term.setCursorPos(1,1)
                term.setTextColor(colors.yellow)
                term.write(table.concat(columns, " | "))
                term.setTextColor(colors.white)
                local y = 2
                for i = offset+1, math.min(offset+h-2, #result) do
                    local row = result[i]
                    term.setCursorPos(1,y)
                    local line = {}
                    for _,col in ipairs(columns) do
                        table.insert(line, tostring(row[col] or ""))
                    end
                    term.write(table.concat(line, " | "))
                    y = y+1
                end
                term.setCursorPos(w-3,1)
                term.setTextColor(colors.red)
                term.write("[X]") -- close button
                term.setTextColor(colors.white)
            end

            local offset = 0
            drawTable(offset)

            while true do
                local e, p1, p2, p3 = os.pullEvent()
                if e == "key" then
                    if p1 == keys.q then break end
                    if p1 == keys.up and offset > 0 then
                        offset = offset - 1
                        drawTable(offset)
                    elseif p1 == keys.down and offset < #result-h+2 then
                        offset = offset + 1
                        drawTable(offset)
                    end
                elseif e == "mouse_click" then
                    -- click [X]
                    if p2 >= w-3 and p2 <= w and p3 == 1 then
                        break
                    end
                elseif e == "mouse_scroll" then
                    if p1 == -1 and offset > 0 then
                        offset = offset - 1
                        drawTable(offset)
                    elseif p1 == 1 and offset < #result-h+2 then
                        offset = offset + 1
                        drawTable(offset)
                    end
                end
            end

            term.clear()
            term.setCursorPos(1,1)
            print("Back to client. Type 'help' for commands.")
        end
    end


    else
        print("Unknown command: " .. cmd .. " (type 'help')")
    end

    ::continue::
end
