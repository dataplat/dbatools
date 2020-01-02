function Copy-DbaAgentSchedule {
    <#
    .SYNOPSIS
        Copy-DbaAgentSchedule migrates shared job schedules from one SQL Server to another.

    .DESCRIPTION
        All shared job schedules are copied.

        If the associated credential for the account does not exist on the destination, it will be skipped. If the shared job schedule already exists on the destination, it will be skipped unless -Force is used.

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

    .PARAMETER Schedule
        Copy only specific schedules. Note that SQL Server allows multiple schedules with the same name. Use Id for more accurate schedule copies.

    .PARAMETER Id
        Copy only specific schedule.

    .PARAMETER InputObject
        Enables piping from Get-DbaAgentSchedule

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER Force
        If this switch is enabled, the Operator will be dropped and recreated on Destination.

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
        https://dbatools.io/Copy-DbaAgentSchedule

    .EXAMPLE
        PS C:\> Copy-DbaAgentSchedule -Source sqlserver2014a -Destination sqlcluster

        Copies all shared job schedules from sqlserver2014a to sqlcluster using Windows credentials. If shared job schedules with the same name exist on sqlcluster, they will be skipped.

    .EXAMPLE
        PS C:\> Copy-DbaAgentSchedule -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

        Shows what would happen if the command were executed using force.

    .EXAMPLE
        PS C:\> Get-DbaAgentSchedule -SqlInstance sql2016 | Out-GridView -Passthru | Copy-DbaAgentSchedule -Destination sqlcluster

        Gets a list of schedule, outputs to a gridview which can be selected from, then copies to SqlInstance
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [string[]]$Schedule,
        [int[]]$Id,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Agent.JobSchedule[]]$InputObject,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if ($Source) {
            try {
                $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $Source" -Category ConnectionError -ErrorRecord $_ -Target $Source
                return
            }

            if (-not $InputObject) {
                $InputObject = Get-DbaAgentSchedule -SqlInstance $sourceServer -Schedule $Schedule -Id $Id
            }
        }
        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        if (-not $PSBoundParameters.Source -and -not $PSBoundParameters.InputObject) {
            Stop-Function -Message "You must specify either Source or pipe in results from Get-DbaAgentSchedule"
            return
        }

        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-SqlInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $destinstance" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }

            $destSchedules = Get-DbaAgentSchedule -SqlInstance $destServer -Schedule $Schedule

            foreach ($currentschedule in $InputObject) {
                $scheduleName = $currentschedule.Name
                $sourceServer = $currentschedule.Parent.Parent
                $copySharedScheduleStatus = [pscustomobject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Type              = "Agent Schedule"
                    Name              = $scheduleName
                    Status            = $null
                    Notes             = $null
                    DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
                }

                if ($destSchedules.Name -contains $scheduleName) {
                    if ($Force -ne $true) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Shared job schedule $scheduleName exists at destination. Use -Force to drop and migrate.")) {
                            $copySharedScheduleStatus.Status = "Skipped"
                            $copySharedScheduleStatus.Notes = "Already exists on destination"
                            $copySharedScheduleStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Level Verbose -Message "Shared job schedule $scheduleName exists at destination. Use -Force to drop and migrate."
                            continue
                        }
                    } else {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Schedule [$scheduleName] has associated jobs. Skipping.")) {
                            if ($destServer.JobServer.Jobs.JobSchedules.Name -contains $scheduleName) {
                                $copySharedScheduleStatus.Status = "Skipped"
                                $copySharedScheduleStatus.Notes = "Schedule has associated jobs"
                                $copySharedScheduleStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                Write-Message -Level Verbose -Message "Schedule [$scheduleName] has associated jobs. Skipping."
                                continue
                            }
                        } else {
                            if ($Pscmdlet.ShouldProcess($destinstance, "Dropping schedule $scheduleName and recreating")) {
                                try {
                                    Write-Message -Level Verbose -Message "Dropping schedule $scheduleName"
                                    $destServer.JobServer.SharedSchedules[$scheduleName].Drop()
                                } catch {
                                    $copySharedScheduleStatus.Status = "Failed"
                                    $copySharedScheduleStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                    Stop-Function -Message "Issue dropping schedule" -Target $scheduleName -ErrorRecord $_ -Continue
                                }
                            }
                        }
                    }
                }

                if ($Pscmdlet.ShouldProcess($destinstance, "Creating schedule $scheduleName")) {
                    try {
                        Write-Message -Level Verbose -Message "Copying schedule $scheduleName"
                        $sql = $currentschedule.Script() | Out-String

                        Write-Message -Level Debug -Message $sql
                        $destServer.Query($sql)

                        $copySharedScheduleStatus.Status = "Successful"
                        $copySharedScheduleStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    } catch {
                        $copySharedScheduleStatus.Status = "Failed"
                        $copySharedScheduleStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Stop-Function -Message "Issue creating schedule" -Target $scheduleName -ErrorRecord $_ -Continue
                    }
                }
            }
        }
    }
}