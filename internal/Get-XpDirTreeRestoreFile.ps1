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
    
    .PARAMETER Silent
        Setting this to true will disable all verbosity.
    
    .EXAMPLE
        PS C:\> Get-XpDirTreeRestoreFile -Path '\\foo\bar\' -SqlInstance $SqlInstance
    
        Tests whether the instance $SqlInstance has access to the path \\foo\bar\
#>
    [CmdletBinding()]
    Param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]
        $Path,
        
        [parameter(Mandatory = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter]
        $SqlInstance,
        
        [System.Management.Automation.PSCredential]
        $SqlCredential,
        
        [bool]
        $Silent = $false
    )
    
    Write-Message -Level InternalComment -Message "Starting"
    
    Write-Message -Level Verbose -Message "Connecting to $SqlInstance"
    $Server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
    
    if ($Path[-1] -ne "\") {
        $Path = $Path + "\"
    }
    
    If (!(Test-DbaSqlPath -SqlInstance $server -SqlCredential $SqlCredential -path $path)) {
        Stop-Function -Message "SqlInstance $SqlInstance cannot access $path" -Silent $true
    }
    
    $query = "EXEC master.sys.xp_dirtree '$Path',1,1;"
    $queryResult = $server.Query($query,'tempdb')
    
    $dirs = $queryResult | where-object file -eq 0
    $Results = @()
    $Results += $queryResult | where-object file -eq 1 | Select-Object @{ Name = "FullName"; Expression = { $PATH + $_."Subdirectory" } }
    
    ForEach ($d in $dirs) {
        $fullpath = "$path$($d.Subdirectory)"
        Write-Message -Level Verbose -Message "Enumerating subdirectory '$fullpath'"
        $Results += Get-XpDirTreeRestoreFile -path $fullpath -SqlInstance $Server -SqlCredential $SqlCredential
    }
    return $Results
    
}
