Function New-DbaClientAlias {
<#
.SYNOPSIS 
Sets SQL Server Client aliases - mimics cliconfg.exe

.DESCRIPTION
Sets SQL Server Client aliases - mimics cliconfg.exe which is stored in HKLM:\SOFTWARE\Microsoft\MSSQLServer\Client

.PARAMETER ComputerName
The target computer - defaults to localhost
		
.PARAMETER Credential
Allows you to login to remote computers using alternative credentials

.PARAMETER ServerAlias
The SqlServer that the alias will point to

.PARAMETER Alias
The new alias

.PARAMETER Protocol
Defaults to TCPIP but can be NamedPipes
	
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
Creates a new TCP alias on the local workstation called sp, which points sqlcluster\sharepoint
	
.EXAMPLE
New-DbaClientAlias -ServerAlias sqlcluster\sharepoint -Alias sp -Protocol NamedPipes
Creates a new NamedPipes alias on the local workstation called sp, which points sqlcluster\sharepoint
	
#>
	[CmdletBinding()]
	Param (
		[DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
		[PSCredential]$Credential,
		[parameter(Mandatory, ValueFromPipeline)]
		[DbaInstanceParameter[]]$ServerAlias,
		[parameter(Mandatory)]
		[string]$Alias,
		[ValidateSet("TCPIP", "NamedPipes")]
		[string]$Protcol = "TCPIP",
		[switch]$Silent
	)
	
	begin {
		# This is a script block so cannot use messaging system
		$scriptblock = {
			$basekeys = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\MSSQLServer", "HKLM:\SOFTWARE\Microsoft\MSSQLServer"
			$ServerAlias = $args[0]
			$Alias = $args[1]
			$serverstring = $args[2]
			
			if ($env:PROCESSOR_ARCHITECTURE -like "*64*") { $64bit = $true }
			
			foreach ($basekey in $basekeys) {
				if ($64bit -ne $true -and $basekey -like "*WOW64*") { continue }
				
				if ((Test-Path $basekey) -eq $false) {
					throw "Base key ($basekey) does not exist. Quitting."
				}
				
				$client = "$basekey\Client"
				
				if ((Test-Path $client) -eq $false) {
					Write-Verbose "Creating $client key"
					$null = New-Item -Path $client -Force
				}
				
				$connect = "$client\ConnectTo"
				
				if ((Test-Path $connect) -eq $false) {
					Write-Verbose "Creating $connect key"
					$null = New-Item -Path $connect -Force
				}
				
				if ($basekey -like "*WOW64*") {
					$architecture = "32-bit"
				}
				else {
					$architecture = "64-bit"
				}
				
				Write-Verbose "Creating/updating alias for $ComputerName for $architecture"
				$null = New-ItemProperty -Path $connect -Name $Alias -Value $serverstring -PropertyType String -Force
			}
		}
	}
	
	process {
		if ($protocol -eq "TCPIP") {
			$serverstring = "DBMSSOCN,$ServerAlias"
		}
		else {
			$serverstring = "DBNMPNTW,\\$ServerAlias\pipe\sql\query"
		}
		
		foreach ($computer in $ComputerName.ComputerName) {
			
			if ((Test-ElevationRequirement -ComputerName $computer)) {
				continue
			}
			
			if ($PScmdlet.ShouldProcess($computer, "Adding $alias")) {
				try {
					Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock $scriptblock -ErrorAction Stop -ArgumentList $ServerAlias, $Alias, $serverstring -Verbose:$verbose
					[pscustomobject]@{
						ComputerName	  = $computer
						ServerAlias	      = $ServerAlias
						Alias			  = $Alias
						RegistryEntry  = $serverstring
					}
				}
				catch {
					Stop-Function -Message "Failure" -ErrorRecord $_ -Target $computer -Continue
				}
			}
		}
	}
}