os.loadAPI("json");

local result = http.get("https://api.chucknorris.io/jokes/random");
print(json.decode(result.readAll())["value"]);
result.close();