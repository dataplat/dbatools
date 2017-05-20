function Copy-DbaAgentAlert {
	<#
	.SYNOPSIS
		Copy-DbaAgentAlert migrates alerts from one SQL Server to another.

	.DESCRIPTION
		By default, all alerts are copied. The -Alert parameter is autopopulated for command-line completion and can be used to copy only specific alerts.

		If the alert already exists on the destination, it will be skipped unless -Force is used.

	.PARAMETER Source
		Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2000 or greater.

	.PARAMETER Destination
		Destination Sql Server. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

	.PARAMETER SourceSqlCredential
		Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

		$scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter.

		Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.
		To connect as a different Windows user, run PowerShell as that user.

	.PARAMETER DestinationSqlCredential
		Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

		$dcred = Get-Credential, then pass this $dcred to the -DestinationSqlCredential parameter.

		Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

		To connect as a different Windows user, run PowerShell as that user.

	.PARAMETER IncludeDefaults
		Copy SQL Agent defaults such as FailSafeEmailAddress, ForwardingServer, and PagerSubjectTemplate.

	.PARAMETER WhatIf
		Shows what would happen if the command were to run. No actions are actually performed.

	.PARAMETER Confirm
		Prompts you for confirmation before executing any changing operations within the command.

	.PARAMETER Force
		Drops and recreates the Alert if it exists

	.PARAMETER Silent
		Use this switch to disable any kind of verbose messages

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

		Copies all alerts from sqlserver2014a to sqlcluster, using Windows credentials. If alerts with the same name exist on sqlcluster, they will be skipped.

	.EXAMPLE
		Copy-DbaAgentAlert -Source sqlserver2014a -Destination sqlcluster -Alert PSAlert -SourceSqlCredential $cred -Force

		Copies a single alert, the PSAlert alert from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If a alert with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

	.EXAMPLE
		Copy-DbaAgentAlert -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

		Shows what would happen if the command were executed using force.
	#>
	[cmdletbinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory = $true)]
		[DbaInstanceParameter]$Source,
		[parameter(Mandatory = $true)]
		[DbaInstanceParameter]$Destination,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SourceSqlCredential,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$DestinationSqlCredential,
		[switch]$IncludeDefaults,
		[switch]$Force,
		[switch]$Silent
	)


	begin {
		$alerts = $psboundparameters.Alerts

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
                    DateTime          = [sqlcollective.dbatools.Utility.DbaDateTime](Get-Date)
                }
				try {
					Write-Message -Message "Creating Alert Defaults" -Level Output
					$sql = $sourceServer.JobServer.AlertSystem.Script() | Out-String
					$sql = $sql -replace [Regex]::Escape("'$source'"), [Regex]::Escape("'$Destination'")

					Write-Message -Message $sql -Level Debug
					$null = $destServer.ConnectionContext.ExecuteNonQuery($sql)
					
					$copyAgentAlertStatus.Status = "Successful"
				}
				catch {
                    $copyAgentAlertStatus.Status = "Failed"
					$copyAgentAlertStatus
					Stop-Function -Message "Issue creating alert defaults" -Category InvalidOperation -InnerErrorRecord $_ -Target $destServer -Continue
				}
				$copyAgentAlertStatus
			}
		}

		foreach ($alert in $serverAlerts) {
			$alertName = $alert.name
            $copyAgentAlertStatus = [pscustomobject]@{
                SourceServer      = $sourceServer.Name
                DestinationServer = $destServer.Name
                Name              = $alertName
                Type              = "Agent Alert"
                Status            = $null
                DateTime          = [sqlcollective.dbatools.Utility.DbaDateTime](Get-Date)
            }

			if ($alerts.count -gt 0 -and $alerts -notcontains $alertName) { 
				continue 
			}

			if ($destAlerts.name -contains $alert.name) {
                if ($force -eq $false) {					
                    $copyAgentAlertStatus.Status = "Skipped"
					$copyAgentAlertStatus
					Write-Message -Message "Alert $alertName exists at destination. Use -Force to drop and migrate." -Level Warning
					continue
				}

				if ($PSCmdlet.ShouldProcess($Destination, "Dropping alert $alertName and recreating")) {
                    try {
                        Write-Message -Message "Dropping Alert $alertName on $destServer" -Level Verbose

                        $sql = "EXEC msdb.dbo.sp_delete_alert @name = N'$($alert.name)';"
                        Write-Message -Message $sql -Level Debug
                        $null = $destServer.ConnectionContext.ExecuteNonQuery($sql)
                    }
                    catch {
                        $copyAgentAlertStatus.Status = "Failed"
						$copyAgentAlertStatus
                        Stop-Function -Message "Issue dropping/recreating alert" -Category InvalidOperation -InnerErrorRecord $_ -Target $destServer -Continue
                    }
				}
			}

            if ($PSCmdlet.ShouldProcess($Destination, "Creating Alert $alertName")) {
                try {
                    <# *****bug w/ SQL Server Event Alerts****
						The severity and scope are unique, and can only be used once per alert. 
						Need to validate a severity is not already in use. However this needs to match the definition of another alert. 
						An alert set to "All Databases" and severity 1 can only exist once. If an alert is set to "model" database with
						severity 1, this is fine.
					#>
                    Write-Message -Message "Copying Alert $alertName" -Level Output
                    $sql = $alert.Script() | Out-String
                    $sql = $sql -replace [Regex]::Escape("'$source'"), [Regex]::Escape("'$Destination'")
                    $sql = $sql -replace "@job_id=N'........-....-....-....-............", "@job_id=N'00000000-0000-0000-0000-000000000000"

                    Write-Message -Message $sql -Level Debug
                    $null = $destServer.ConnectionContext.ExecuteNonQuery($sql)

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
			$notifications = $alert.EnumNotifications()
			$jobName = $alert.JobName

            # JobId = 00000000-0000-0000-0000-000 means the Alertdoes not execute/is attached to a SQL Agent Job.
            if ($alert.JobId -ne '00000000-0000-0000-0000-000000000000') {
                $copyAgentAlertStatus = [pscustomobject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $alertName
                    Type              = "Attach to Job"
                    Status            = $null
                    DateTime          = [sqlcollective.dbatools.Utility.DbaDateTime](Get-Date)
                }
				if ($PSCmdlet.ShouldProcess($Destination, "Adding $alertName to $jobName")) {
                    try {
						<# THERE needs to be validation within this block to see if the $jobName actually exists on the source server. #>
                        Write-Message -Message "Adding $alertName to $jobName" -Level Output
                        $newJob = $destServer.JobServer.Jobs[$jobName]
                        $newJobId = ($newJob.JobId) -replace " ", ""
                        $sql = $sql -replace '00000000-0000-0000-0000-000000000000', $newJobId
                        $sql = $sql -replace 'sp_add_alert', 'sp_update_alert'

                        Write-Message -Message $sql -Level Debug
                        $null = $destServer.ConnectionContext.ExecuteNonQuery($sql)
						
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
                        DateTime          = [sqlcollective.dbatools.Utility.DbaDateTime](Get-Date)
                    }
                    # cant add them this way, we need to modify the existing one or give all options that are supported.
                    foreach ($notify in $notifications) {
                        $notifyCollection = @()
                        if ($notify.UseNetSend -eq $true) {
                            Write-Message -Message "Adding net send" -Level Verbose
                            $notifyCollection += "NetSend"
                        }

                        if ($notify.UseEmail -eq $true) {
                            Write-Message -Message "Adding email" -Level Output
                            $notifyCollection += "NotifyEmail"
                        }

                        if ($notify.UsePager -eq $true) {
                            Write-Message -Message "Adding pager" -Level Output
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
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Copy-SqlAlert
	}
}
