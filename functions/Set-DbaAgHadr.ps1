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

		.PARAMETER WhatIf
			Shows what would happen if the command were to run. No actions are actually performed.

		.PARAMETER Confirm
			Prompts you for confirmation before executing any changing operations within the command.

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages

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
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
	param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential]$Credential,
		[boolean]$Enabled,
		[switch]$Force,
		[switch]$Silent
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
			$computer = $instance.ComputerName
			$instanceName = $instance.InstanceName

			$noChange = $false

			switch ($instance.InstanceName) {
				'MSSQLSERVER' { $agentName = 'SQLSERVERAGENT' }
				default { $agentName = "SQLAgent`$$instanceName" }
			}

			try {
				Write-Message -Level Verbose -Message "Checking current Hadr setting for $computer"
				$computerFullName = (Resolve-DbaNetworkName -ComputerName $computer -Credential $Credential -Silent).FullComputerName
				$currentState = Get-DbaAgHadr -SqlInstance $instance
			}
			catch {
				Stop-Function -Message "Failure to pull current state of Hadr setting on $computer" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}

			$isHadrEnabled = $currentState.IsHadrEnabled
			Write-Message -Level InternalComment -Message "$instance Hadr current value: $isHadrEnabled"

			if ($isHadrEnabled -eq $true -and $Enabled -eq 1) {
				Write-Message -Level Warning -Message "Hadr is already enabled for instance: $($instance.FullName)"
				$noChange = $true
				continue
			}
			if ($isHadrEnabled -eq $false -and $Enabled -eq 0) {
				Write-Message -Level Warning -Message "Hadr is already disabled for instance: $($instance.FullName)"
				$noChange = $true
				continue
			}

			# $scriptBlock = {
			# 	$instanceName = $args[0]
			# 	$agentName = $args[1]
			# 	$hadrSet = $args[2]
			# 	$force = $args[3]

			# 	$wmi.Services[$instanceName].ChangeHadrServiceSetting($hadrSet)
			# 	if ($force) {
			# 		$wmi.Services[$instanceName].Stop()
			# 		Start-Sleep -Seconds 8
			# 		$wmi.Services[$instanceName].Start()

			# 		if ($wmi.Services[$agentName].ServiceState -ne 'Running') {
			# 			$wmi.Services[$agentName].Start()
			# 		}
			# 	}
			# }
			$sqlwmi = new-object ('Microsoft.SqlServer.Management.Smo.WMI.ManagedComputer') $computerFullName
			$sqlService = $sqlwmi.Services[$instanceName]
			$agentService = $sqlwmi.Services[$agentName]

			if ($noChange -eq $false) {
				if ($PSCmdlet.ShouldProcess($instance,"Changing Hadr from $isHadrEnabled to $Enabled for $instance")) {
					$sqlService.ChangeHadrServiceSetting($Enabled)
				}
				if (Test-Bound 'Force') {
					if ($PSCmdlet.ShouldProcess($instance,"Force provided, restarting Engine and Agent service for $instance on $computerFullName")) {
						try {
							<# have to call it twice until command is fixed #>
							Stop-DbaSqlService -ComputerName $computerFullName -InstanceName $instanceName -Type Agent,Engine
							Start-DbaSqlService -ComputerName $computerFullName -InstanceName $instanceName -Type Agent,Engine
						}
						catch {
							Stop-Function -Message "Issue restarting $instance" -Target $instance -Continue
						}
					}
				}
			}
		} # foreach instance
	}
}