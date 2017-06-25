function Get-DbaSqlManagementObject
{
	<#
		.SYNOPSIS
			Gets SQL Mangaement Object versions installed on the machine.

		.DESCRIPTION
			The Get-DbaSqlManagementObject returns an object with the Version and the 
			Add-Type Load Template for each version on the server.

		.PARAMETER VersionNumber
			This is the specific version number you are looking for. The function will look 
			for that version only.
		
		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages
		
		.NOTES
			Tags: SMO
			Original Author: Ben Miller (@DBAduck - http://dbaduck.com)

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Get-DbaSqlManagementObject

		.EXAMPLE
			Get-DbaSqlManagementObject
			Returns all versions of SMO on the computer
		
		.EXAMPLE
			Get-DbaSqlManagementObject -VersionNumber 13
	
			Returns just the version specified. If the version does not exist then it will return nothing.
		
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $false, Position=0)]
		[int]$VersionNumber = 0,
		[switch]$Silent
	)
	begin
	{
		if ($VersionNumber -lt 9 and $VersionNumber -ne 0)
		{
			throw "SMO existed from SQL 2005 (version 9) onward. Please use a version after 9. Quitting."
		}	
	}
	process {
        Write-Message -Level Verbose -Message "Looking for SMO in the Global Assembly Cache"
		
		$smolist = (Get-ChildItem -Path "$env:SystemRoot\assembly\GAC_MSIL\Microsoft.SqlServer.Smo" | Sort-Object Name -Desc).Name
		
		$VersionList = [System.Collections.ArrayList]@()
		
		foreach ($version in $smolist)
		{
			$array = $version.Split("__")
			if ($VersionNumber -eq 0)
			{
				Write-Message -Level Verbose -Message "Inside VersionNumber not present"
				$VersionList += [PSCustomObject]@{
					Version = $array[0]
					LoadTemplate = "Add-Type -AssemblyName `"Microsoft.SqlServer.Smo, Version=$($array[0]), Culture=neutral, PublicKeyToken=89845dcd8080cc91`""
				}
			}
			else
			{
				Write-Message -Level Verbose -Message "Inside the Version is $VersionNumber"
				if ($array[0].StartsWith("$VersionNumber."))
				{
					Write-Message -Level Verbose -Message "Found the Version $VersionNumber"
					$VersionList += [PSCustomObject]@{
						Version	  = $array[0]
						LoadTemplate = "Add-Type -AssemblyName `"Microsoft.SqlServer.Smo, Version=$($array[0]), Culture=neutral, PublicKeyToken=89845dcd8080cc91`""
					}
					break
				}
			}
			
		} #foreach
		
		return $VersionList
		
    } # process
} #function