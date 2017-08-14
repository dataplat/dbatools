#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#

function Set-DbaAgHadr {
	<#
		.SYNOPSIS
			Changes the Hadr service setting on the specified SQL Server.

		.DESCRIPTION
			In order to build an AG a cluster has to be built and then the Hadr enabled for the SQL Server
			service. This function enables or disables that feature for the SQL Server service.

		.PARAMETER SqlInstance
			The SQL Server that you're connecting to.

		.PARAMETER Credential
			Credential object used to connect to the Windows server itself as a different user

		.PARAMETER Enabled
			Boolean value, supports passing in 0, 1, $true or $false

		.PARAMETER AllowException
			Use this switch to disable any kind of verbose messages

		.PARAMETER WhatIf
			Shows what would happen if the command were to run. No actions are actually performed.

		.PARAMETER Confirm
			Prompts you for confirmation before executing any changing operations within the command.

		.NOTES
			Original Author: Shawn Melton (@wsmelton | http://blog.wsmelton.info)

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Set-DbaAgHadr

		.EXAMPLE
			Set-DbaAgHadr -SqlInstance sql2016 -Enabled 1

			Sets Hadr service to enabled for the instance sql2016

		.EXAMPLE
			Set-DbaAgHadr -SqlInstance sql2012\dev1 Enabled 0

			Sets Hadr service to disabled for the instance dev1 on sq2012
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential]$Credential,
		[boolean]$Enabled,
		[switch]$AllowException
	)
	begin {
		if (Test-Bound 'Enabled') {
			if ($Enabled -eq $null) {
				Stop-Function -Message "A value must be provided for Enabled"
				return
			}
		}
	}
	process {
		if (Test-FunctionInterrupt) { return }
		foreach ($instance in $SqlInstance) {

			try {
				$computer = $instance.ComputerName
				$instanceName = $instance.InstanceName
				$computerName = (Resolve-DbaNetworkName -ComputerName $computer -Credential $Credential).FullComputerName
				Write-Message -Level Verbose -Message "Attempting to connect to $computer"
				$currentState = Invoke-ManagedComputerCommand -ComputerName $computerName -ScriptBlock { $wmi.Services[$args[0]] | Select-Object IsHadrEnabled } -ArgumentList $instanceName -Credential $Credential
			}
			catch {
				Stop-Function -Message "Failure connecting to $computer" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}
			Write-Message -Level Output -Message "Enabled = $Enabled"
			Write-Message -Level Output -Message "IsHadr Enabled = $($currentState.IsHadrEnabled)"
			$noChange = $false
			if ($currentState.IsHadrEnabled -eq $true -and $Enabled -eq 1) {
				Write-Message -Level Warning -Message "Hadr is already enabled on $($instance.FullName)"
				$noChange = $true
				continue
			}
			if ($currentState.IsHadrEnabled -eq $false -and $Enabled -eq 0) {
				Write-Message -Level Warning -Message "Hadr is already disabled on $($instance.FullName)"
				$noChange = $true
				continue
			}

			if ($currentState.IsHadrEnabled -eq $true -and $Enabled -eq 0) {
				if ($PSCmdlet.ShouldProcess($instance, "Disabling Hadr.")) {
					$scriptBlock = {
						$instanceName = $args[0]
						$hadrSet = $args[1]

						$sqlService = $wmi.Services[$instanceName]
						if ($sqlService -eq $true) {
							$sqlService.ChangeHadrServiceSetting($hadrSet)
						}
					}
					Invoke-ManagedComputerCommand -ComputerName $resolvedComputer -ScriptBlock $scriptBlock -ArgumentList $instanceName, $Enabled
				}
			}
			if ($currentState.IsHadrEnabled -eq $false -and $Enabled -eq 1) {
				if ($PSCmdlet.ShouldProcess("$instance", "Enabling Hadr.")) {
					$scriptBlock = {
						$instanceName = $args[0]
						$hadrSet = $args[1]

						$sqlService = $wmi.Services[$instanceName]
						Write-Host "Hadr Current state: $($sqlService.IsHadrEnabled)"
						if ($sqlService -eq $true) {
							$sqlService.ChangeHadrServiceSetting($hadrSet)
							$sqlService.Stop()
							Start-Sleep -Seconds 8
							$sqlService.Start()
						}
					}
					Invoke-ManagedComputerCommand -ComputerName $resolvedComputer -ScriptBlock $scriptBlock -ArgumentList $instanceName, $Enabled
				}
			}
		}
	}
}