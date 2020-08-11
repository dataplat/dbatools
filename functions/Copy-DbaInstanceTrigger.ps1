function Copy-DbaInstanceTrigger {
    <#
    .SYNOPSIS
        Copy-DbaInstanceTrigger migrates server triggers from one SQL Server to another.

    .DESCRIPTION
        By default, all triggers are copied. The -ServerTrigger parameter is auto-populated for command-line completion and can be used to copy only specific triggers.

        If the trigger already exists on the destination, it will be skipped unless -Force is used.

    .PARAMETER Source
        Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SourceSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        Destination Sql Server. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER ServerTrigger
        The Server Trigger(s) to process - this list is auto-populated from the server. If unspecified, all Server Triggers will be processed.

    .PARAMETER ExcludeServerTrigger
        The Server Trigger(s) to exclude - this list is auto-populated from the server

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER Force
        Drops and recreates the Trigger if it exists

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

    .LINK
        https://dbatools.io/Copy-DbaInstanceTrigger

    .EXAMPLE
        PS C:\> Copy-DbaInstanceTrigger -Source sqlserver2014a -Destination sqlcluster

        Copies all server triggers from sqlserver2014a to sqlcluster, using Windows credentials. If triggers with the same name exist on sqlcluster, they will be skipped.

    .EXAMPLE
        PS C:\> Copy-DbaInstanceTrigger -Source sqlserver2014a -Destination sqlcluster -ServerTrigger tg_noDbDrop -SourceSqlCredential $cred -Force

        Copies a single trigger, the tg_noDbDrop trigger from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If a trigger with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

    .EXAMPLE
        PS C:\> Copy-DbaInstanceTrigger -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

        Shows what would happen if the command were executed using force.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [PSCredential]
        $SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]
        $DestinationSqlCredential,
        [object[]]$ServerTrigger,
        [object[]]$ExcludeServerTrigger,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        try {
            $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 9
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $Source" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }
        $serverTriggers = $sourceServer.Triggers

        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-SqlInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $destinstance" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }
            if ($destServer.VersionMajor -lt $sourceServer.VersionMajor) {
                Stop-Function -Message "Migration from version $($destServer.VersionMajor) to version $($sourceServer.VersionMajor) is not supported."
                return
            }
            $destTriggers = $destServer.Triggers

            foreach ($trigger in $serverTriggers) {
                $triggerName = $trigger.Name

                $copyTriggerStatus = [pscustomobject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $triggerName
                    Type              = "Server Trigger"
                    Status            = $null
                    Notes             = $null
                    DateTime          = [DbaDateTime](Get-Date)
                }

                if ($ServerTrigger -and $triggerName -notin $ServerTrigger -or $triggerName -in $ExcludeServerTrigger) {
                    continue
                }

                if ($destTriggers.Name -contains $triggerName) {
                    if ($force -eq $false) {
                        Write-Message -Level Verbose -Message "Server trigger $triggerName exists at destination. Use -Force to drop and migrate."

                        $copyTriggerStatus.Status = "Skipped"
                        $copyTriggerStatus.Notes = "Already exists on destination"
                        $copyTriggerStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        continue
                    } else {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Dropping server trigger $triggerName and recreating")) {
                            try {
                                Write-Message -Level Verbose -Message "Dropping server trigger $triggerName"
                                $destServer.Triggers[$triggerName].Drop()
                            } catch {
                                $copyTriggerStatus.Status = "Failed"
                                $copyTriggerStatus.Notes = (Get-ErrorMessage -Record $_)
                                $copyTriggerStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                                Stop-Function -Message "Issue dropping trigger on destination" -Target $triggerName -ErrorRecord $_ -Continue
                            }
                        }
                    }
                }

                if ($Pscmdlet.ShouldProcess($destinstance, "Creating server trigger $triggerName")) {
                    try {
                        Write-Message -Level Verbose -Message "Copying server trigger $triggerName"
                        $sql = $trigger.Script() | Out-String
                        $sql = $sql -replace "CREATE TRIGGER", "`nGO`nCREATE TRIGGER"
                        $sql = $sql -replace "ENABLE TRIGGER", "`nGO`nENABLE TRIGGER"
                        Write-Message -Level Debug -Message $sql

                        foreach ($query in ($sql -split '\nGO\b')) {
                            $destServer.Query($query) | Out-Null
                        }

                        $copyTriggerStatus.Status = "Successful"
                        $copyTriggerStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    } catch {
                        $copyTriggerStatus.Status = "Failed"
                        $copyTriggerStatus.Notes = (Get-ErrorMessage -Record $_)
                        $copyTriggerStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                        Stop-Function -Message "Issue creating trigger on destination" -Target $triggerName -ErrorRecord $_
                    }
                }
            }
        }
    }
}