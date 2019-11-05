function Get-XpDirTreeRestoreFile {
    <#
    .SYNOPSIS
        Internal Function to get SQL Server backfiles from a specified folder using xp_dirtree

    .DESCRIPTION
        Takes path, checks for validity. Scans for usual backup file

    .PARAMETER Path
        The path to retrieve the restore for.

    .PARAMETER SqlInstance
        The SQL Server that you're connecting to.

    .PARAMETER SqlCredential
        Credential object used to connect to the SQL Server as a different user

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .EXAMPLE
        PS C:\> Get-XpDirTreeRestoreFile -Path '\\foo\bar\' -SqlInstance $SqlInstance

        Tests whether the instance $SqlInstance has access to the path \\foo\bar\
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [string]$Path,
        [parameter(Mandatory)]
        [DbaInstanceParameter]$SqlInstance,
        [System.Management.Automation.PSCredential]$SqlCredential,
        [switch]$EnableException,
        [switch]$NoRecurse
    )

    Write-Message -Level InternalComment -Message "Starting"

    $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
    $pathSep = Get-DbaPathSep -Server $server
    if (($path -like '*.bak') -or ($path -like '*.trn')) {
        # For a future person who knows what's up, please replace this comment with the reason this is empty
    } elseif ($Path[-1] -ne $pathSep) {
        $Path = $Path + $pathSep
    }

    if (!(Test-DbaPath -SqlInstance $server -path $path)) {
        Stop-Function -Message "SqlInstance $SqlInstance cannot access $path"
    }
    if (!(Test-DbaPath -SqlInstance $server -path $Path)) {
        Stop-Function -Message "SqlInstance $SqlInstance cannot access $Path"
    }
    if ($server.VersionMajor -ge 14) {
        # this is all kinds of cool, api could be expanded sooo much here
        $sql = "SELECT file_or_directory_name AS subdirectory, ~CONVERT(BIT, is_directory) as [file], 1 as depth
        FROM sys.dm_os_enumerate_filesystem('$Path', '*')
        WHERE  [level] = 0"
    } elseif ($server.VersionMajor -lt 9) {
        $sql = "EXEC master..xp_dirtree '$Path',1,1;"
    } else {
        $sql = "EXEC master.sys.xp_dirtree '$Path',1,1;"
    }
    #$queryResult = Invoke-DbaQuery -SqlInstance $SqlInstance -Credential $SqlCredential -Database tempdb -Query $query
    $queryResult = $server.Query($sql)
    Write-Message -Level Debug -Message $sql
    $dirs = $queryResult | Where-Object file -eq 0
    $Results = @()
    $Results += $queryResult | Where-Object file -eq 1 | Select-Object @{ Name = "FullName"; Expression = { $path + $_.subdirectory } }

    if ($True -ne $NoRecurse) {
        foreach ($d in $dirs) {
            $fullpath = $path + $d.subdirectory
            Write-Message -Level Verbose -Message "Enumerating subdirectory '$fullpath'"
            $Results += Get-XpDirTreeRestoreFile -Path $fullpath -SqlInstance $server
        }
    }
    return $Results
}