#Helper Function
function Connect-ReplicationDB {
    param (
        [object]$Server,
        [object]$Database
    )

    $repDB = New-Object Microsoft.SqlServer.Replication.ReplicationDatabase

    $repDB.Name = $Database.Name
    $repDB.ConnectionContext = $Server.ConnectionContext.SqlConnectionObject

    if (!$repDB.LoadProperties()) {
        Write-Message -Level Verbose -Message "Skipping $($Database.Name). Failed to load properties correctly."
    }

    return $repDB
}