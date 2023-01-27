function Disconnect-Regserver ($Server) {
    $i = 0
    do { $server = $server.Parent }
    until ($null -ne $server.ServerConnection -or $i++ -gt 20)
    if ($server.ServerConnection) {
        $server.ServerConnection.Disconnect()
    }
}