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
       
        $FunctionName = "Get-XpDirTreeRestoreFile"
        
        Write-Verbose "$FunctionName - Starting"
        Write-Verbose "$FunctionName - Checking Path"
        If (((Test-SQLConnection -SqlServer $SqlServer -SqlCredential $SqlCredential)[11].ConnectSuccess -eq $false))
        {
            Write-Error "$FunctionName - SQL Connection details not valid"
            return $null
            break
        }
        if ((Test-SqlSa -SqlServer $SqlServer -SqlCredential $SqlCredential) -eq $false)
        {
            Write-Error "$FunctionName - Not sysadmin, this will not work"
        }
        function Get-XpDirTreeRestoreFileRecurse([string]$Path)
        {
            if ($Path[-1] -ne "\")
            {
                $Path = $Path + "\"
            }
            $query = "EXEC master.sys.xp_dirtree '$Path',0,1;"
            $queryResult = Invoke-Sqlcmd2 -ServerInstance $sqlServer -Database tempdb -Query $query
            $dirs = $queryResult | where-object { $_.file -eq 0 }
            foreach($d in $dirs) 
            {
                $fullpath = "$path$($d.Subdirectory)"
                Write-Verbose "Enumerating subdirectory '$fullpath'"
                Get-XpDirTreeRestoreFileRecurse $fullpath
            }
            $Results = $queryResult | where-object { $_.file -eq 1 } | Select @{Name="FullName";Expression={$_."Subdirectory"}}
            $Results = $Results | %{"$path$($_.FullName)"} | select @{Name="Fullname";Expression={$_}}
            return $Results
        }
        Write-Verbose "Enumerating main directory '$Path'"
        Get-XpDirTreeRestoreFileRecurse $Path
}