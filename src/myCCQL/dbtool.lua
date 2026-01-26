local Database = require "database"

local function print_help()
    print([[
Usage:
  lua dbtool.lua dump <dbfile> <sqlfile>     Dump database into SQL text file
  lua dbtool.lua import <dbfile> <sqlfile>   Import SQL text file into database
  lua dbtool.lua help                        Show this help

Notes:
  - <dbfile> is the binary .db file used by Database:save/load
  - <sqlfile> is a plain text file with SQL/CCQL commands
]])
end

local function file_exists(path)
    local f = io.open(path, "r")
    if f then f:close() return true end
    return false
end

local function dump_db(db, filename)
    local file, err = io.open(filename, "w")
    if not file then error("Cannot open " .. filename .. " for writing: " .. tostring(err)) end

    for tname, tdata in pairs(db.tables) do
        -- CREATE TABLE
        local cols = {}
        for _, col in ipairs(tdata.columns) do
            table.insert(cols, col.name .. " " .. col.type)
        end
        file:write(string.format("CREATE TABLE %s (%s);\n", tname, table.concat(cols, ", ")))

        -- INSERT INTO
        for _, row in ipairs(tdata.rows) do
            local vals = {}
            for i, col in ipairs(tdata.columns) do
                local v = row[i]
                if v == nil or v == Database.NULL then
                    table.insert(vals, "null")
                elseif col.type == "str" then
                    table.insert(vals, "'" .. tostring(v):gsub("'", "''") .. "'")
                else
                    table.insert(vals, tostring(v))
                end
            end
            file:write(string.format("INSERT INTO %s VALUES (%s);\n", tname, table.concat(vals, ", ")))
        end
        file:write("\n")
    end

    file:close()
    print("Database dumped to " .. filename)
end

local function import_db(db, filename)
    if not file_exists(filename) then
        error("SQL file not found: " .. filename)
    end

    local file = assert(io.open(filename, "r"))
    local buffer = {}
    for line in file:lines() do
        table.insert(buffer, line)
    end
    file:close()

    local sql = table.concat(buffer, "\n")
    for stmt in sql:gmatch("([^;]+);") do
        stmt = stmt:gsub("^%s+", ""):gsub("%s+$", "")
        if stmt ~= "" then
            db:execute(stmt)
        end
    end
    print("Database imported from " .. filename)
end

-- CLI
local action, dbfile, sqlfile = ...
if not action or action == "help" or action == "--help" then
    print_help()
    return
end

if action == "dump" then
    if not dbfile or not sqlfile then
        print("Missing arguments for dump\n")
        print_help()
        error()
    end
    if not file_exists(dbfile) then
        print("Database file not found: " .. dbfile)
        error()
    end
    local db = Database.new()
    db:load(dbfile)
    dump_db(db, sqlfile)

elseif action == "import" then
    if not dbfile or not sqlfile then
        print("Missing arguments for import\n")
        print_help()
        error()
    end
    local db = Database.new()
    import_db(db, sqlfile)
    db:save(dbfile)

else
    print("Unknown command: " .. tostring(action) .. "\n")
    print_help()
    error()
end
