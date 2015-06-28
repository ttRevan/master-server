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
    client.send("HTTP/1.1 200 OK\n")
    client.send("Content-Type: text/plain; charset=UTF-8\n")
    var q = queryMap(query)
    var response = ""
    if path == "/register":
        var serverKey = q["guid"]
        var server = newServerInfo(serverKey, q["name"], ip, parseInt(q["port"]), epochTime())
        getServers(q["type"])[serverKey] = server
        serversByGuid[serverKey] = server
        echo("registering server: '$1' - $2" % [q["name"], serverKey])
        response.add("registered")
    elif path == "/update":
        var serverKey = q["guid"]
        if not serversByGuid.hasKey(serverKey):
            response.add("not registered")
        else:
            serversByGuid[serverKey].timestamp = epochTime()
            echo("updating server $1" % [serverKey])
            response.add("updated")
    elif path == "/list":
        var servers = getServers(q["type"])
        var oldKeys: seq[string] = @[]
        response.add("servers_list\n")
        for key, server in servers.pairs:
            if (epochTime() - server.timestamp) <= 10:
                response.add("$1,$2,$3,$4\n" %
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
        response.add("unregistered")
    client.send("Content-Length: " & $len(response) & "\n\n")
    client.send(response)
    return false


var port = Port(8090)
var threshold = 15
var localIpMapping: string

for kind, key, val in getopt():
    case kind
    of cmdShortOption, cmdLongOption:
        if key == "p" or key == "port":
            port = Port(parseInt(val))
        elif key == "t" or key == "threshold":
            threshold = parseInt(val)
        elif key == "m" or key == "map-local":
            localIpMapping = val
    else: discard

var s: TServer
open(s, port, reuseAddr = true)
while true:
    next(s)
    var ip = s.ip
    if ip == "127.0.0.1" and localIpMapping != nil:
        ip = localIpMapping
    if handleRequest(s.client, s.path, s.query, ip, threshold):
        break
    close(s.client)
close(s)



