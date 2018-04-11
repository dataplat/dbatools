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
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Path,
        [parameter(Mandatory = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter]$SqlInstance,
        [System.Management.Automation.PSCredential]$SqlCredential,
        [bool][Alias('Silent')]$EnableException = $false,
        [switch]$NoRecurse
    )

    Write-Message -Level InternalComment -Message "Starting"

    Write-Message -Level Verbose -Message "Connecting to $SqlInstance"
    $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential

    if (($path -like '*.bak') -or ($path -like '*trn')) {

    }
    elseif ($Path[-1] -ne "\") {
        $Path = $Path + "\"
    }

    if (!(Test-DbaSqlPath -SqlInstance $server -path $path)) {
        Stop-Function -Message "SqlInstance $SqlInstance cannot access $path" -EnableException $true
    }
    if ($server.VersionMajor -lt 9) {
        $sql = "EXEC master..xp_dirtree '$Path',1,1;"
    }
    else {
        $sql = "EXEC master.sys.xp_dirtree '$Path',1,1;"
    }
    #$queryResult = Invoke-Sqlcmd2 -ServerInstance $SqlInstance -Credential $SqlCredential -Database tempdb -Query $query
    $queryResult = $server.Query($sql)
    Write-Message -Level Debug -Message $sql
    $dirs = $queryResult | where-object file -eq 0
    $Results = @()
    $Results += $queryResult | where-object file -eq 1 | Select-Object @{ Name = "FullName"; Expression = { $path + $_."Subdirectory" } }

    if ($True -ne $NoRecurse) {
        foreach ($d in $dirs) {
            $fullpath = "$path$($d.Subdirectory)"
            Write-Message -Level Verbose -Message "Enumerating subdirectory '$fullpath'"
            $Results += Get-XpDirTreeRestoreFile -path $fullpath -SqlInstance $server
        }
    }
    return $Results
}
