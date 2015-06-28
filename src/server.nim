import httpserver, sockets, tables, strutils, strtabs, times, parseopt2

type
    ServerInfo = ref object of RootObj
        guid, name, ip: string
        port: int
        timestamp: float

proc newServerInfo(guid, name, ip: string, port: int, timestamp: float): ServerInfo =
    new(result)
    result.guid = guid
    result.name = name
    result.ip = ip
    result.port = port
    result.timestamp = timestamp

var db = initTable[string, TableRef[string, ServerInfo]]()
var serversByGuid = initTable[string, ServerInfo]()

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


proc handleRequest(client: Socket, path, query, ip: string, threshold: int): bool =
    var q = queryMap(query)
    if path == "/register":
        var serverKey = q["guid"]
        var server = newServerInfo(serverKey, q["name"], ip, parseInt(q["port"]), epochTime())
        getServers(q["type"])[serverKey] = server
        serversByGuid[serverKey] = server
        echo("registering server: '$1' - $2" % [q["name"], serverKey])
        client.send("registered")
    elif path == "/update":
        var serverKey = q["guid"]
        if not serversByGuid.hasKey(serverKey):
            client.send("not registered")
        else:
            serversByGuid[serverKey].timestamp = epochTime()
            echo("updating server $1" % [serverKey])
            client.send("updated")
    elif path == "/list":
        var servers = getServers(q["type"])
        var oldKeys: seq[string] = @[]
        client.send("servers_list\n")
        for key, server in servers.pairs:
            if (epochTime() - server.timestamp) <= 10:
                client.send("$1,$2,$3,$4\n" %
                    [server.guid, server.name, server.ip, $server.port])
            else: oldKeys.add(key)
        for key in oldKeys:
            echo("removing server: " & key)
            servers.del(key)
            serversByGuid.del(key)
    elif path == "/unregister":
        var serverKey = q["guid"]
        echo("unregistering server: " & serverKey)
        getServers(q["type"]).del(serverKey)
        serversByGuid.del(serverKey)
        client.send("unregistered")
    return false


var port = Port(8090)
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
    if handleRequest(s.client, s.path, s.query, s.ip, threshold):
        break
    close(s.client)
close(s)



