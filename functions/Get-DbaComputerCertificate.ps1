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
	
.PARAMETER Path
The path to a certificate - basically changes the path into a certificate object

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
		[PSCredential]$Credential,
		[string]$Store = "LocalMachine",
		[string]$Folder = "My",
		[string]$Path,
		[string[]]$Thumbprint,
		[switch]$Silent
	)
	
	process {
		foreach ($computer in $computername) {
			$scriptblock = {
				$Thumbprint = $args[0]
				$Store = $args[1]
				$Folder = $args[2]
				$Path = $args[3]
				
				if ($Path) {
					$bytes = [System.IO.File]::ReadAllBytes($path)
					$Certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
					$Certificate.Import($bytes, $null, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
					return $Certificate
				}
				
				if ($Thumbprint) {
					try {
						Write-Verbose "Searching Cert:\$Store\$Folder"
						Get-ChildItem "Cert:\$Store\$Folder" -Recurse | Where-Object Thumbprint -in $args[0]
					}
					catch {
						# don't care - there's a weird issue with remoting where an exception gets thrown for no apparent reason
					}
				}
				else {
					try {
						# This used to be hostname only but that didn't support clusters
						Write-Verbose "Searching Cert:\$Store\$Folder"
						Get-ChildItem "Cert:\$Store\$Folder" -Recurse | Where-Object { $_.DnsNameList -match $env:USERDNSDOMAIN -and $_.EnhancedKeyUsageList -match '1\.3\.6\.1\.5\.5\.7\.3\.1' }
					}
					catch {
						# don't care
					}
				}
			}
			
			try {
				Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock $scriptblock -ArgumentList $thumbprint, $Store, $Folder, $Path -ErrorAction Stop |
				Select-DefaultView -Property FriendlyName, DnsNameList, Thumbprint, NotBefore, NotAfter, Subject, Issuer
			}
			catch {
				Stop-Function -Message $_ -ErrorRecord $_ -Target $computer -Continue
			}
		}
	}
}
