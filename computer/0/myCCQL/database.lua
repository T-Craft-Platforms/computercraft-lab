local NULL = setmetatable({}, {
    __tostring = function() return "null" end
})

local magic_number = 0xCCDB

local Database = {}
Database.__index = Database

local type_defs = {
    { name = "u8",  id = 0x01, size = 1, signed = false },
    { name = "u16", id = 0x02, size = 2, signed = false },
    { name = "u32", id = 0x03, size = 4, signed = false },
    { name = "s8",  id = 0x04, size = 1, signed = true  },
    { name = "s16", id = 0x05, size = 2, signed = true  },
    { name = "s32", id = 0x06, size = 4, signed = true  },
}
local write_types = {}
local read_types = {
    [0x10] = { name = "string" },
    [0x11] = { name = "null" },
}

for _, def in ipairs(type_defs) do
    write_types[def.name] = {
        id = def.id,
        size = def.size,
        signed = def.signed
    }
    read_types[def.id] = {
        name = def.name,
        size = def.size,
        signed = def.signed
    }
end

local function to_twos_complement(value, bits)
    if value < 0 then
        return value + 2^bits
    else
        return value
    end
end
local function from_twos_complement(value, bits)
    local max_unsigned = 2^bits
    local max_signed = 2^(bits - 1)
    if value >= max_signed then
        return value - max_unsigned
    else
        return value
    end
end
local function write_string(file, str)
    file:write(string.char(0x10))
    file:write(str)
    file:write('\0')
end
local function write_integer(file, typename, value)
    local typeinfo = write_types[typename]
    if not typeinfo then error("Unknown type: " .. tostring(typename)) end

    file:write(typeinfo.id)

    local bits = typeinfo.size * 8
    if typeinfo.signed then
        value = to_twos_complement(value, bits)
    end
    for i = typeinfo.size - 1, 0, -1 do
        local byte = bit.band(bit.brshift(value, i * 8), 0xFF)
        file:write(byte)
    end
end
local function read_integer(file, typeinfo)
    local raw = file:read(typeinfo.size)
    if not raw or #raw ~= typeinfo.size then
        return nil, "Unexpected EOF while reading " .. typeinfo.name
    end

    local value = 0
    for i = 1, typeinfo.size do
        value = bit.blshift(value, 8) + raw:byte(i)
    end

    if typeinfo.signed then
        value = from_twos_complement(value, typeinfo.size * 8)
    end

    return value, typeinfo.name
end

local function read_value(file)
    local type_id = file:read(1)
    if not type_id then return nil, "EOF" end
    local typeinfo = read_types[type_id:byte()]
    if not typeinfo then return nil, "Unknown type ID: " .. tostring(type_id) end

    if typeinfo.name == "string" then
        local chars = {}
        while true do
            local c = file:read(1)
            if not c or c == '\0' then break end
            table.insert(chars, c)
        end
        return table.concat(chars), "string"
    elseif typeinfo.name == "null" then
        return NULL
    else
        return read_integer(file, typeinfo)
    end
end

function Database:save(filename)
    local file = assert(io.open(filename, "wb"))
    file:write(string.char(
        bit.brshift(magic_number, 8),
        bit.band(magic_number, 0xFF)
    ))
    local tblCount = 0
    for _ in pairs(self.tables) do tblCount = tblCount + 1 end
    write_integer(file, "u16", tblCount)
    for name, table in pairs(self.tables) do
        write_string(file, name)
        write_integer(file, "u16", #table.columns)
        for _, col in ipairs(table.columns) do
            write_string(file, col.name)
            write_string(file, col.type)
        end
        write_integer(file, "u16", #table.rows)
        for _, row in ipairs(table.rows) do
            for i, col in ipairs(table.columns) do
                local val = row[i]
                if val == NULL then
                    file:write(0x11)
                elseif col.type == "str" then
                    write_string(file, val)
                else
                    write_integer(file, col.type, val)
                end
            end
        end
    end
    file:close()
end

function Database:load(filename)
    local file = io.open(filename, "rb")
    if not file then return end
    local magic = read_integer(file, read_types[0x02])
    if magic ~= magic_number then file:close() error("Invalid Format", 2) end
    local tableCount = read_value(file)
    for _ = 1, tableCount do
        local name = read_value(file)
        local colCount = read_value(file)
        local columns = {}
        for _ = 1, colCount do
            local cname = read_value(file)
            local ctype = read_value(file)
            table.insert(columns, { name = cname, type = ctype })
        end
        local rowCount = read_value(file)
        local rows = {}
        for _ = 1, rowCount do
            local row = {}
            for i, col in ipairs(columns) do
                local val, type = read_value(file)
                table.insert(row, val)
            end
            table.insert(rows, row)
        end
        self.tables[name] = { columns = columns, rows = rows }
    end
    file:close()
end

--[[ Query Parser ]]--
-- TODO: Write a better parser

local function parse_conditions(clause)
    local conditions = {}
    for cond in clause:gmatch("[^%s]+%s*=%s*[^%s]+") do
        local col, val = cond:match("(%w+)%s*=%s*([%w\']+)")
        if not col or not val then error("Invalid condition: " .. tostring(cond)) end
        val = val:gsub("^'", ""):gsub("'$", "")
        table.insert(conditions, { col = col, val = val })
    end
    return conditions
end

local function row_matches_conditions(row, table_data, conditions, get_column_index)
    for _, cond in ipairs(conditions) do
        local col_index = get_column_index(table_data.name, cond.col)
        if not col_index then error("Invalid column in WHERE clause: " .. cond.col) end
        if tostring(row[col_index]) ~= cond.val then
            return false
        end
    end
    return true
end

function Database:get_column_index(table_name, col_name)
    local columns = self.tables[table_name].columns
    for i, col in ipairs(columns) do
        if col.name == col_name then
            return i
        end
    end
    return nil
end

function Database:parse_create(query)
    local table_name, columns_str = query:match("CREATE TABLE%s+(%w+)%s*%((.-)%)")
    if not table_name or not columns_str then
        error("Invalid CREATE TABLE syntax.")
    end

    if self.tables[table_name] then
        error("Table '" .. table_name .. "' already exists.")
    end

    local columns = {}
    for col_def in columns_str:gmatch("[^,]+") do
        local col_name, col_type = col_def:match("(%w+)%s+(%w+)")
        if not col_name or not col_type then
            error("Invalid column definition: " .. tostring(col_def))
        end

        if col_type ~= "str" and not write_types[col_type] then
            error("Unknown column type: " .. col_type)
        end

        table.insert(columns, { name = col_name, type = col_type })
    end

    self.tables[table_name] = {
        columns = columns,
        rows = {}
    }
end


function Database:parse_select(query)
    local select_clause = query:match("SELECT%s+(.+)%s+FROM")
    local from_clause = query:match("FROM%s+(%w+)")
    local where_clause = query:match("WHERE%s+(.+);?$")

    local result = {}
    local table_data = self.tables[from_clause]
    if not table_data then
        error("Table '" .. from_clause .. "' not found.")
    end

    if not (select_clause and from_clause) then
        error("Invalid SELECT query.")
    end

    local columns = {}
    if select_clause:match("^%*%s*$") then
        for _, col in ipairs(table_data.columns) do
            table.insert(columns, col.name)
        end
    else
        for col in select_clause:gmatch("[^,%s]+") do
            table.insert(columns, col)
        end
    end

    local conditions = {}
    if where_clause then
        conditions = parse_conditions(where_clause)
    end

    for _, row in ipairs(table_data.rows) do
        if #conditions == 0 or row_matches_conditions(row, { name = from_clause, columns = table_data.columns }, conditions, function(tbl, col)
            return self:get_column_index(tbl, col)
        end) then
            local result_row = {}
            for _, col_name in ipairs(columns) do
                local col_index = self:get_column_index(from_clause, col_name)
                if not col_index then error("Invalid column: " .. col_name) end
                result_row[col_name] = row[col_index]
            end
            table.insert(result, result_row)
        end
    end

    return result
end
function Database:parse_insert(query)
    local table_name = query:match("INSERT INTO%s+(%w+)")
    local columns_part = query:match("INSERT INTO%s+%w+%s*%((.-)%)")
    local values_part = query:match("VALUES%s*%((.-)%)")

    if not (table_name and values_part) then
        error("Invalid INSERT query.")
    end

    local table_data = self.tables[table_name]
    if not table_data then
        error("Table '" .. table_name .. "' not found.")
    end

    local values = {}
    for val in values_part:gmatch("[^,%s]+") do
        val = val:gsub("^\'", ""):gsub("\'$", "")
        if tonumber(val) then
            table.insert(values, tonumber(val))
        else
            table.insert(values, val)
        end
    end

    local columns = {}
    if columns_part then
        for col in columns_part:gmatch("[^,%s]+") do
            table.insert(columns, col)
        end
        if #columns ~= #values then
            error("Number of columns and values do not match.")
        end
    else
        if #values ~= #table_data.columns then
            error("Number of values does not match table column count and no columns were specified.")
        end
        for _, col in ipairs(table_data.columns) do
            table.insert(columns, col.name)
        end
    end

    local new_row = {}
    for _ = 1, #table_data.columns do table.insert(new_row, NULL) end

    for i, col_name in ipairs(columns) do
        local col_index = self:get_column_index(table_name, col_name)
        if not col_index then
            error("Invalid column: " .. col_name)
        end
        new_row[col_index] = values[i]
    end

    table.insert(table_data.rows, new_row)
end

function Database:parse_delete(query)
    local table_name = query:match("DELETE FROM%s+(%w+)")
    local where_clause = query:match("WHERE%s+(.+);?$")

    if not table_name then
        error("Invalid DELETE query.")
    end

    local table_data = self.tables[table_name]
    if not table_data then
        error("Table '" .. table_name .. "' not found.")
    end
    if not where_clause then
        table_data.rows = {}
        return
    end

    local conditions = parse_conditions(where_clause)

    local new_rows = {}
    for _, row in ipairs(table_data.rows) do
        if not row_matches_conditions(row, { name = table_name, columns = table_data.columns }, conditions, function(tbl, col)
            return self:get_column_index(tbl, col)
        end) then
            table.insert(new_rows, row)
        end
    end
    table_data.rows = new_rows
end

function Database:parse_drop(query)
    local table_name = query:match("DROP TABLE%s+(%w+);?$")
    if not table_name then
        error("Invalid DROP query.")
    end

    if not self.tables[table_name] then
        error("Table '" .. table_name .. "' not found.")
    end

    self.tables[table_name] = nil
end

function Database:parse_truncate(query)
    local table_name = query:match("TRUNCATE TABLE%s+(%w+);?$")
    if not table_name then
        error("Invalid TRUNCATE query.")
    end

    local table_data = self.tables[table_name]
    if not table_data then
        error("Table '" .. table_name .. "' not found.")
    end

    table_data.rows = {}
end

function Database:parse_show(query)
    if not query:match("^SHOW%s+TABLES;?$") then
        error("Invalid SHOW TABLES query.")
    end

    local result = {}
    for name, _ in pairs(self.tables) do
        table.insert(result, { table_name = name })
    end

    return result
end

function Database:parse_describe(query)
    local table_name = query:match("^DESCRIBE%s+(%w+);?$")
    if not table_name then
        table_name = query:match("^DESC%s+(%w+);?$")
    end
    if not table_name then
        error("Invalid DESCRIBE query.")
    end

    local table_data = self.tables[table_name]
    if not table_data then
        error("Table '" .. table_name .. "' not found.")
    end

    local result = {}
    for _, col in ipairs(table_data.columns) do
        table.insert(result, { Field = col.name, Type = col.type })
    end
    return result
end

function Database:parse_alter(query)
    local table_name = query:match("^ALTER TABLE%s+(%w+)")
    if not table_name then
        error("Invalid ALTER TABLE syntax")
    end

    local table_data = self.tables[table_name]
    if not table_data then
        error("Table '" .. table_name .. "' not found")
    end

    -- ADD COLUMN
    local col_name, col_type = query:match("ADD COLUMN%s+(%w+)%s+(%w+)")
    if col_name and col_type then
        if col_type ~= "str" and not write_types[col_type] then
            error("Unknown column type: " .. col_type)
        end
        table.insert(table_data.columns, { name = col_name, type = col_type })
        for _, row in ipairs(table_data.rows) do
            table.insert(row, NULL) -- default NULL for new col
        end
        return
    end

    -- DROP COLUMN
    local drop_col = query:match("DROP COLUMN%s+(%w+)")
    if drop_col then
        local idx = self:get_column_index(table_name, drop_col)
        if not idx then error("Column '"..drop_col.."' not found") end
        table.remove(table_data.columns, idx)
        for _, row in ipairs(table_data.rows) do
            table.remove(row, idx)
        end
        return
    end

    -- RENAME COLUMN
    local old_col, new_col = query:match("RENAME COLUMN%s+(%w+)%s+TO%s+(%w+)")
    if old_col and new_col then
        local idx = self:get_column_index(table_name, old_col)
        if not idx then error("Column '"..old_col.."' not found") end
        table_data.columns[idx].name = new_col
        return
    end

    -- ALTER COLUMN TYPE
    local col, new_type = query:match("ALTER COLUMN%s+(%w+)%s+TYPE%s+(%w+)")
    if col and new_type then
        if new_type ~= "str" and not write_types[new_type] then
            error("Unknown column type: " .. new_type)
        end
        local idx = self:get_column_index(table_name, col)
        if not idx then error("Column '"..col.."' not found") end
        table_data.columns[idx].type = new_type
        return
    end

    error("Unsupported ALTER TABLE operation")
end

function Database:parse_rename(query)
    local old_name, new_name = query:match("^RENAME TABLE%s+([%w_]+)%s+TO%s+([%w_]+);?$")
    if not old_name or not new_name then
        error("Invalid RENAME TABLE syntax")
    end

    if not self.tables[old_name] then
        error("Table '"..old_name.."' not found")
    end
    if self.tables[new_name] then
        error("Table '"..new_name.."' already exists")
    end

    self.tables[new_name] = self.tables[old_name]
    self.tables[old_name] = nil
end

function Database:execute(query)
    local command = query:match("^(%w+)")
    if not command then error("Empty query") end

    command = command:upper()
    if command == "CREATE" then
        self:parse_create(query)
    elseif command == "SELECT" then
        return self:parse_select(query)
    elseif command == "INSERT" then
        self:parse_insert(query)
    elseif command == "DELETE" then
        self:parse_delete(query)
    elseif command == "DROP" then
        self:parse_drop(query)
    elseif command == "TRUNCATE" then
        self:parse_truncate(query)
    elseif command == "SHOW" then
        return self:parse_show(query)
    elseif command == "DESCRIBE" or command == "DESC" then
        return self:parse_describe(query)
    elseif command == "ALTER" then
        self:parse_alter(query)
    elseif command == "RENAME" then
        self:parse_rename(query)
    else
        error("Unsupported command: " .. command)
    end
end

function Database.new()
    return setmetatable({
        tables = {}
    }, Database)
end

return Database
