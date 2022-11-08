function Add-ReplicationLibrary {
    param(
        [switch]$EnableException
    )
    try {
        $platformlib = Join-DbaPath -Path $script:libraryroot -ChildPath lib
        $repdll = Join-DbaPath -Path $platformlib -ChildPath Microsoft.SqlServer.Replication.dll
        $rmodll = Join-DbaPath -Path $platformlib -ChildPath Microsoft.SqlServer.Rmo.dll
        Add-Type -Path $rmodll -ErrorAction Stop
        Add-Type -Path $repdll -ErrorAction Stop
    } catch {
        Stop-Function -Message "Could not load replication libraries. Replication is very challenging to support. We recommend running theses commands from a machine that does not have SQL Server installed."
        return
    }
}