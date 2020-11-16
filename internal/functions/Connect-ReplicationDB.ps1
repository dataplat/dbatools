#Helper Function
function Connect-ReplicationDB {
    param (
        [object]$Server,
        [object]$Database,
        [switch]$EnableException
    )

    try {
        Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.Replication.dll" -ErrorAction Stop
        Add-Type -Path "$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.Rmo.dll" -ErrorAction Stop
    } catch {
        $repdll = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Replication")
        $rmodll = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Rmo")

        if ($null -eq $repdll -or $null -eq $rmodll) {
            Stop-Function -Message "Could not load replication libraries" -ErrorRecord $_
            return
        }
    }

    $repDB = New-Object Microsoft.SqlServer.Replication.ReplicationDatabase

    $repDB.Name = $Database.Name
    $repDB.ConnectionContext = $Server.ConnectionContext.SqlConnectionObject

    if (!$repDB.LoadProperties()) {
        Write-Message -Level Verbose -Message "Skipping $($Database.Name). Failed to load properties correctly."
    }

    return $repDB
}