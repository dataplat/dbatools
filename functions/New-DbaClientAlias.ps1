Function New-DbaClientAlias {
<#
.SYNOPSIS 
Gets SQL Server Client aliases - mimics cliconfg.exe

.DESCRIPTION
Gets SQL Server Client aliases - mimics cliconfg.exe which is stored in HKLM:\SOFTWARE\Microsoft\MSSQLServer\Client

.PARAMETER ComputerName
The target computer - defaults to localhost

.PARAMETER Credential
Allows you to login to remote computers using alternative credentials
	
.PARAMETER Silent
Use this switch to disable any kind of verbose messages

.NOTES
Tags: Alias

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/ New-DbaClientAlias

.EXAMPLE
New-DbaClientAlias -ServerAlias sqlcluster\sharepoint -Alias sp
Does this
#>
	[CmdletBinding()]
	Param (
		[DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
		[PSCredential]$Credential,
		[parameter(Mandatory, ValueFromPipeline)]
		[DbaInstanceParameter[]]$ServerAlias,
		[parameter(Mandatory)]
		[string]$Alias,
		[switch]$Silent
	)
	
	process {
		foreach ($computer in $ComputerName) {
			$null = Test-ElevationRequirement -ComputerName $computer -Continue
			
			$scriptblock = {
				$basekeys = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\MSSQLServer", "HKLM:\SOFTWARE\Microsoft\MSSQLServer"
				
				if ($env:PROCESSOR_ARCHITECTURE -like "*64*") { $64bit = $true }
				
				foreach ($basekey in $basekeys) {
					if ($64bit -ne $true -and $basekey -like "*WOW64*") { continue }
					
					if ((Test-Path $basekey) -eq $false) {
						Stop-Function -Message "Base key ($basekey) does not exist. Quitting." -Target $basekey
					}
					
					$client = "$basekey\Client"
					
					if ((Test-Path $client) -eq $false) {
						Write-Message -Level Verbose -Message "Creating $client key"
						$null = New-Item -Path $client -Force
					}
					
					$connect = "$client\ConnectTo"
					
					if ((Test-Path $connect) -eq $false) {
						Write-Message -Level Verbose -Message "Creating $connect key"
						$null = New-Item -Path $connect -Force
					}
					
					if ($basekey -like "*WOW64*") {
						$architecture = "32-bit"
					}
					else {
						$architecture = "64-bit"
					}
					
					Write-Message -Level Verbose -Message "Creating/updating alias for $ComputerName for $architecture"
					$null = New-ItemProperty -Path $connect -Name $Alias -Value "DBMSSOCN,$ComputerName" -PropertyType String -Force
				}
			}
			
			if ($PScmdlet.ShouldProcess($computer, "Adding $alias")) {
				try {
					Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock $scriptblock -ErrorAction Stop -ArgumentList $alias, $Password, $Store, $Folder |
					Select-DefaultView -Property FriendlyName, DnsNameList, Thumbprint, NotBefore, NotAfter, Subject, Issuer
				}
				catch {
					Stop-Function -Message "Failure" -ErrorRecord $_ -Target $computer -Continue
				}
			}
		}
	}
}