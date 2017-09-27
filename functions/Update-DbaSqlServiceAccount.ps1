function Update-DbaSqlServiceAccount {
	<#
	.SYNOPSIS
	Changes service account (or just its password) of the SQL Server service.

	.DESCRIPTION
	Reconfigures service account or updates password of the specified SQL Server service. The service will be restarted in the event of changing the account.

	.PARAMETER ComputerName
	The SQL Server (or server in general) that you're connecting to. This command handles named instances.

	.PARAMETER Credential
	Windows Credential with permission to log on to the server running the SQL instance
	
	.PARAMETER ServiceCollection
	A collection of services. Basically, any object that has ComputerName and ServiceName properties. Can be piped from Get-DbaSqlService.

	.PARAMETER ServiceName
	A name of the service on which the action is performed. E.g. MSSQLSERVER or SqlAgent$INSTANCENAME

	.PARAMETER ServiceCredential
	Windows Credential object under which the service will be setup to run. For local service accounts use one of the following usernames with empty password:
	LOCALSERVICE
	NETWORKSERVICE
	LOCALSYSTEM

	.PARAMETER OldPassword
	An old password of the service account. Optional when run under local admin privileges.

	.PARAMETER NewPassword
	New password of the service account.

	.PARAMETER WhatIf 
	Shows what would happen if the command were to run. No actions are actually performed. 

	.PARAMETER Confirm 
	Prompts you for confirmation before executing any changing operations within the command. 

	.PARAMETER Silent 
	Use this switch to disable any kind of verbose messages

	.NOTES
	Author: Kirill Kravtsov (@nvarscar)

	dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
	Copyright (C) 2017 Chrissy LeMaire

	This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
	This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
	You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

	.EXAMPLE 
	$NewPassword = ConvertTo-SecureString 'Qwerty1234' -AsPlainText -Force
	Update-DbaSqlServiceAccount -ComputerName sql1 -ServiceName 'MSSQL$MYINSTANCE' -Password $NewPassword

	Changes the current service account's password of the service MSSQL$MYINSTANCE to 'Qwerty1234'

	.EXAMPLE
	$cred = Get-Credential
	Get-DbaSqlService sql1 -Type Engine,Agent -Instance MYINSTANCE | Update-DbaSqlServiceAccount -ServiceCredential $cred

	Requests credentials from the user and configures them as a service account for the SQL Server engine and agent services of the instance sql1\MYINSTANCE
	
	.EXAMPLE
	$cred = New-Object System.Management.Automation.PSCredential ("NETWORKSERVICE", [securestring]::New())
	Update-DbaSqlServiceAccount -ComputerName sql1,sql2 -ServiceName 'MSSQLSERVER','SQLSERVERAGENT' -ServiceCredential $cred

	Configures SQL Server engine and agent services on the machines sql1 and sql2 to run under Network Service system user.
	
	#>
	[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = "ServiceNameAccount" )]
	param (
		[parameter(ParameterSetName = "ServiceNameAccount")]
		[parameter(ParameterSetName = "ServiceNamePassword")]
		[Alias("cn", "host", "Server")]
		[DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
		[PSCredential]$Credential,
		[parameter(ValueFromPipeline = $true, Mandatory = $true, ParameterSetName = "ServiceCollectionAccount")]
		[parameter(ValueFromPipeline = $true, Mandatory = $true, ParameterSetName = "ServiceCollectionPassword")]
		[object[]]$ServiceCollection,
		[parameter(ParameterSetName = "ServiceNameAccount", Position = 1, Mandatory = $true)]
		[parameter(ParameterSetName = "ServiceNamePassword", Position = 1, Mandatory = $true)]
		[Alias("Name", "Service")]
		[string[]]$ServiceName,
		[Parameter(ParameterSetName = "ServiceCollectionAccount", Mandatory = $true)]
		[Parameter(ParameterSetName = "ServiceNameAccount", Position = 2, Mandatory = $true)]
		[PSCredential]$ServiceCredential,
		[Parameter(ParameterSetName = "ServiceCollectionPassword")]
		[Parameter(ParameterSetName = "ServiceNamePassword")]
		[securestring]$OldPassword = [securestring]::new(),
		[Parameter(ParameterSetName = "ServiceCollectionPassword", Mandatory = $true)]
		[Parameter(ParameterSetName = "ServiceNamePassword", Position = 2, Mandatory = $true)]
		[Alias("Password")]
		[securestring]$NewPassword,
		[switch]$Silent
	)
	begin {
		$svcCollection = @()
		$scriptAccountChange = {
			$service = $wmi.Services[$args[0]]
			$service.SetServiceAccount($args[1], $args[2])
			$service.Alter()
		}
		$scriptPasswordChange = {
			$service = $wmi.Services[$args[0]]
			$service.ChangePassword($args[1], $args[2])
			$service.Alter()
		}
		#Check for system logins and replace the Credential object to simplify passing localsystem-like login names
		if ($ServiceCredential) {
			#Get rid of domain name and remove whitespaces
			$userName = (Split-Path $ServiceCredential.UserName -Leaf).Trim().Replace(' ', '')
			#System logins should not have a domain name, whitespaces or passwords
			if ($userName -in 'NETWORKSERVICE', 'LOCALSYSTEM', 'LOCALSERVICE') {
				$ServiceCredential = New-Object System.Management.Automation.PSCredential ($userName, [securestring]::New())
			}
		}
	}
	process {
		if ($PsCmdlet.ParameterSetName -match 'ServiceName') {
			foreach ($Computer in $ComputerName.ComputerName) {
				$Server = Resolve-DbaNetworkName -ComputerName $Computer -Credential $credential
				if ($Server.ComputerName) {
					foreach ($service in $ServiceName) {
						$svcCollection += [psobject]@{
							ComputerName = $server.ComputerName
							ServiceName  = $service
						}		
					}			
				}
				else {
					Stop-Function -Silent $Silent -Message "Failed to connect to $Computer" -Continue
				}
			}
		}
		elseif ($PsCmdlet.ParameterSetName -match 'ServiceCollection') {
			foreach ($service in $ServiceCollection) {
				$Server = Resolve-DbaNetworkName -ComputerName $service.ComputerName -Credential $credential
				if ($Server.ComputerName) {
					$svcCollection += [psobject]@{
						ComputerName = $Server.ComputerName
						ServiceName  = $service.ServiceName
					}		
				}
				else {
					Stop-Function -Silent $Silent -Message "Failed to connect to $($service.ComputerName)" -Continue
				}
			}	
		}
		
	}
	end {
		foreach ($svc in $svcCollection) {
			if ($serviceObject = Get-DbaSqlService -ComputerName $svc.ComputerName -ServiceName $svc.ServiceName -Credential $Credential -Silent:$Silent) {
				$outMessage = $outStatus = $agent = $null
				if ($serviceObject.ServiceType -eq 'Engine') {
					#Get SQL Agent running status
					$agent = Get-DbaSqlService -ComputerName $svc.ComputerName -Type Agent -InstanceName $serviceObject.InstanceName
				}
				if ($PsCmdlet.ShouldProcess($svc, "Changing account information for service $($svc.ServiceName) on $($svc.ComputerName)")) {
					try {
						if ($PsCmdlet.ParameterSetName -match 'Account') {
							Write-Message -Level Verbose -Message "Attempting an account change for service $($svc.ServiceName) on $($svc.ComputerName)"
							$null = Invoke-ManagedComputerCommand -ComputerName $svc.ComputerName -Credential $Credential -ScriptBlock $scriptAccountChange -ArgumentList @($svc.ServiceName, $ServiceCredential.UserName, $ServiceCredential.GetNetworkCredential().Password) -Silent:$Silent
							$outMessage = "The login account for the service has been successfully set."
						}
						elseif ($PsCmdlet.ParameterSetName -match 'Password') {
							Write-Message -Level Verbose -Message "Attempting a password change for service $($svc.ServiceName) on $($svc.ComputerName)"
							$null = Invoke-ManagedComputerCommand -ComputerName $svc.ComputerName -Credential $Credential -ScriptBlock $scriptPasswordChange -ArgumentList @($svc.ServiceName, (New-Object System.Management.Automation.PSCredential ("user", $OldPassword)).GetNetworkCredential().Password, (New-Object System.Management.Automation.PSCredential ("user", $NewPassword)).GetNetworkCredential().Password) -Silent:$Silent
							$outMessage = "The password has been successfully changed."
						}
						$outStatus = 'Successful'
					}
					catch {
						$outStatus = 'Failed'
						$outMessage = $_.Exception.Message
						Write-Message -Level Warning -Message $_.Exception.Message -Silent $Silent
					}
				}
				if ($serviceObject.ServiceType -eq 'Engine' -and $PsCmdlet.ParameterSetName -match 'Account' -and $outStatus -eq 'Successful' -and $agent.State -eq 'Running') {
					#Restart SQL Agent after SQL Engine has been restarted
					$res = Start-DbaSqlService -ComputerName $svc.ComputerName -Type Agent -InstanceName $serviceObject.InstanceName
					if ($res.Status -ne 'Successful') { 
						Write-Message -Level Warning -Message "Failed to restart SQL Agent after changing credentials. $($res.Message)"
					}
				}
				$serviceObject = Get-DbaSqlService -ComputerName $svc.ComputerName -ServiceName $svc.ServiceName -Credential $Credential -Silent:$Silent
				Add-Member -Force -InputObject $serviceObject -NotePropertyName Message -NotePropertyValue $outMessage
				Add-Member -Force -InputObject $serviceObject -NotePropertyName Status -NotePropertyValue $outStatus
				Select-DefaultView -InputObject $serviceObject -Property ComputerName, ServiceName, State, StartName, Status, Message
			}
			Else {
				Stop-Function -Message "The service $($svc.ServiceName) has not been found on $($svc.ComputerName)" -Silent $Silent -Continue
			}
		}
	}
}