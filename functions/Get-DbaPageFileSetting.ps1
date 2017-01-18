Function Get-DbaPageFileSetting {
<#
.SYNOPSIS
Returns information about the network connection of the target computer including NetBIOS name, IP Address, domain name and fully qualified domain name (FQDN).

.DESCRIPTION
   WMI class Win32_ComputerSystem tells us if Page File is managed automatically.
   If TRUE all other properties do not exist.
   If FALSE classes Win32_PageFile, Win32_PageFileSetting en Win32_PageFileUsage are examined.
   CIM is used, first via WinRM, and if not successful, via DCOM.

.PARAMETER ComputerName
The Server that you're connecting to.
This can be the name of a computer, a SMO object, an IP address or a SQL Instance.

.PARAMETER Credential
Credential object used to connect to the Computer as a different user

.NOTES
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
 ServerA | Get-DbaPageFileSetting

Returns a custom object displaying ComputerName, AutoPageFile, FileName, Status, LastModified, LastAccessed, AllocatedBaseSize, InitialSize, MaximumSize, PeakUsage, CurrentUsage  for ServerA

#>[CmdletBinding()]
	param (
		[Parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
		[Alias("cn", "host", "ServerInstance", "Server", "SqlServer")]
		[object]$ComputerName,
		[PSCredential] [System.Management.Automation.CredentialAttribute()]$Credential
	)
	BEGIN {}
	PROCESS {
        foreach ($Computer in $ComputerName)
        {
            Write-Verbose "Connecting to $Computer"
			$reply = Resolve-DbaNetworkName -ComputerName $Computer -erroraction silentlycontinue
            if ( $reply.ComputerName )
            {
                $computer = $reply.ComputerName
            }
            Write-Verbose "Connecting to $Computer via CIM (WSMan)"
            $CompSys = Get-CimInstance -ComputerName $Computer -Query "SELECT * FROM win32_computersystem" -ErrorVariable $MyErr -Credential $Credential
            if ( $CompSys )
            {
                Write-Verbose "Successfully retrieved PageFile information on $Computer via WSMan"
                if ($CompSys.automaticmanagedpagefile -eq $False)
                {
                    $PF = Get-CimInstance -ComputerName $Computer -Query "SELECT * FROM win32_pagefile" # deprecated !
                    $PFU = Get-CimInstance -ComputerName $Computer -Query "SELECT * FROM win32_pagefileUsage"
                    $PFS = Get-CimInstance -ComputerName $Computer -Query "SELECT * FROM win32_pagefileSetting"
                }
            }
			else
            {
				Write-Verbose "No WSMan connection to $Computer"
                Write-Verbose "Getting computer information from server $Computer via CIM (DCOM)"
			    $sessionoption = New-CimSessionOption -Protocol DCOM
			    $CIMsession = New-CimSession -ComputerName $Computer -SessionOption $sessionoption -Credential $Credential
                $CompSys = Get-CimInstance -CimSession $CIMsession -Query "SELECT * FROM win32_computersystem" -ErrorVariable $MyErr
                if ( $CompSys )
                {
                    if ( $CompSys.automaticmanagedpagefile )
                    {
                        Write-Verbose "Successfully retrieved PageFile information on $Computer via DCom"
                        if ($CompSys.automaticmanagedpagefile -eq $False)
                        {
                            $PF = Get-CimInstance -CimSession $CIMsession -Query "SELECT * FROM win32_pagefile" # deprecated !
                            $PFU = Get-CimInstance -CimSession $CIMsession -Query "SELECT * FROM win32_pagefileUsage"
                            $PFS = Get-CimInstance -CimSession $CIMsession -Query "SELECT * FROM win32_pagefileSetting"
                        }
                    }
                    else
                    {
                    Write-Warning "$computer Operating System too old. No Pagefile information available."
                    continue
                    }
                }
			    else
			    {
				    Write-Warning "No WSMan nor DCom connection to $Computer"
                    continue
			    }
            }
            if ($CompSys.automaticmanagedpagefile -eq $False)
            {
                [PSCustomObject]@{
                            'ComputerName' = $Computer;
                            'AutoPageFile' = $CompSys.automaticmanagedpagefile;
                            'FileName' = $PF.name; # deprecated !
                            'Status' = $PF.status; # deprecated !
                            'LastModified' = $PF.LastModified;
                            'LastAccessed' = $PF.LastAccessed;
                            'AllocatedBaseSize' = $PFU.AllocatedBaseSize; # in MB, between Initial and Maximum Size
                            'InitialSize' = $PFS.InitialSize; # in MB
                            'MaximumSize' = $PFS.MaximumSize; # in MB
                            'PeakUsage' = $PFU.peakusage; # in MB
                            'CurrentUsage' = $PFU.currentusage; # in MB
                            }
            }
            else
            {
                [PSCustomObject]@{
                            'ComputerName' = $Computer;
                            'AutoPageFile' = $CompSys.automaticmanagedpagefile;
                            'FileName' = "";
                            'Status' = "";
                            'LastModified' = "";
                            'LastAccessed' = "";
                            'AllocatedBaseSize' = "";
                            'InitialSize' = "";
                            'MaximumSize' = "";
                            'PeakUsage' = "";
                            'CurrentUsage' = "";
                            }
            }
        }
	}
	END {}
}