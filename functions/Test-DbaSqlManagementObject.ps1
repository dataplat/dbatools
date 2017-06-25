function Test-DbaSqlManagementObject
{
	<#
		.SYNOPSIS
			Tests to see if the SMO version specified exists on the computer.
		
		.DESCRIPTION
		 	The Test-DbaSqlManagementObject returns True if the Version is on the computer, and False if it does not exist.
		
		.PARAMETER VersionNumber
			This is the specific version number you are looking for and the return will be True.
		
		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages
		
		.NOTES
			Tags: SMO
			Original Author: Ben Miller (@DBAduck - http://dbaduck.com)

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Test-DbaSqlManagementObject

		.EXAMPLE
			Test-DbaSqlManagementObject -VersionNumber 13
			Returns True if the version exists, if it does not exist it will return False
		
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true, Position = 0)]
		[int]$VersionNumber
	)
	begin
	{
		if ($VersionNumber -lt 9)
		{
			throw "SMO existed from SQL 2005 (version 9) onward. Please use a version after 9. Quitting."
		}
	}
	process
	{
		$smolist = Get-ChildItem -Path "$($env:SystemRoot)\assembly\GAC_MSIL\Microsoft.SqlServer.Smo" -Filter "$VersionNumber.*" | Sort-Object Name -Desc | select -ExpandProperty Name
		
		if ($smolist.Length -gt 0)
		{
			return $true
		}
		else
		{
			return $false
		}
	}
}
