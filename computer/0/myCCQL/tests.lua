local Database = require("database")
local DefaultTextColor = term.getTextColor()
local TestDBFile = "test.db"

local function print_colored(text, color)
    term.setTextColor(color)
    print(text)
    term.setTextColor(DefaultTextColor)
end

local function test(name, fn)
    io.write("| " .. name .. " ... ")
    term.setTextColor(colors.red)
    fn()
    print_colored("PASS", colors.green)
end

local function run_tests()
    local db = Database.new()

    if fs.exists(TestDBFile) then
        fs.delete(TestDBFile)
    end
      
    test("CREATE TABLE", function()
        db:execute("CREATE TABLE users (id u32, name str)")
        assert(db.tables["users"], "Table 'users' should exist after CREATE")
    end)

    test("INSERT INTO (explicit columns)", function()
        db:execute("INSERT INTO users (id, name) VALUES (1, 'Alice')")
        assert(#db.tables["users"].rows == 1, "Should have 1 row after insert")
    end)

    test("INSERT INTO (no columns, matches all)", function()
        db:execute("INSERT INTO users VALUES (2, 'Bob')")
        assert(#db.tables["users"].rows == 2, "Should have 2 rows after insert")
    end)

    test("SELECT *", function()
        local result = db:execute("SELECT * FROM users")
        assert(#result == 2, "SELECT * should return 2 rows")
        assert(result[1].id == 1 and result[1].name == "Alice", "First row should match Alice")
        assert(result[2].id == 2 and result[2].name == "Bob", "Second row should match Bob")
    end)

    test("SELECT specific column with WHERE", function()
        local result2 = db:execute("SELECT name FROM users WHERE id=2")
        assert(#result2 == 1, "WHERE id=2 should return 1 row")
        assert(result2[1].name == "Bob", "Row should contain Bob")
    end)

    test("DELETE specific row", function()
        db:execute("DELETE FROM users WHERE id=1")
        assert(#db.tables["users"].rows == 1, "Should have 1 row after DELETE WHERE")
        assert(db.tables["users"].rows[1][1] == 2, "Remaining row should have id=2")
    end)

    test("DELETE all rows", function()
        db:execute("DELETE FROM users")
        assert(#db.tables["users"].rows == 0, "Should have 0 rows after DELETE without WHERE")
    end)

    test("DROP TABLE", function()
        db:execute("DROP TABLE users")
        assert(db.tables["users"] == nil, "Table 'users' should not exist after DROP")
    end)

    test("TRUNCATE TABLE", function()
        db:execute("CREATE TABLE logs (id u32, message str)")
        db:execute("INSERT INTO logs VALUES (1, 'First')")
        db:execute("INSERT INTO logs VALUES (2, 'Second')")
        assert(#db.tables["logs"].rows == 2, "Should have 2 rows before TRUNCATE")

        db:execute("TRUNCATE TABLE logs")
        assert(#db.tables["logs"].rows == 0, "Should have 0 rows after TRUNCATE")
        assert(db.tables["logs"].columns[1].name == "id", "Table structure should remain intact")
    end)

    test("SHOW TABLES", function()
        local tabledb = Database.new()
        tabledb:execute("CREATE TABLE customers (id u32, name str)")
        tabledb:execute("CREATE TABLE orders (id u32, product str)")

        local result = tabledb:execute("SHOW TABLES")
        local names = {}
        for _, row in ipairs(result) do
            table.insert(names, row.table_name)
        end

        assert(#names == 2, "Should list 2 tables")
        assert(table.concat(names, ", "):match("customers"), "Should include 'customers'")
        assert(table.concat(names, ", "):match("orders"), "Should include 'orders'")
    end)

    test("DESCRIBE TABLE", function()
        db:execute("CREATE TABLE accounts (id u32, username str)")

        local result = db:execute("DESCRIBE accounts")
        assert(#result == 2, "Should return 2 columns")
        assert(result[1].Field == "id" and result[1].Type == "u32", "First column should be id u32")
        assert(result[2].Field == "username" and result[2].Type == "str", "Second column should be username str")
    end)

    test("ALTER TABLE add/drop/rename/alter columns", function()
        db:execute("CREATE TABLE items (id u32, name str)")
        db:execute("ALTER TABLE items ADD COLUMN price u16")
        assert(db:get_column_index("items", "price"), "Column 'price' should exist")

        db:execute("ALTER TABLE items RENAME COLUMN price TO cost")
        assert(db:get_column_index("items", "cost"), "Column should be renamed to 'cost'")

        db:execute("ALTER TABLE items ALTER COLUMN cost TYPE str")
        local idx = db:get_column_index("items", "cost")
        assert(db.tables["items"].columns[idx].type == "str", "Column 'cost' type should now be str")

        db:execute("ALTER TABLE items DROP COLUMN cost")
        assert(not db:get_column_index("items", "cost"), "Column 'cost' should be dropped")
    end)

    test("RENAME TABLE", function()
        db:execute("CREATE TABLE tmp (id u32)")
        db:execute("RENAME TABLE tmp TO real_items;")

        assert(db.tables["tmp"] == nil, "Old name 'tmp' should be gone")
        assert(db.tables["real_items"], "New table 'real_items' should exist")
    end)

    test("SAVE + LOAD roundtrip", function()
        db:execute("CREATE TABLE products (id u16, title str)")
        db:execute("INSERT INTO products (id, title) VALUES (10, 'Keyboard')")
        db:execute("INSERT INTO products (id, title) VALUES (20, 'Mouse')")

        db:save(TestDBFile)

        local db2 = Database.new()
        db2:load(TestDBFile)

        assert(db2.tables["products"], "Table 'products' should exist after load")
        local result3 = db2:execute("SELECT * FROM products")
        assert(#result3 == 2, "Loaded table should have 2 rows")
        assert(result3[1].title == "Keyboard", "First loaded row should be Keyboard")
        assert(result3[2].title == "Mouse", "Second loaded row should be Mouse")
    end)
end

run_tests()
