#Helper Function
function Connect-ReplicationDB {
    param (
        [object]$Server,
        [object]$Database,
        [switch]$EnableException
    )

    Add-ReplicationLibrary

    $repDB = New-Object Microsoft.SqlServer.Replication.ReplicationDatabase

    $repDB.Name = $Database.Name
    $repDB.ConnectionContext = $Server.ConnectionContext

    if (-not $repDB.LoadProperties()) {
        Write-Message -Level Verbose -Message "Skipping $($Database.Name). Failed to load properties correctly."
    }

    return $repDB
}