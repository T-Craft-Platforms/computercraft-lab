args = { ... };
repeatNo = 3;

if args[2] then
    repeatNo = args[2];
end

if not string.find(args[1], "://") then
	args[1] = "http://"..args[1];
end

success = 0;
timeTotal = 0;

for i=1, repeatNo, 1 do
    local start = os.clock();
    local result = http.get(args[1]);
    if result then
        local timeElapsed = math.floor((os.clock() - start) * 100);
        print("Response from " .. args[1] .. ": Time=" .. timeElapsed .. ' ms');
        success = success + 1;
        timeTotal = timeTotal + timeElapsed;
    else
        print("Ping failed!")
    end
end

print("\nSent = " .. repeatNo .. ", Received = " .. success .. ", Lost = " .. repeatNo - success .. ", Avg = " .. timeTotal / success);