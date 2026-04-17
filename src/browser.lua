local target = "/src/browser/main.lua"
local args = { ... }

if not fs.exists(target) then
    print("Missing file: " .. target)
    return
end

local unpackFn = table.unpack or unpack
shell.run(target, unpackFn(args))
