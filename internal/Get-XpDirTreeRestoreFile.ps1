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

        if ($path[-1] -ne "\")
        {
            $path = $path + "\"
        }

        $query = "EXEC master.sys.xp_dirtree '$path',1,1;"

        $queryResult = Invoke-Sqlcmd2 -ServerInstance $sqlServer -Database tempdb -Query $query
        $results = $queryResult | Select @{Name="FullName";Expression={$_."Subdirectory"}}
        $results = $results | %{"$path$($_.fullname)"} | select @{Name="Fullname";Expression={$_}}
        #$results = $queryResult | Select @{Name="FullName";Expression={$_."Subdirectory"}}
        #$results  = $results | ForEach-Object {$_ = "$path$($_.FullName)"}
        return $results
}