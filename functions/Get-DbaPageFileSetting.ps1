Function Get-DbaPageFileSetting
{
<#
.SYNOPSIS
Returns information about the network connection of the target computer including NetBIOS name, IP Address, domain name and fully qualified domain name (FQDN).

.DESCRIPTION
   WMI class Win32_ComputerSystem tells us if Page File is managed automatically.
   If TRUE all other properties do not exist.
   If FALSE classes Win32_PageFile, Win32_PageFileSetting en Win32_PageFileUsage are examined.
   CIM is used, first via WinRM, and if not successful, via DCOM.
   This function needs to be executed as a user with local admin rights on the target computer(s).

.PARAMETER ComputerName
The Server that you're connecting to.
This can be the name of a computer, a SMO object, an IP address or a SQL Instance.

.PARAMETER Credential
Credential object used to connect to the Computer as a different user

.PARAMETER Silent
Use this switch to disable any kind of verbose messages and allow exceptions

.NOTES
Tags: CIM
Author: Klaas Vandenberghe ( @PowerDBAKlaas )

dbatools PowerShell module (https://dbatools.io)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.

.LINK
 https://dbatools.io/Get-DbaPageFileSetting

.EXAMPLE
Get-DbaPageFileSetting -ComputerName ServerA,ServerB

Returns a custom object displaying ComputerName, AutoPageFile, FileName, Status, LastModified, LastAccessed, AllocatedBaseSize, InitialSize, MaximumSize, PeakUsage, CurrentUsage  for ServerA and ServerB

.EXAMPLE
'ServerA' | Get-DbaPageFileSetting

Returns a custom object displaying ComputerName, AutoPageFile, FileName, Status, LastModified, LastAccessed, AllocatedBaseSize, InitialSize, MaximumSize, PeakUsage, CurrentUsage  for ServerA

#>	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
		[Alias("cn", "host", "ServerInstance", "Server", "SqlServer")]
		[object]$ComputerName,
		[PSCredential] $Credential,
		[switch]$Silent
	)
	PROCESS
	{
		foreach ( $Computer in $ComputerName )
		{
			$reply = Resolve-DbaNetworkName -ComputerName $Computer -Credential $Credential -ErrorAction silentlycontinue
			
			if ( !$reply.FullComputerName ) # we can reach $computer
			{
				Write-Message -Level Warning -Message "$Computer is not available."
				continue
			}
			
			$computer = $reply.FullComputerName
			Write-Message -Level Verbose -Message "Getting computer information from $Computer via CIM (WSMan)"
			$CompSys = Get-CimInstance -ComputerName $Computer -Query "SELECT * FROM win32_computersystem" -ErrorAction SilentlyContinue
			
			if ( $CompSys ) # we have computersystem class via WSMan
			{
				Write-Message -Level Verbose -Message "Successfully retrieved ComputerSystem information on $Computer via CIM (WSMan)"
				if ( $CompSys.PSobject.Properties.Name -contains "automaticmanagedpagefile" ) # pagefile exists on $computer
				{
					Write-Message -Level Verbose -Message "Successfully retrieved PageFile information on $Computer via CIM (WSMan)"
					if ( $CompSys.automaticmanagedpagefile -eq $False ) # pagefile is not automatically managed, so get settings via WSMan
					{
						$PF = Get-CimInstance -ComputerName $Computer -Query "SELECT * FROM win32_pagefile" # deprecated !
						$PFU = Get-CimInstance -ComputerName $Computer -Query "SELECT * FROM win32_pagefileUsage"
						$PFS = Get-CimInstance -ComputerName $Computer -Query "SELECT * FROM win32_pagefileSetting"
					}
				}
				else # pagefile does not exist on $computer, warn and try next computer
				{
					Write-Message -Level Verbose -Message "$computer Operating System too old. No Pagefile information available."
					continue
				}
			}
			else # we do not get computersystem class via WSMan, try via DCom
			{
				Write-Message -Level Verbose -Message "No WSMan connection to $Computer"
				Write-Message -Level Verbose -Message "Getting computer information from $Computer via CIM (DCOM)"
				
				$sessionoption = New-CimSessionOption -Protocol DCOM
				$CIMsession = New-CimSession -ComputerName $Computer -SessionOption $sessionoption -Credential $Credential -ErrorAction SilentlyContinue
				$CompSys = Get-CimInstance -CimSession $CIMsession -Query "SELECT * FROM win32_computersystem" -ErrorVariable $MyErr -ErrorAction SilentlyContinue
				
				if ( $CompSys ) # we have computersystem class via DCom
				{
					Write-Message -Level Verbose -Message "Successfully retrieved ComputerSystem information on $Computer via CIM (DCOM)"
					if ( $CompSys.PSobject.Properties.Name -contains "automaticmanagedpagefile" ) # pagefile exists on $computer
					{
						Write-Message -Level Verbose -Message "Successfully retrieved PageFile information on $Computer via CIM (DCOM)"
						if ( $CompSys.automaticmanagedpagefile -eq $False ) # pagefile is not automatically managed, so get settings via DCom CimSession
						{
							$PF = Get-CimInstance -CimSession $CIMsession -Query "SELECT * FROM win32_pagefile" # deprecated !
							$PFU = Get-CimInstance -CimSession $CIMsession -Query "SELECT * FROM win32_pagefileUsage"
							$PFS = Get-CimInstance -CimSession $CIMsession -Query "SELECT * FROM win32_pagefileSetting"
						}
					}
					else # pagefile does not exist on $computer, warn and try next computer
					{
						Write-Message -Level Warning -Message "$computer Operating System too old. No Pagefile information available."
						continue
					}
				}
				else # we don't get computersystem, not wia WSMan nor via DCom, warn and try next computer
				{
					Write-Message -Level Warning -Message "No WSMan nor DCom connection to $Computer. If you're not local admin on $Computer, you need to run this command as a different user."
					continue
				}
			}
			if ( $CompSys.automaticmanagedpagefile -eq $False ) # pagefile is not automatic managed, so return settings
			{
				[PSCustomObject]@{
					ComputerName = $Computer
					AutoPageFile = $CompSys.automaticmanagedpagefile
					FileName = $PF.name # deprecated !
					Status = $PF.status # deprecated !
					LastModified = $PF.LastModified
					LastAccessed = $PF.LastAccessed
					AllocatedBaseSize = $PFU.AllocatedBaseSize # in MB, between Initial and Maximum Size
					InitialSize = $PFS.InitialSize # in MB
					MaximumSize = $PFS.MaximumSize # in MB
					PeakUsage = $PFU.peakusage # in MB
					CurrentUsage = $PFU.currentusage # in MB
				}
			}
			else # pagefile is automatic managed, so there are no settings
			{
				[PSCustomObject]@{
					ComputerName = $Computer
					AutoPageFile = $CompSys.automaticmanagedpagefile
					FileName = $null
					Status = $null
					LastModified = $null
					LastAccessed = $null
					AllocatedBaseSize = $null
					InitialSize = $null
					MaximumSize = $null
					PeakUsage = $null
					CurrentUsage = $null
				} | Select-DefaultView -Property ComputerName, AutoPageFile
			}
			if ( [void]$CIMsession.TestConnection() ) { Remove-CimSession $CIMsession }
		}
	}
}
