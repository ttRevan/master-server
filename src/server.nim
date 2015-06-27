import httpserver, sockets, tables, strutils, strtabs, times, parseopt2

type
    ServerInfo = ref object of RootObj
        name, ip: string
        port: int
        timestamp: float

proc newServerInfo(name, ip: string, port: int, timestamp: float): ServerInfo =
    new(result)
    result.name = name
    result.ip = ip
    result.port = port
    result.timestamp = timestamp

var db = initTable[string, TableRef[string, ServerInfo]]()

proc getServers(key: string): TableRef[string, ServerInfo] =
    result = db[key]
    if result == nil:
        result = newTable[string, ServerInfo]()
        db[key] = result


proc queryMap(query: string): StringTableRef =
    result = newStringTable(modeCaseSensitive)
    for param in query.split('&'):
        var key = param[0..param.find('=') - 1]
        var value = param[param.find('=') + 1..len(param) - 1]
        result[key] = value


proc handleRequest(client: Socket, path, query, ip: string, port, threshold: int): bool =
    var q = queryMap(query)
    var serverKey = ip & $port
    if path == "/register":
        var servers = getServers(q["type"])
        if servers.hasKey(serverKey):
            var server = servers[serverKey]
            server.timestamp = epochTime()
            server.name = q["name"]
            echo("updating server: ", serverKey)
        else:
            servers[serverKey] = newServerInfo(q["name"], ip, port, epochTime())
            echo("registering server: ", serverKey)
            client.send("registered " & serverKey)
    elif path == "/list":
        var servers = getServers(q["type"])
        var oldKeys: seq[string] = @[]
        client.send("servers_list\n")
        for key, server in servers.pairs:
            if (epochTime() - server.timestamp) <= 10:
                client.send("$1,$2,$3\n" % [server.name, server.ip, $server.port])
            else:
                oldKeys.add(key)
        for key in oldKeys:
            echo("removing server: ", key)
            servers.del(key)
    elif path == "/unregister":
        getServers(q["type"]).del(serverKey)
        client.send("unregistered " & serverKey)
    return false


var port = Port(8080)
var threshold = 15
for kind, key, val in getopt():
    case kind
    of cmdShortOption, cmdLongOption:
        if key == "p" or key == "port":
            port = Port(parseInt(val))
        elif key == "t" or key == "threshold":
            threshold = parseInt(val)
    else: discard

var s: TServer
open(s, port, reuseAddr = true)
while true:
    next(s)
    var port = int(s.client.getSockName())
    if handleRequest(s.client, s.path, s.query, s.ip, port, threshold):
        break
    close(s.client)
close(s)



