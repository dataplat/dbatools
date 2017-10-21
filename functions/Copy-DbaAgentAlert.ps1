function Copy-DbaAgentAlert {
	<#
		.SYNOPSIS
			Copy-DbaAgentAlert migrates alerts from one SQL Server to another.

		.DESCRIPTION
			By default, all alerts are copied. The -Alert parameter is auto-populated for command-line completion and can be used to copy only specific alerts.

			If the alert already exists on the destination, it will be skipped unless -Force is used.

		.PARAMETER Source
			Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

		.PARAMETER SourceSqlCredential
			Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

			$scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter.

			Windows Authentication will be used if SourceSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER Destination
			Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2000 or higher.

		.PARAMETER DestinationSqlCredential
			Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

			$dcred = Get-Credential, then pass this $dcred to the -DestinationSqlCredential parameter.

			Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER Alert
			The alert(s) to process. This list is auto-populated from the server. If unspecified, all alerts will be processed.

		.PARAMETER ExcludeAlert
			The alert(s) to exclude. This list is auto-populated from the server.

		.PARAMETER IncludeDefaults
			Copy SQL Agent defaults such as FailSafeEmailAddress, ForwardingServer, and PagerSubjectTemplate.

		.PARAMETER WhatIf
			If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

		.PARAMETER Confirm
			If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

		.PARAMETER Force
			If this switch is enabled, the Alert will be dropped and recreated on Destination.

		.PARAMETER EnableException
			By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
			This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
			Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
			
		.NOTES
			Tags: Migration, Agent
			Author: Chrissy LeMaire (@cl), netnerds.net
			Requires: sysadmin access on SQL Servers

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Copy-DbaAgentAlert

		.EXAMPLE
			Copy-DbaAgentAlert -Source sqlserver2014a -Destination sqlcluster

			Copies all alerts from sqlserver2014a to sqlcluster using Windows credentials. If alerts with the same name exist on sqlcluster, they will be skipped.

		.EXAMPLE
			Copy-DbaAgentAlert -Source sqlserver2014a -Destination sqlcluster -Alert PSAlert -SourceSqlCredential $cred -Force

			Copies a only the alert named PSAlert from sqlserver2014a to sqlcluster using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If a alert with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

		.EXAMPLE
			Copy-DbaAgentAlert -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

			Shows what would happen if the command were executed using force.
	#>
	[cmdletbinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory = $true)]
		[DbaInstanceParameter]$Source,
		[PSCredential]
		$SourceSqlCredential,
		[parameter(Mandatory = $true)]
		[DbaInstanceParameter]$Destination,
		[PSCredential]
		$DestinationSqlCredential,
		[object[]]$Alert,
		[object[]]$ExcludeAlert,
		[switch]$IncludeDefaults,
		[switch]$Force,
		[switch][Alias('Silent')]$EnableException
	)

	begin {
		$sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
		$destServer = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential

		$source = $sourceServer.DomainInstanceName
		$Destination = $destServer.DomainInstanceName

	}
	process {

		$serverAlerts = $sourceServer.JobServer.Alerts
		$destAlerts = $destServer.JobServer.Alerts

		if ($IncludeDefaults -eq $true) {
			if ($PSCmdlet.ShouldProcess($Destination, "Creating Alert Defaults")) {
				$copyAgentAlertStatus = [pscustomobject]@{
					SourceServer      = $sourceServer.Name
					DestinationServer = $destServer.Name
					Name              = "Alert Defaults"
					Type              = "Alert Defaults"
					Status            = $null
					DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
				}
				try {
					Write-Message -Message "Creating Alert Defaults" -Level Verbose
					$sql = $sourceServer.JobServer.AlertSystem.Script() | Out-String
					$sql = $sql -replace [Regex]::Escape("'$source'"), "'$Destination'"

					Write-Message -Message $sql -Level Debug
					$null = $destServer.Query($sql)

					$copyAgentAlertStatus.Status = "Successful"
				}
				catch {
					$copyAgentAlertStatus.Status = "Failed"
					$copyAgentAlertStatus
					Stop-Function -Message "Issue creating alert defaults." -Category InvalidOperation -InnerErrorRecord $_ -Target $destServer -Continue
				}
				$copyAgentAlertStatus
			}
		}

		foreach ($serverAlert in $serverAlerts) {
			$alertName = $serverAlert.name
			$copyAgentAlertStatus = [pscustomobject]@{
				SourceServer      = $sourceServer.Name
				DestinationServer = $destServer.Name
				Name              = $alertName
				Type              = "Agent Alert"
				Status            = $null
				DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
			}

			if (($Alert -and $Alert -notcontains $alertName) -or ($ExcludeAlert -and $ExcludeAlert -contains $alertName)) {
				continue
			}

			if ($destAlerts.name -contains $serverAlert.name) {
				if ($force -eq $false) {
					$copyAgentAlertStatus.Status = "Skipped"
					$copyAgentAlertStatus
					Write-Message -Message "Alert [$alertName] exists at destination. Use -Force to drop and migrate." -Level Warning
					continue
				}

				if ($PSCmdlet.ShouldProcess($Destination, "Dropping alert $alertName and recreating")) {
					try {
						Write-Message -Message "Dropping Alert $alertName on $destServer." -Level Verbose

						$sql = "EXEC msdb.dbo.sp_delete_alert @name = N'$($alertname)';"
						Write-Message -Message $sql -Level Debug
						$null = $destServer.Query($sql)
					}
					catch {
						$copyAgentAlertStatus.Status = "Failed"
						$copyAgentAlertStatus
						Stop-Function -Message "Issue dropping/recreating alert" -Category InvalidOperation -InnerErrorRecord $_ -Target $destServer -Continue
					}
				}
			}

			$destSevConflict = $destAlerts | Where-Object Severity -eq $serverAlert.Severity
			$destSevDbConflict = $destAlerts | Where-Object { $_.Severity -eq $serverAlert.Severity -and $_.DatabaseName -eq $serverAlert.DatabaseName }
			if ($destSevConflict) {
				Write-Message -Level Warning -Message "Alert [$($destSevConflict.Name)] has already been defined to use the severity $($serverAlert.Severity). Skipping."

				$copyAgentAlertStatus.Status = "Skipped"
				$copyAgentAlertStatus
				continue
			}
			if ($destSevDbConflict) {
				Write-Message -Level Warning -Message "Alert [$($destSevConflict.Name)] has already been defined to use the severity $($serverAlert.Severity) on database $($severAlert.DatabaseName). Skipping."

				$copyAgentAlertStatus.Status = "Skipped"
				$copyAgentAlertStatus
				continue
			}

			if ($serverAlert.JobName -and $destServer.JobServer.Jobs.Name -NotContains $serverAlert.JobName) {
				Write-Message -Level Warning -Message "Alert [$alertName] has job [$($serverAlert.JobName)] configured as response. The job does not exist on destination $destServer. Skipping."

				$copyAgentAlertStatus.Status = "Skipped"
				$copyAgentAlertStatus
				continue
			}

			if ($PSCmdlet.ShouldProcess($Destination, "Creating Alert $alertName")) {
				try {
					Write-Message -Message "Copying Alert $alertName" -Level Verbose
					$sql = $serverAlert.Script() | Out-String
					$sql = $sql -replace "@job_id=N'........-....-....-....-............", "@job_id=N'00000000-0000-0000-0000-000000000000"

					Write-Message -Message $sql -Level Debug
					$null = $destServer.Query($sql)

					$copyAgentAlertStatus.Status = "Successful"
					$copyAgentAlertStatus
				}
				catch {
					$copyAgentAlertStatus.Status = "Failed"
					$copyAgentAlertStatus
					Stop-Function -Message "Issue creating alert" -Category InvalidOperation -InnerErrorRecord $_ -Target $destServer -Continue
				}
			}

			$destServer.JobServer.Alerts.Refresh()
			$destServer.JobServer.Jobs.Refresh()

			$newAlert = $destServer.JobServer.Alerts[$alertName]
			$notifications = $serverAlert.EnumNotifications()
			$jobName = $serverAlert.JobName

			# JobId = 00000000-0000-0000-0000-000 means the Alert does not execute/is attached to a SQL Agent Job.
			if ($serverAlert.JobId -ne '00000000-0000-0000-0000-000000000000') {
				$copyAgentAlertStatus = [pscustomobject]@{
					SourceServer      = $sourceServer.Name
					DestinationServer = $destServer.Name
					Name              = $alertName
					Type              = "Attach to Job"
					Status            = $null
					DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
				}
				if ($PSCmdlet.ShouldProcess($Destination, "Adding $alertName to $jobName")) {
					try {
						<# THERE needs to be validation within this block to see if the $jobName actually exists on the source server. #>
						Write-Message -Message "Adding $alertName to $jobName" -Level Verbose
						$newJob = $destServer.JobServer.Jobs[$jobName]
						$newJobId = ($newJob.JobId) -replace " ", ""
						$sql = $sql -replace '00000000-0000-0000-0000-000000000000', $newJobId
						$sql = $sql -replace 'sp_add_alert', 'sp_update_alert'

						Write-Message -Message $sql -Level Debug
						$null = $destServer.Query($sql)

						$copyAgentAlertStatus.Status = "Successful"
						$copyAgentAlertStatus
					}
					catch {
						$copyAgentAlertStatus.Status = "Failed"
						$copyAgentAlertStatus
						Stop-Function -Message "Issue adding alert to job" -Category InvalidOperation -InnerErrorRecord $_ -Target $destServer
					}
				}
			}

			if ($PSCmdlet.ShouldProcess($Destination, "Moving Notifications $alertName")) {
				try {
					$copyAgentAlertStatus = [pscustomobject]@{
						SourceServer      = $sourceServer.Name
						DestinationServer = $destServer.Name
						Name              = $alertName
						Type              = "Notifications"
						Status            = $null
						DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
					}
					# cant add them this way, we need to modify the existing one or give all options that are supported.
					foreach ($notify in $notifications) {
						$notifyCollection = @()
						if ($notify.UseNetSend -eq $true) {
							Write-Message -Message "Adding net send" -Level Verbose
							$notifyCollection += "NetSend"
						}

						if ($notify.UseEmail -eq $true) {
							Write-Message -Message "Adding email" -Level Verbose
							$notifyCollection += "NotifyEmail"
						}

						if ($notify.UsePager -eq $true) {
							Write-Message -Message "Adding pager" -Level Verbose
							$notifyCollection += "Pager"
						}

						$notifyMethods = $notifyCollection -join ", "
						$newAlert.AddNotification($notify.OperatorName, [Microsoft.SqlServer.Management.Smo.Agent.NotifyMethods]$notifyMethods)
					}
					$copyAgentAlertStatus.Status = "Successful"
					$copyAgentAlertStatus
				}
				catch {
					$copyAgentAlertStatus.Status = "Failed"
					$copyAgentAlertStatus
					Stop-Function -Message "Issue moving notifications for the alert" -Category InvalidOperation -InnerErrorRecord $_ -Target $destServer
				}
			}
		}
	}
	end {
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Copy-SqlAlert
	}
}
