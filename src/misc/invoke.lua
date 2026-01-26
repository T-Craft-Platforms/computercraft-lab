args = {...};
cmd = '';

for k,v in pairs(args) do
    cmd = cmd .. v .. ' ';
end

print('Executing: ' .. cmd);

assert(loadstring(cmd))();