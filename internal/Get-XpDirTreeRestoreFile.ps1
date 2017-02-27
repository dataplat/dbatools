function Get-XpDirTreeRestoreFile
{
<#
.SYNOPSIS
Internal Function to get SQL Server backfiles from a specified folder using xp_dirtree
.DESCRIPTION
Takes path, checks for validity. Scans for usual backup file 
.PARAMETER Path
.PARAMETER 
#>
    [CmdletBinding()]
    Param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Path,
        [parameter(Mandatory = $true)]
        [Alias("ServerInstance", "SqlInstance")]
        [object]$SqlServer,
        [System.Management.Automation.PSCredential]$SqlCredential
    )
       
        $FunctionName =(Get-PSCallstack)[0].Command
        
        Write-Verbose "$FunctionName - Starting"
        Write-Verbose "$FunctionName - Checking Path"
        Try 
        {
            $srv = Connect-SQLServer -SqlServer $SqlServer -SqlCredential $SqlCredential
        }
        Catch
        {
            Write-Warning "$FunctionName - Cannot connect to $sqlServer" -WarningAction stop
        }

        if ($Path[-1] -ne "\")
        {
            $Path = $Path + "\"
        }
        If (!(Test-SqlPath -SQLServer $sqlserver -SqlCredential $SqlCredential -path $path))
        {
            Write-warning "$FunctionName - SQLServer $sqlserver cannot access $path"
        }
        $query = "EXEC master.sys.xp_dirtree '$Path',1,1;"
        $queryResult = Invoke-Sqlcmd2 -ServerInstance $sqlServer -Credential $SqlCredential -Database tempdb -Query $query
        #$queryresult
        $dirs = $queryResult | where-object { $_.file -eq 0 }
        $Results = @()
              $Results += $queryResult | where-object { $_.file -eq 1 } | Select-Object @{Name="FullName";Expression={$PATH+$_."Subdirectory"}}
  
        ForEach ($d in $dirs) 
        {
            $fullpath = "$path$($d.Subdirectory)"
            Write-Verbose "Enumerating subdirectory '$fullpath'"
            $Results += Get-XpDirTreeRestoreFile -path $fullpath -SqlServer $SqlServer -SqlCredential $SqlCredential
        }
        return $Results
    
}
