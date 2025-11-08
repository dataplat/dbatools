function Get-DbaDbPhysicalFile {
    <#
    .SYNOPSIS
    Gets raw information about physical files linked to databases

    .DESCRIPTION
    Fastest way to fetch just the paths of the physical files for every database on the instance, also for offline databases.
    Incidentally, it also fetches the paths for MMO and FS filegroups.
    This is partly already in Get-DbaDbFile, but this internal needs to stay lean and fast, as it's heavily used in top-level functions

    .PARAMETER SqlInstance
    SMO object representing the SQL Server to connect to.

    .EXAMPLE
    Get-DbaDbPhysicalFile -SqlInstance server1\instance2

    .NOTES
        Author: Simone Bizzotto

        dbatools PowerShell module (https://dbatools.io)
       Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT
    #>
    [CmdletBinding()]
    param(
        [parameter(Mandatory)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]
        $SqlCredential
    )
    try {
        $server = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
    } catch {
        Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance
        return
    }
    if ($server.versionMajor -le 8) {
        $sql = "SELECT DB_NAME(dbid) AS name, Name AS LogicalName, filename AS PhysicalName, type FROM sys.sysaltfiles"
    } else {
        $sql = "SELECT DB_NAME(database_id) AS Name, name AS LogicalName, physical_name AS PhysicalName, type FROM sys.master_files"
    }
    Write-Message -Level Debug -Message "$sql"
    try {
        $server.Query($sql)
    } catch {
        throw "Error enumerating files"
    }
}