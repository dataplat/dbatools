function Copy-DbaServerTrigger {
    <#
        .SYNOPSIS
            Copy-DbaServerTrigger migrates server triggers from one SQL Server to another.

        .DESCRIPTION
            By default, all triggers are copied. The -ServerTrigger parameter is auto-populated for command-line completion and can be used to copy only specific triggers.

            If the trigger already exists on the destination, it will be skipped unless -Force is used.

        .PARAMETER Source
            Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2000 or greater.

        .PARAMETER SourceSqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Destination
            Destination Sql Server. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

        .PARAMETER DestinationSqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

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
            Requires: sysadmin access on SQL Servers

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Copy-DbaServerTrigger

        .EXAMPLE
            Copy-DbaServerTrigger -Source sqlserver2014a -Destination sqlcluster

            Copies all server triggers from sqlserver2014a to sqlcluster, using Windows credentials. If triggers with the same name exist on sqlcluster, they will be skipped.

        .EXAMPLE
            Copy-DbaServerTrigger -Source sqlserver2014a -Destination sqlcluster -ServerTrigger tg_noDbDrop -SourceSqlCredential $cred -Force

            Copies a single trigger, the tg_noDbDrop trigger from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If a trigger with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

        .EXAMPLE
            Copy-DbaServerTrigger -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

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
        [object[]]$ServerTrigger,
        [object[]]$ExcludeServerTrigger,
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
            Stop-Function -Message "Server Triggers are only supported in SQL Server 2005 and above. Quitting."
            return
        }

        if ($destServer.VersionMajor -lt $sourceServer.VersionMajor) {
            Stop-Function -Message "Migration from version $($destServer.VersionMajor) to version $($sourceServer.VersionMajor) is not supported."
            return
        }

        $serverTriggers = $sourceServer.Triggers
        $destTriggers = $destServer.Triggers

    }
    process {
        if (Test-FunctionInterrupt) { return }

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
                    $copyTriggerStatus.Status = "Already exists"
                    $copyTriggerStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    continue
                }
                else {
                    if ($Pscmdlet.ShouldProcess($destination, "Dropping server trigger $triggerName and recreating")) {
                        try {
                            Write-Message -Level Verbose -Message "Dropping server trigger $triggerName"
                            $destServer.Triggers[$triggerName].Drop()
                        }
                        catch {
                            $copyTriggerStatus.Status = "Failed"
                            $copyTriggerStatus.Notes = $_.Exception
                            $copyTriggerStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Stop-Function -Message "Issue dropping trigger on destination" -Target $triggerName -ErrorRecord $_ -Continue
                        }
                    }
                }
            }

            if ($Pscmdlet.ShouldProcess($destination, "Creating server trigger $triggerName")) {
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
                }
                catch {
                    $copyTriggerStatus.Status = "Failed"
                    $copyTriggerStatus.Notes = $_.Exception
                    $copyTriggerStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                    Stop-Function -Message "Issue creating trigger on destination" -Target $triggerName -ErrorRecord $_
                }
            }
        }
    }
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Copy-SqlServerTrigger
    }
}