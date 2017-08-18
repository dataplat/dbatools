function Get-OlaHRestoreFile
{
<#
.SYNOPSIS
Internal Function to get SQL Server backfiles from a specified folder that's formatted according to Ola Hallengreen's scripts.

.DESCRIPTION
Takes path, checks for validity. Scans for usual backup file 
#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[string]$Path
	)
	$FunctionName = (Get-PSCallstack)[0].Command
	
	Write-Verbose "$FunctionName - Starting"
	Write-Verbose "$FunctionName - Checking Path"
	
	if ((Test-Path $Path) -ne $true)
	{
		Write-Warning "$FunctionName - $Path is not valid"
		return
	}
	
	#There should be at least FULL folder, DIFF and LOG are nice as well
	Write-Verbose "$FunctionName - Checking we have a FULL folder"
	
	if (Test-Path -Path $Path\FULL)
	{
		Write-Verbose "$FunctionName - We have a FULL folder, scanning"
		$Results = Get-ChildItem -Path $Path\FULL -Filter *.bak
		$results = @($results)
	}
	else
	{
		if ($MaintenanceSolutionBackup)
		{
			Write-Warning "$FunctionName - Don't have a FULL folder"
		}
		else
		{
			Write-Warning "$FunctionName - No valid backup found - even tried MaintenanceSolution structure"
		}
		
		return
	}
	if (Test-Path -Path $Path\Log)
	{
		Write-Verbose "$FunctionName - We have a LOG folder, scanning"
		$Results += Get-ChildItem -Path $Path\LOG -filter *.trn
	}
	if (Test-Path -Path $Path\Diff)
	{
		Write-Verbose "$FunctionName - We have a DIFF folder, scanning"
		$Results += Get-ChildItem -Path $Path\DIFF -filter *.bak
	}
	
	return $Results
}
