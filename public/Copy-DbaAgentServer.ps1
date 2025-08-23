function Copy-DbaAgentServer {
    <#
    .SYNOPSIS
        Copies all SQL Server Agent objects and server properties between instances.

    .DESCRIPTION
        Migrates complete SQL Server Agent configuration including jobs, operators, alerts, schedules, job categories, and proxies from one instance to another. This function handles the proper sequence of object creation and also copies server-level Agent properties like job history retention settings, error log locations, and database mail profiles. Essential for server migrations, disaster recovery setups, or standardizing Agent configurations across multiple environments without manually recreating dozens of objects.

        You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER Source
        Source SQL Server instance containing the Agent objects you want to copy. All jobs, schedules, operators, alerts, proxies, and server properties will be migrated from this instance.
        Must have sysadmin access and be SQL Server 2000 or higher.

    .PARAMETER SourceSqlCredential
        Authentication credentials for connecting to the Source SQL Server instance. Use this when you need SQL Server authentication instead of Windows authentication.
        Create credentials using Get-Credential and pass them to this parameter. Common when source server is in different domain or requires SQL login.

    .PARAMETER Destination
        Target SQL Server instance(s) where Agent objects will be copied. Accepts multiple instances to copy the same configuration to several servers at once.
        Must have sysadmin access and be SQL Server 2000 or higher. Useful for standardizing Agent configurations across development, test, and production environments.

    .PARAMETER DestinationSqlCredential
        Authentication credentials for connecting to the Destination SQL Server instance(s). Use this when you need SQL Server authentication instead of Windows authentication.
        Create credentials using Get-Credential and pass them to this parameter. Required when destination servers use different authentication than your current context.

    .PARAMETER DisableJobsOnDestination
        Disables all copied jobs on the destination instance after migration completes. Jobs will exist but won't run until manually enabled.
        Use this when copying to test environments where you don't want production jobs running automatically, or during staged migrations where jobs should remain inactive initially.

    .PARAMETER DisableJobsOnSource
        Disables all jobs on the source instance after copying them to destination. Jobs will exist but won't run until manually re-enabled.
        Use this during server migrations when you want to prevent jobs from running on the old server after moving them to the new instance.

    .PARAMETER ExcludeServerProperties
        Skips copying SQL Agent server-level configuration like job history retention settings, error log locations, database mail profiles, and service restart preferences.
        Use this when you only want to copy jobs and schedules but keep the destination server's existing Agent configuration settings intact.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Force
        Overwrites existing Agent objects on destination that have matching names from source. Objects are dropped first, then recreated with source configuration.
        Use this when you want to ensure destination matches source exactly, replacing any existing jobs, operators, or schedules with conflicting names.

    .NOTES
        Tags: Migration, SqlServerAgent, SqlAgent
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

    .LINK
        https://dbatools.io/Copy-DbaAgentServer

    .EXAMPLE
        PS C:\> Copy-DbaAgentServer -Source sqlserver2014a -Destination sqlcluster

        Copies all job server objects from sqlserver2014a to sqlcluster using Windows credentials for authentication. If job objects with the same name exist on sqlcluster, they will be skipped.

    .EXAMPLE
        PS C:\> Copy-DbaAgentServer -Source sqlserver2014a -Destination sqlcluster -SourceSqlCredential $cred

        Copies all job objects from sqlserver2014a to sqlcluster using SQL credentials to authentication to sqlserver2014a and Windows credentials to authenticate to sqlcluster.

    .EXAMPLE
        PS C:\> Copy-DbaAgentServer -Source sqlserver2014a -Destination sqlcluster -WhatIf

        Shows what would happen if the command were executed.

    #>
    [cmdletbinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [Switch]$DisableJobsOnDestination,
        [Switch]$DisableJobsOnSource,
        [switch]$ExcludeServerProperties,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        try {
            $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }
        Invoke-SmoCheck -SqlInstance $sourceServer
        $sourceAgent = $sourceServer.JobServer

        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }
            Invoke-SmoCheck -SqlInstance $destServer
            # All of these support whatif inside of them
            Copy-DbaAgentJobCategory -Source $sourceServer -Destination $destinstance -DestinationSqlCredentia $DestinationSqlCredential -Force:$force

            $destServer.Refresh()
            $destServer.JobServer.Refresh()
            $destServer.JobServer.JobCategories.Refresh()
            $destServer.JobServer.OperatorCategories.Refresh()
            $destServer.JobServer.AlertCategories.Refresh()

            Copy-DbaAgentOperator -Source $sourceServer -Destination $destinstance -DestinationSqlCredentia $DestinationSqlCredential -Force:$force
            $destServer.Refresh()
            $destServer.JobServer.Refresh()
            $destServer.JobServer.Operators.Refresh()

            # extra reconnect to force refresh
            $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential

            Copy-DbaAgentAlert -Source $sourceServer -Destination $destinstance -DestinationSqlCredentia $DestinationSqlCredential -Force:$force -IncludeDefaults
            $destServer.JobServer.Alerts.Refresh()

            Copy-DbaAgentProxy -Source $sourceServer -Destination $destinstance -DestinationSqlCredentia $DestinationSqlCredential -Force:$force
            $destServer.JobServer.ProxyAccounts.Refresh()

            Copy-DbaAgentSchedule -Source $sourceServer -Destination $destinstance -DestinationSqlCredentia $DestinationSqlCredential -Force:$force
            $destServer.JobServer.SharedSchedules.Refresh()

            $destServer.JobServer.Refresh()
            $destServer.Refresh()
            Copy-DbaAgentJob -Source $sourceServer -Destination $destinstance -DestinationSqlCredentia $DestinationSqlCredential -Force:$force -DisableOnDestination:$DisableJobsOnDestination -DisableOnSource:$DisableJobsOnSource

            # To do
            <#
            Copy-DbaAgentMasterServer -Source $sourceServer -Destination $destinstance -DestinationSqlCredentia $DestinationSqlCredential -Force:$force
            Copy-DbaAgentTargetServer -Source $sourceServer -Destination $destinstance -DestinationSqlCredentia $DestinationSqlCredential -Force:$force
            Copy-DbaAgentTargetServerGroup -Source $sourceServer -Destination $destinstance -DestinationSqlCredentia $DestinationSqlCredential -Force:$force
            #>

            <# Here are the properties which must be migrated separately #>
            $copyAgentPropStatus = [PSCustomObject]@{
                SourceServer      = $sourceServer.Name
                DestinationServer = $destServer.Name
                Name              = "Server level properties"
                Type              = "Agent Properties"
                Status            = $null
                Notes             = $null
                DateTime          = [DbaDateTime](Get-Date)
            }

            if ($ExcludeServerProperties) {
                if ($Pscmdlet.ShouldProcess($destinstance, "Skipping Agent Server property copy")) {
                    $copyAgentPropStatus.Status = "Skipped"
                    $copyAgentPropStatus.Notes = $null
                    $copyAgentPropStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                }
            } else {
                if ($Pscmdlet.ShouldProcess($destinstance, "Copying Agent Properties")) {
                    try {
                        Write-Message -Level Verbose -Message "Copying SQL Agent Properties"
                        $sql = $sourceAgent.Script() | Out-String
                        $sql = $sql -replace [Regex]::Escape("'$source'"), "'$destinstance'"
                        $sql = $sql -replace [Regex]::Escape("@errorlog_file="), [Regex]::Escape("--@errorlog_file=")
                        $sql = $sql -replace [Regex]::Escape("@auto_start="), [Regex]::Escape("--@auto_start=")
                        Write-Message -Level Debug -Message $sql
                        $null = $destServer.Query($sql)
                        $copyAgentPropStatus.Status = "Successful"
                        $copyAgentPropStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    } catch {
                        $message = $_.Exception.InnerException.InnerException.InnerException.Message
                        if (-not $message) { $message = $_.Exception.Message }
                        $copyAgentPropStatus.Status = "Failed"
                        $copyAgentPropStatus.Notes = $message
                        $copyAgentPropStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Issue copying SQL Agent properties on $destinstance | $PSItem"
                        continue
                    }
                }
            }
        }
    }
}