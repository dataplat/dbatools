function Copy-DbaXESession {
    <#
    .SYNOPSIS
        Copies Extended Event sessions from one SQL Server instance to another, excluding system sessions.

    .DESCRIPTION
        Copies custom Extended Event sessions between SQL Server instances while preserving their configuration and running state. This function scripts out the session definitions from the source server and recreates them on the destination, making it essential for server migrations, standardizing monitoring across environments, or setting up disaster recovery instances.

        System sessions (AlwaysOn_health and system_health) are automatically excluded since they're managed by SQL Server itself. If a session was running on the source, it will be started on the destination after creation. Existing sessions with the same name on the destination will be skipped unless you use the Force parameter to overwrite them.

        Perfect for migrating your custom monitoring, auditing, and troubleshooting Extended Event sessions when moving databases between servers or ensuring consistent monitoring across your SQL Server estate.

    .PARAMETER Source
        The source SQL Server instance containing the Extended Event sessions to copy. Requires sysadmin privileges and SQL Server 2012 or higher.
        This is typically your production server or template instance where you've configured custom monitoring and auditing sessions.

    .PARAMETER SourceSqlCredential
        SQL Server authentication credentials for connecting to the source instance. Required when Windows authentication is disabled or unavailable.
        Use Get-Credential to securely prompt for credentials or pass an existing PSCredential object for automated scripts.

    .PARAMETER Destination
        One or more destination SQL Server instances where Extended Event sessions will be recreated. Accepts arrays for bulk deployment to multiple servers.
        Common scenarios include disaster recovery sites, development environments, or new production servers that need the same monitoring configuration.

    .PARAMETER DestinationSqlCredential
        SQL Server authentication credentials for connecting to all destination instances. Used when destination servers require different authentication than the source.
        Single credential object applies to all destinations - use separate commands if different destinations need different credentials.

    .PARAMETER XeSession
        Specific Extended Event session names to copy instead of all custom sessions. Accepts arrays of session names for selective migration.
        Use this when you only need specific monitoring sessions, such as copying just audit-related sessions to a compliance server or performance sessions to development.

    .PARAMETER ExcludeXeSession
        Extended Event session names to exclude from the copy operation. Use this to skip sessions inappropriate for the destination environment.
        Common use cases include excluding production-specific auditing sessions when copying to development or excluding resource-intensive sessions on smaller test servers.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Force
        Drops and recreates existing Extended Event sessions with matching names on the destination servers. Without this parameter, existing sessions are skipped.
        Use this when you need to update session configurations or when consolidating monitoring setups from multiple sources requires overwriting existing sessions.

    .OUTPUTS
        PSCustomObject (with TypeName: MigrationObject)

        Returns one object per Extended Event session processed, documenting the migration status for each session copy attempt.

        Default display properties (via Select-DefaultView with TypeName MigrationObject):
        - DateTime: Timestamp (DbaDateTime) when the migration operation occurred
        - SourceServer: Name of the source SQL Server instance from which the session was copied
        - DestinationServer: Name of the destination SQL Server instance where the session was copied to
        - Name: Name of the Extended Event session being migrated
        - Type: Always "Extended Event" indicating the object type being migrated
        - Status: Migration result (Successful, Skipped, or Failed)
        - Notes: Additional information; null for successful migrations, error message for failed operations or "Already exists on destination" for skipped sessions
    .NOTES
        Tags: Migration, ExtendedEvent, XEvent
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

    .LINK
        https://dbatools.io/Copy-DbaXESession

    .EXAMPLE
        PS C:\> Copy-DbaXESession -Source sqlserver2014a -Destination sqlcluster

        Copies all Extended Event sessions from sqlserver2014a to sqlcluster using Windows credentials.

    .EXAMPLE
        PS C:\> Copy-DbaXESession -Source sqlserver2014a -Destination sqlcluster -SourceSqlCredential $cred

        Copies all Extended Event sessions from sqlserver2014a to sqlcluster using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster.

    .EXAMPLE
        PS C:\> Copy-DbaXESession -Source sqlserver2014a -Destination sqlcluster -WhatIf

        Shows what would happen if the command were executed.

    .EXAMPLE
        PS C:\> Copy-DbaXESession -Source sqlserver2014a -Destination sqlcluster -XeSession CheckQueries, MonitorUserDefinedException

        Copies only the Extended Events named CheckQueries and MonitorUserDefinedException from sqlserver2014a to sqlcluster.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]
        $SourceSqlCredential,
        [PSCredential]
        $DestinationSqlCredential,
        [object[]]$XeSession,
        [object[]]$ExcludeXeSession,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        try {
            $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 11

            $sourceSqlConn = $sourceServer.ConnectionContext.SqlConnectionObject
            $sourceSqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $sourceSqlConn
            $sourceStore = New-Object  Microsoft.SqlServer.Management.XEvent.XEStore $sourceSqlStoreConnection
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }

        $storeSessions = $sourceStore.Sessions | Where-Object { $_.Name -notin 'AlwaysOn_health', 'system_health' }
        if ($XeSession) {
            $storeSessions = $storeSessions | Where-Object Name -In $XeSession
        }
        if ($ExcludeXeSession) {
            $storeSessions = $storeSessions | Where-Object Name -NotIn $ExcludeXeSession
        }

        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -MinimumVersion 11
                $destSqlConn = $destServer.ConnectionContext.SqlConnectionObject
                $destSqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $destSqlConn
                $destStore = New-Object  Microsoft.SqlServer.Management.XEvent.XEStore $destSqlStoreConnection
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }

            Write-Message -Level Verbose -Message "Migrating sessions."
            foreach ($session in $storeSessions) {
                $sessionName = $session.Name

                $copyXeSessionStatus = [PSCustomObject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $sessionName
                    Type              = "Extended Event"
                    Status            = $null
                    Notes             = $null
                    DateTime          = [DbaDateTime](Get-Date)
                }

                if ($null -ne $destStore.Sessions[$sessionName]) {
                    if ($force -eq $false) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Extended Event Session '$sessionName' was skipped because it already exists on $destinstance.")) {
                            $copyXeSessionStatus.Status = "Skipped"
                            $copyXeSessionStatus.Notes = "Already exists on destination"
                            $copyXeSessionStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Write-Message -Level Verbose -Message "Extended Event Session '$sessionName' was skipped because it already exists on $destinstance."
                            Write-Message -Level Verbose -Message "Use -Force to drop and recreate."
                        }
                        continue
                    } else {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Attempting to drop $sessionName")) {
                            Write-Message -Level Verbose -Message "Extended Event Session '$sessionName' exists on $destinstance."
                            Write-Message -Level Verbose -Message "Force specified. Dropping $sessionName."

                            try {
                                $destStore.Sessions[$sessionName].Drop()
                            } catch {
                                $copyXeSessionStatus.Status = "Failed"
                                $copyXeSessionStatus.Notes = (Get-ErrorMessage -Record $_)
                                $copyXeSessionStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                Write-Message -Level Verbose -Message "Issue dropping Extended Event session $sessionName on $destinstance | $PSItem"
                                continue
                            }
                        }
                    }
                }

                if ($Pscmdlet.ShouldProcess($destinstance, "Migrating session $sessionName")) {
                    try {
                        $sql = $session.ScriptCreate().GetScript() | Out-String

                        Write-Message -Level Debug -Message $sql
                        Write-Message -Level Verbose -Message "Migrating session $sessionName."
                        $null = $destServer.Query($sql)

                        if ($session.IsRunning -eq $true) {
                            $destStore.Sessions.Refresh()
                            $destStore.Sessions[$sessionName].Start()
                        }

                        $copyXeSessionStatus.Status = "Successful"
                        $copyXeSessionStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    } catch {
                        $copyXeSessionStatus.Status = "Failed"
                        $copyXeSessionStatus.Notes = (Get-ErrorMessage -Record $_)
                        $copyXeSessionStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Issue creating Extended Event session $sessionName on $destinstance | $PSItem"
                        continue
                    }
                }
            }
        }
    }
}