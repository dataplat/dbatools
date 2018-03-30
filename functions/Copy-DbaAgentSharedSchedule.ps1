function Copy-DbaAgentSharedSchedule {
    <#
        .SYNOPSIS
            Copy-DbaAgentSharedSchedule migrates shared job schedules from one SQL Server to another.

        .DESCRIPTION
            All shared job schedules are copied.

            If the associated credential for the account does not exist on the destination, it will be skipped. If the shared job schedule already exists on the destination, it will be skipped unless -Force is used.

        .PARAMETER Source
            Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

        .PARAMETER SourceSqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Destination
            Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2000 or higher.

        .PARAMETER DestinationSqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

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
            Requires: sysadmin access on SQL Servers

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Copy-DbaAgentSharedSchedule

        .EXAMPLE
            Copy-DbaAgentSharedSchedule -Source sqlserver2014a -Destination sqlcluster

            Copies all shared job schedules from sqlserver2014a to sqlcluster using Windows credentials. If shared job schedules with the same name exist on sqlcluster, they will be skipped.

        .EXAMPLE
            Copy-DbaAgentSharedSchedule -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

            Shows what would happen if the command were executed using force.
    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
    param (
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter]$Source,
        [PSCredential]
        $SourceSqlCredential,
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter]$Destination,
        [PSCredential]
        $DestinationSqlCredential,
        [switch]$Force,
        [Alias('Silent')]
        [switch]$EnableException
    )

    begin {
        $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        $destServer = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential

        $source = $sourceServer.DomainInstanceName
        $destination = $destServer.DomainInstanceName

        if ($sourceServer.VersionMajor -lt 9 -or $destServer.VersionMajor -lt 9) {
            throw "Server SharedSchedules are only supported in SQL Server 2005 and above. Quitting."
        }

        $serverSchedules = $sourceServer.JobServer.SharedSchedules
        $destSchedules = $destServer.JobServer.SharedSchedules
    }
    process {
        foreach ($schedule in $serverSchedules) {
            $scheduleName = $schedule.Name
            $copySharedScheduleStatus = [pscustomobject]@{
                SourceServer      = $sourceServer.Name
                DestinationServer = $destServer.Name
                Type              = "Agent Schedule"
                Name              = $scheduleName
                Status            = $null
                Notes             = $null
                DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
            }

            if ($schedules.Length -gt 0 -and $schedules -notcontains $scheduleName) {
                continue
            }

            if ($destSchedules.Name -contains $scheduleName) {
                if ($force -eq $false) {
                    $copySharedScheduleStatus.Status = "Skipped"
                    $copySharedScheduleStatus.Notes = "Already exists"
                    $copySharedScheduleStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    Write-Message -Level Verbose -Message "Shared job schedule $scheduleName exists at destination. Use -Force to drop and migrate."
                    continue
                }
                else {
                    if ($destServer.JobServer.Jobs.JobSchedules.Name -contains $scheduleName) {
                        $copySharedScheduleStatus.Status = "Skipped"
                        $copySharedScheduleStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Schedule [$scheduleName] has associated jobs. Skipping."
                        continue
                    }
                    else {
                        if ($Pscmdlet.ShouldProcess($destination, "Dropping schedule $scheduleName and recreating")) {
                            try {
                                Write-Message -Level Verbose -Message "Dropping schedule $scheduleName"
                                $destServer.JobServer.SharedSchedules[$scheduleName].Drop()
                            }
                            catch {
                                $copySharedScheduleStatus.Status = "Failed"
                                $copySharedScheduleStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                Stop-Function -Message "Issue dropping schedule" -Target $scheduleName -InnerErrorRecord $_ -Continue
                            }
                        }
                    }
                }
            }

            if ($Pscmdlet.ShouldProcess($destination, "Creating schedule $scheduleName")) {
                try {
                    Write-Message -Level Verbose -Message "Copying schedule $scheduleName"
                    $sql = $schedule.Script() | Out-String

                    Write-Message -Level Debug -Message $sql
                    $destServer.Query($sql)

                    $copySharedScheduleStatus.Status = "Successful"
                    $copySharedScheduleStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                }
                catch {
                    $copySharedScheduleStatus.Status = "Failed"
                    $copySharedScheduleStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    Stop-Function -Message "Issue creating schedule" -Target $scheduleName -InnerErrorRecord $_ -Continue
                }
            }
        }
    }
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Copy-SqlSharedSchedule
    }
}
