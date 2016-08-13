Function Test-SqlTempDbConfiguration
{
<#
.SYNOPSIS
Evaluates tempdb against several rules to match best practices.

.DESCRIPTION
Evaluates tempdb aganst a set of rules to match best practices. The rules are:
TF 1118 enabled - Is Trace Flag 1118 enabled (See KB328551).
File Count - Does the count of data files in tempdb match the number of logical cores, up to 8.
File Growth - Are any files set to have percentage growth, as best practice is all files have an explicit growth value.
File Location - Is tempdb located on the C:\? Best practice says to locate it elsewhere.
File MaxSize Set(optional) - Do any files have a max size value? Max size could cause tempdb problems if it isn't allowed to grow.

Other rules can be added at a future date. Only results that don't match best practices will be displayed. To display all results,
use the -Detailed switch.

.PARAMETER SqlServer
The SQL Server instance.You must have sysadmin access and server version must be SQL Server version 2000 or higher.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 

Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.

.PARAMETER Detailed
Switch that allows you to display all test results.

.NOTES 
Original Author: Michael Fal (@Mike_Fal), http://mikefal.net
Based off of Amit Bannerjee's (@banerjeeamit) Get-TempDB function (https://github.com/amitmsft/SqlOnAzureVM/blob/master/Get-TempdbFiles.ps1)

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Test-SqlTempDbConfiguration

.EXAMPLE   
Test-SqlTempDbConfiguration -SqlServer localhost

Checks tempdb on the localhost machine.

.EXAMPLE   
Test-SqlTempDbConfiguration -SqlServer localhost -Detailed

Checks tempdb on the localhost machine. All rest results are shown.
	
#>
	
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[object]$SqlCredential,
        [Switch]$Detailed
	)
	
	BEGIN
	{
		$return = @()
		Write-Verbose "Connecting to $SqlServer"
		$server = Connect-SqlServer $SqlServer -SqlCredential $SqlCredential
	}
	
	PROCESS
	{
		#test for TF 1118
		if ($server.VersionMajor -ge 13)
		{
			$notes = 'SQL 2016 has this functionality enabled by default'
			# DBA May have changed setting. May need to check.
			$value = [PSCustomObject]@{
				Rule = 'TF 1118 Enabled'
				Recommended = $true
				CurrentSetting = $true
			}
		}
		else
		{
			$sql = "dbcc traceon (3604);dbcc tracestatus (-1)"
			$tfcheck = $server.Databases['tempdb'].ExecuteWithResults($sql).Tables[0].TraceFlag
			$notes = 'KB328551 describes how TF 1118 can benefit performance.'
			
			if (($tfcheck -join ',').Contains('1118'))
			{
				
				$value = [PSCustomObject]@{
					Rule = 'TF 1118 Enabled'
					Recommended = $true
					CurrentSetting = $true
				}
			}
			else
			{
				$value = [PSCustomObject]@{
					Rule = 'TF 1118 Enabled'
					Recommended = $true
					CurrentSetting = $false
				}
			}
		}
		
		if ($value.Recommended -ne $value.CurrentSetting -and $value.Recommended -ne $null)
		{
			$isBestPractice = $false
		}
		else
		{
			$isBestPractice = $true
		}
		
		$value | Add-Member -MemberType NoteProperty -Name IsBestpractice -Value $isBestPractice
		$value | Add-Member -MemberType NoteProperty -Name Notes -Value $notes
		$return += $value
		Write-Verbose "TF 1118 evaluated"
		
		#get files and log files
		$datafiles = $server.Databases['tempdb'].ExecuteWithResults("SELECT physical_name as FileName, max_size as MaxSize, CASE WHEN is_percent_growth = 1 THEN 'Percent' ELSE 'KB' END as GrowthType from sys.database_files WHERE type_desc = 'ROWS'").Tables[0]
		$logfiles =  $server.Databases['tempdb'].ExecuteWithResults("SELECT physical_name as FileName, max_size as MaxSize, CASE WHEN is_percent_growth = 1 THEN 'Percent' ELSE 'KB' END as GrowthType from sys.database_files WHERE type_desc = 'LOG'").Tables[0]
		
		Write-Verbose "TempDB file objects gathered"
		
		$cores = $server.Processors

		if ($cores -gt 8) { $cores = 8 }
		
		$value = [PSCustomObject]@{
			Rule = 'File Count'
			Recommended = $cores
			CurrentSetting = $datafiles.Rows.Count
		}
		
		if ($value.Recommended -ne $value.CurrentSetting -and $value.Recommended -ne $null)
		{
			$isBestPractice = $false
		}
		else
		{
			$isBestPractice = $true
		}
		
		$value | Add-Member -MemberType NoteProperty -Name IsBestpractice -Value $isBestPractice
		$value | Add-Member -MemberType NoteProperty -Name Notes -Value 'Microsoft recommends that the number of tempdb data files is equal to the number of logical cores up to 8.'
		$return += $value
		
		Write-Verbose "File counts evaluated"
		
		#test file growth
		$percdata = $datafiles | Where-Object { $_.GrowthType -ne 'KB' } | Measure-Object
		$perclog =  $logfiles  | Where-Object { $_.GrowthType -ne 'KB' } | Measure-Object
		
		$totalcount = $percdata.count + $perclog.count
		if ($totalcount -gt 0) { $totalcount = $true } else { $totalcount = $false }
		
		$value = [PSCustomObject]@{
			Rule = 'File Growth in Percent'
			Recommended = $false
			CurrentSetting = $totalcount
		}
		
		if ($value.Recommended -ne $value.CurrentSetting -and $value.Recommended -ne $null)
		{
			$isBestPractice = $false
		}
		else
		{
			$isBestPractice = $true
		}
		
		$value | Add-Member -MemberType NoteProperty -Name IsBestpractice -Value $isBestPractice
		$value | Add-Member -MemberType NoteProperty -Name Notes -Value 'Set grow with explicit values, not by percent.'
		$return += $value
		
		Write-Verbose "File growth settings evaluated"
		#test file Location
		
		$cdata = ($datafiles | Where-Object { $_.FileName -like 'C:*' } | Measure-Object).Count + ($logfiles | Where-Object { $_.FileName -like 'C:*' } | Measure-Object).Count
		if ($cdata -gt 0) { $cdata = $true } else { $cdata = $false }
		
		$value = [PSCustomObject]@{
			Rule = 'File Location'
			Recommended = $false
			CurrentSetting = $cdata
		}
		
		if ($value.Recommended -ne $value.CurrentSetting -and $value.Recommended -ne $null)
		{
			$isBestPractice = $false
		}
		else
		{
			$isBestPractice = $true
		}
		
		$value | Add-Member -MemberType NoteProperty -Name IsBestpractice -Value $isBestPractice
		$value | Add-Member -MemberType NoteProperty -Name Notes -Value "Do not place your tempdb files on C:\."
		$return += $value
		
		Write-Verbose "File locations evaluated"
		
		#Test growth limits
		$growthlimits = ($datafiles | Where-Object { $_.MaxSize -gt 0 } | Measure-Object).Count + ($logfiles | Where-Object { $_.MaxSize -gt 0 } | Measure-Object).Count
		if ($growthlimits -gt 0) { $growthlimits = $true } else { $growthlimits = $false }
		
		$value = [PSCustomObject]@{
			Rule = 'File MaxSize Set'
			Recommended = $false
			CurrentSetting = $growthlimits
		}
		
		if ($value.Recommended -ne $value.CurrentSetting -and $value.Recommended -ne $null)
		{
			$isBestPractice = $false
		}
		else
		{
			$isBestPractice = $true
		}
		
		$value | Add-Member -MemberType NoteProperty -Name IsBestpractice -Value $isBestPractice
		$value | Add-Member -MemberType NoteProperty -Name Notes -Value "Consider setting your tempdb files to unlimited growth."
		$return += $value
		
		Write-Verbose "MaxSize values evaluated"
	}
	
	END
	{
        if($Detailed){
		    return $return
        } else {
            return ($return | Where-Object {$_.isBestPractice -eq $false})
        }
	}
}