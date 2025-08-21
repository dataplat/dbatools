function Copy-DbaXESession {
    <#
    .SYNOPSIS
        Copies Extended Event sessions from one SQL Server instance to another, excluding system sessions.

    .DESCRIPTION
        Copies custom Extended Event sessions between SQL Server instances while preserving their configuration and running state. This function scripts out the session definitions from the source server and recreates them on the destination, making it essential for server migrations, standardizing monitoring across environments, or setting up disaster recovery instances.

        System sessions (AlwaysOn_health and system_health) are automatically excluded since they're managed by SQL Server itself. If a session was running on the source, it will be started on the destination after creation. Existing sessions with the same name on the destination will be skipped unless you use the Force parameter to overwrite them.

        Perfect for migrating your custom monitoring, auditing, and troubleshooting Extended Event sessions when moving databases between servers or ensuring consistent monitoring across your SQL Server estate.

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

    .PARAMETER XeSession
        The Extended Event Session(s) to process. This list is auto-populated from the server. If unspecified, all Extended Event Sessions will be processed.

    .PARAMETER ExcludeXeSession
        The Extended Event Session(s) to exclude. This list is auto-populated from the server.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Force
        If this switch is enabled, existing Extended Events sessions on Destination with matching names from Source will be dropped.

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