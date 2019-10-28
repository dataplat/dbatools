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
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2000 or higher.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

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

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

    .LINK
        https://dbatools.io/Copy-DbaAgentAlert

    .EXAMPLE
        PS C:\> Copy-DbaAgentAlert -Source sqlserver2014a -Destination sqlcluster

        Copies all alerts from sqlserver2014a to sqlcluster using Windows credentials. If alerts with the same name exist on sqlcluster, they will be skipped.

    .EXAMPLE
        PS C:\> Copy-DbaAgentAlert -Source sqlserver2014a -Destination sqlcluster -Alert PSAlert -SourceSqlCredential $cred -Force

        Copies a only the alert named PSAlert from sqlserver2014a to sqlcluster using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If an alert with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

    .EXAMPLE
        PS C:\> Copy-DbaAgentAlert -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

        Shows what would happen if the command were executed using force.

    #>
    [cmdletbinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [object[]]$Alert,
        [object[]]$ExcludeAlert,
        [switch]$IncludeDefaults,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        try {
            $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
            $serverAlerts = $sourceServer.JobServer.Alerts
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $Source" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }
        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-SqlInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $destinstance" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }
            $destAlerts = $destServer.JobServer.Alerts

            if ($IncludeDefaults -eq $true) {
                if ($PSCmdlet.ShouldProcess($destinstance, "Creating Alert Defaults")) {
                    $copyAgentAlertStatus = [pscustomobject]@{
                        SourceServer      = $sourceServer.Name
                        DestinationServer = $destServer.Name
                        Name              = "Alert Defaults"
                        Type              = "Alert Defaults"
                        Status            = $null
                        Notes             = $null
                        DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
                    }
                    try {
                        Write-Message -Message "Creating Alert Defaults" -Level Verbose
                        $sql = $sourceServer.JobServer.AlertSystem.Script() | Out-String
                        $sql = $sql -replace [Regex]::Escape("'$source'"), "'$destinstance'"

                        Write-Message -Message $sql -Level Debug
                        $null = $destServer.Query($sql)

                        $copyAgentAlertStatus.Status = "Successful"
                    } catch {
                        $copyAgentAlertStatus.Status = "Failed"
                        $copyAgentAlertStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Stop-Function -Message "Issue creating alert defaults." -Category InvalidOperation -ErrorRecord $_ -Target $destServer -Continue
                    }
                    $copyAgentAlertStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                }
            }

            $destServerOperators = $destServer.JobServer.Operators

            foreach ($serverAlert in $serverAlerts) {
                $alertName = $serverAlert.name
                $copyAgentAlertStatus = [pscustomobject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $alertName
                    Type              = "Agent Alert"
                    Notes             = $null
                    Status            = $null
                    DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
                }
                if (($Alert -and $Alert -notcontains $alertName) -or ($ExcludeAlert -and $ExcludeAlert -contains $alertName)) {
                    continue
                }

                if ($serverAlert.HasNotification) {
                    $alertOperators = $serverAlert.EnumNotifications()
                    if ($destServerOperators.Name -notin $alertOperators.OperatorName) {
                        $missingOperators = ($alertOperators | Where-Object OperatorName -NotIn $destServerOperators.Name).OperatorName
                        if ($missingOperators.Count -gt 0 -or $missingOperators.Length -gt 0) {
                            $operatorList = $missingOperators -join ','
                            if ($PSCmdlet.ShouldProcess($destinstance, "Missing operator(s) at destination.")) {
                                $copyAgentAlertStatus.Status = "Skipped"
                                $copyAgentAlertStatus.Notes = "Operator(s) [$operatorList] do not exist on destination"
                                $copyAgentAlertStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                Write-Message -Message "One or more operators alerted by [$alertName] is not present at the destination. Alert will not be copied. Use Copy-DbaAgentOperator to copy the operator(s) to the destination. Missing operator(s): $operatorList" -Level Warning
                                continue
                            }
                        }
                    }
                }

                if ($destAlerts.name -contains $serverAlert.name) {
                    if ($force -eq $false) {
                        if ($PSCmdlet.ShouldProcess($destinstance, "Alert [$alertName] exists at destination. Use -Force to drop and migrate.")) {
                            $copyAgentAlertStatus.Status = "Skipped"
                            $copyAgentAlertStatus.Notes = "Already exists on destination"
                            $copyAgentAlertStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Message "Alert [$alertName] exists at destination. Use -Force to drop and migrate." -Level Verbose
                        }
                        continue
                    }

                    if ($PSCmdlet.ShouldProcess($destinstance, "Dropping alert $alertName and recreating")) {
                        try {
                            Write-Message -Message "Dropping Alert $alertName on $destServer." -Level Verbose

                            $sql = "EXEC msdb.dbo.sp_delete_alert @name = N'$($alertname)';"
                            Write-Message -Message $sql -Level Debug
                            $null = $destServer.Query($sql)
                            $destAlerts.Refresh()
                        } catch {
                            $copyAgentAlertStatus.Status = "Failed"
                            $copyAgentAlertStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Stop-Function -Message "Issue dropping/recreating alert" -Category InvalidOperation -ErrorRecord $_ -Target $destServer -Continue
                        }
                    }
                }

                if ($destAlerts | Where-Object { $_.Severity -eq $serverAlert.Severity -and $_.MessageID -eq $serverAlert.MessageID -and $_.DatabaseName -eq $serverAlert.DatabaseName -and $_.EventDescriptionKeyword -eq $serverAlert.EventDescriptionKeyword }) {
                    if ($PSCmdlet.ShouldProcess($destinstance, "Checking for conflicts")) {
                        $conflictMessage = "Alert [$alertName] has already been defined to use"
                        if ($serverAlert.Severity -gt 0) { $conflictMessage += " severity $($serverAlert.Severity)" }
                        if ($serverAlert.MessageID -gt 0) { $conflictMessage += " error number $($serverAlert.MessageID)" }
                        if ($serverAlert.DatabaseName) { $conflictMessage += " on database '$($serverAlert.DatabaseName)'" }
                        if ($serverAlert.EventDescriptionKeyword) { $conflictMessage += " with error text '$($serverAlert.Severity)'" }
                        $conflictMessage += ". Skipping."

                        Write-Message -Level Verbose -Message $conflictMessage
                        $copyAgentAlertStatus.Status = "Skipped"
                        $copyAgentAlertStatus.Notes = $conflictMessage
                        $copyAgentAlertStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    }
                    continue
                }
                if ($serverAlert.JobName -and $destServer.JobServer.Jobs.Name -NotContains $serverAlert.JobName) {
                    Write-Message -Level Verbose -Message "Alert [$alertName] has job [$($serverAlert.JobName)] configured as response. The job does not exist on destination $destServer. Skipping."
                    if ($PSCmdlet.ShouldProcess($destinstance, "Checking for conflicts")) {
                        $copyAgentAlertStatus.Status = "Skipped"
                        $copyAgentAlertStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    }
                    continue
                }

                if ($PSCmdlet.ShouldProcess($destinstance, "Creating Alert $alertName")) {
                    try {
                        Write-Message -Message "Copying Alert $alertName" -Level Verbose
                        $sql = $serverAlert.Script() | Out-String
                        $sql = $sql -replace "@job_id=N'........-....-....-....-............", "@job_id=N'00000000-0000-0000-0000-000000000000"

                        Write-Message -Message $sql -Level Debug
                        $null = $destServer.Query($sql)

                        $copyAgentAlertStatus.Status = "Successful"
                        $copyAgentAlertStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    } catch {
                        $copyAgentAlertStatus.Status = "Failed"
                        $copyAgentAlertStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Stop-Function -Message "Issue creating alert" -Category InvalidOperation -ErrorRecord $_ -Target $destServer -Continue
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
                        Type              = "Agent Alert Job Association"
                        Notes             = "Associated with $jobName"
                        Status            = $null
                        DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
                    }
                    if ($PSCmdlet.ShouldProcess($destinstance, "Adding $alertName to $jobName")) {
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
                            $copyAgentAlertStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        } catch {
                            $copyAgentAlertStatus.Status = "Failed"
                            $copyAgentAlertStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Stop-Function -Message "Issue adding alert to job" -Category InvalidOperation -ErrorRecord $_ -Target $destServer
                        }
                    }
                }

                if ($PSCmdlet.ShouldProcess($destinstance, "Moving Notifications $alertName")) {
                    try {
                        $copyAgentAlertStatus = [pscustomobject]@{
                            SourceServer      = $sourceServer.Name
                            DestinationServer = $destServer.Name
                            Name              = $alertName
                            Type              = "Agent Alert Notification"
                            Notes             = $null
                            Status            = $null
                            DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
                        }
                        # can't add them this way, we need to modify the existing one or give all options that are supported.
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
                        $copyAgentAlertStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    } catch {
                        $copyAgentAlertStatus.Status = "Failed"
                        $copyAgentAlertStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Stop-Function -Message "Issue moving notifications for the alert" -Category InvalidOperation -ErrorRecord $_ -Target $destServer
                    }
                }
            }
        }
    }
}