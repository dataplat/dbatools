function Disconnect-Regserver ($Server) {
    <#
    .SYNOPSIS
        Internal function. Closes the connection behind a registered server object, but only if we opened it.

    .DESCRIPTION
        Takes any object of the registered server tree - a store, a group or a registered server - and walks up
        to the RegisteredServersStore, which is the object that holds the connection.

        The connection is only closed when Get-DbaRegServerStore opened it itself, which it records as
        IsNewConnection on the store. A connection that was handed in belongs to the caller, and closing it takes
        their session, their temp tables and their database context with it. See #10572.
    #>
    $i = 0
    while ($null -ne $Server -and $null -eq $Server.ServerConnection -and $i++ -le 20) {
        $Server = $Server.Parent
    }

    if ($Server.ServerConnection -and $Server.IsNewConnection) {
        $Server.ServerConnection.Disconnect()
    }
}
