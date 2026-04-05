local target = "/src/browser/main.lua"

if not fs.exists(target) then
    print("Missing file: " .. target)
    return
end

shell.run(target)
