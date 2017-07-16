function Test-DbaSqlManagementObject {
	<#
		.SYNOPSIS
			Tests to see if the SMO version specified exists on the computer.
		
		.DESCRIPTION
		 	The Test-DbaSqlManagementObject returns True if the Version is on the computer, and False if it does not exist.
		
		.PARAMETER ComputerName
			The name of the target you would like to check
	
		.PARAMETER Credential
			This command uses Windows credentials. This parameter allows you to connect remotely as a different user.
	
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
		[parameter(ValueFromPipeline)]
		[Alias("ServerInstance", "SqlServer", "SqlInstance")]
		[DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$Credential,
		[Parameter(Mandatory)]
		[int[]]$VersionNumber,
		[switch]$Silent
	)
	
	begin {
		$scriptblock = {
			foreach ($number in $args) {
				$smolist = (Get-ChildItem -Path "$($env:SystemRoot)\assembly\GAC_MSIL\Microsoft.SqlServer.Smo" -Filter "$number.*" | Sort-Object Name -Descending).Name
				
				if ($smolist) {
					[pscustomobject]@{
						ComputerName = $env:COMPUTERNAME
						Version = $number
						Exists = $true
					}
				}
				else {
					[pscustomobject]@{
						ComputerName = $env:COMPUTERNAME
						Version = $number
						Exists = $false
					}
				}
			}
		}
	}
	process {
		foreach ($computer in $ComputerName.ComputerName) {
			try {
				Invoke-Command2 -ComputerName $computer -ScriptBlock $scriptblock -Credential $Credential -ArgumentList $VersionNumber -ErrorAction Stop
			}
			catch {
				Stop-Function -Continue -Message "Faiure" -ErrorRecord $_ -Target $ComputerName
			}
		}
	}
}