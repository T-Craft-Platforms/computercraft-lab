local args = { ... };

local min;
if args[1] then
    min = tonumber(args[1]);
else
    write("Min: ");
    min = read();
    write("\n");
end

local max;
if args[2] then
    max = tonumber(args[2]);
else
    write("Max: ");
    max = read();
    write("\n");
end

print(math.random(min, max));