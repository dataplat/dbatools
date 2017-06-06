function Get-DbaComputerCertificate {
<#
.SYNOPSIS
Simplifies finding computer certificates that are candidates for using with SQL Server's network encryption

.DESCRIPTION
Gets computer certificates on localhost that are candidates for using with SQL Server's network encryption

.PARAMETER ComputerName
The target SQL Server - defaults to localhost. If target is a cluster, you must specify the distinct nodes.

.PARAMETER Credential
Allows you to login to $ComputerName using alternative credentials.
	
.PARAMETER Store
Certificate store - defaults to LocalMachine

.PARAMETER Folder
Certificate folder - defaults to My (Personal)
	
.PARAMETER Thumbprint
Return certificate based on thumbprint

.PARAMETER Thumbprint
Return certificate based on thumbprint

.PARAMETER Silent 
Use this switch to disable any kind of verbose messages

.NOTES
Tags: Certificate

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.EXAMPLE
Get-DbaComputerCertificate
Gets computer certificates on localhost that are candidates for using with SQL Server's network encryption

.EXAMPLE
Get-DbaComputerCertificate -ComputerName sql2016

Gets computer certificates on sql2016 that are candidates for using with SQL Server's network encryption

.EXAMPLE
Get-DbaComputerCertificate -ComputerName sql2016 -Thumbprint 8123472E32AB412ED4288888B83811DB8F504DED, 04BFF8B3679BB01A986E097868D8D494D70A46D6

Gets computer certificates on sql2016 that match thumbprints 8123472E32AB412ED4288888B83811DB8F504DED or 04BFF8B3679BB01A986E097868D8D494D70A46D6
#>
	[CmdletBinding()]
	param (
		[parameter(ValueFromPipeline)]
		[Alias("ServerInstance", "SqlServer", "SqlInstance")]
		[DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
		[System.Management.Automation.PSCredential]$Credential,
		[string]$Store = "LocalMachine",
		[string]$Folder = "My",
		[string[]]$Thumbprint,
		[switch]$Silent
	)
	
	process {
		foreach ($computer in $computername) {
			
			$scriptblock = {
				if ($args) {
					Get-ChildItem Cert:\$Store\$Folder -Recurse | Where-Object Thumbprint -in $args
				}
				else {
					Get-ChildItem Cert:\$Store\$Folder -Recurse | Where-Object { $_.DnsNameList -match "$env:COMPUTERNAME.$env:USERDNSDOMAIN" -and $_.EnhancedKeyUsageList -match '1\.3\.6\.1\.5\.5\.7\.3\.1' }
				}
			}
			
			try {
				Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock $scriptblock -ArgumentList $thumbprint -ErrorAction Stop
			}
			catch {
				Stop-Function -Message $_ -ErrorRecord $_ -Target $computer -Continue
			}
		}
	}
}