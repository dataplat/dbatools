function Get-OfflineSqlFileStructure {
    <#
.SYNOPSIS
Internal function. Returns dictionary object that contains file structures for SQL databases.

    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [object]$SqlInstance,
        [Parameter(Mandatory, Position = 1)]
        [string]$DbName,
        [Parameter(Mandatory, Position = 2)]
        [object]$filelist,
        [Parameter(Position = 3)]
        [bool]$ReuseSourceFolderStructure,
        [PSCredential]$SqlCredential
    )

    $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential

    $destinationfiles = @{ };
    $logfiles = $filelist | Where-Object { $_.Type -eq "L" }
    $datafiles = $filelist | Where-Object { $_.Type -ne "L" }
    $filestream = $filelist | Where-Object { $_.Type -eq "S" }

    if ($filestream) {
        $sql = "select coalesce(SERVERPROPERTY('FilestreamConfiguredLevel'),0) as fs"
        $fscheck = $server.databases['master'].ExecuteWithResults($sql)
        if ($fscheck.tables.fs -eq 0) { return $false }
    }

    # Data Files
    foreach ($file in $datafiles) {
        # Destination File Structure
        $d = @{ }
        if ($ReuseSourceFolderStructure -eq $true) {
            $d.physical = $file.PhysicalName
        } else {
            $directory = Get-SqlDefaultPaths $server data
            $filename = Split-Path $($file.PhysicalName) -leaf
            $d.physical = "$directory\$filename"
        }

        $d.logical = $file.LogicalName
        $destinationfiles.add($file.LogicalName, $d)
    }

    # Log Files
    foreach ($file in $logfiles) {
        $d = @{ }
        if ($ReuseSourceFolderStructure) {
            $d.physical = $file.PhysicalName
        } else {
            $directory = Get-SqlDefaultPaths $server log
            $filename = Split-Path $($file.PhysicalName) -leaf
            $d.physical = "$directory\$filename"
        }

        $d.logical = $file.LogicalName
        $destinationfiles.add($file.LogicalName, $d)
    }

    return $destinationfiles
}