function Copy-DbaExtendedEvent {
    <#
        .SYNOPSIS
            Migrates SQL Extended Event Sessions except the two default sessions, AlwaysOn_health and system_health.

        .DESCRIPTION
            Migrates SQL Extended Event Sessions except the two default sessions, AlwaysOn_health and system_health.

            By default, all non-system Extended Events are migrated.

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
            Requires: sysadmin access on SQL Servers

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Copy-DbaExtendedEvent

        .EXAMPLE
            Copy-DbaExtendedEvent -Source sqlserver2014a -Destination sqlcluster

            Copies all Extended Event sessions from sqlserver2014a to sqlcluster using Windows credentials.

        .EXAMPLE
            Copy-DbaExtendedEvent -Source sqlserver2014a -Destination sqlcluster -SourceSqlCredential $cred

            Copies all Extended Event sessions from sqlserver2014a to sqlcluster using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster.

        .EXAMPLE
            Copy-DbaExtendedEvent -Source sqlserver2014a -Destination sqlcluster -WhatIf

            Shows what would happen if the command were executed.

        .EXAMPLE
            Copy-DbaExtendedEvent -Source sqlserver2014a -Destination sqlcluster -XeSession CheckQueries, MonitorUserDefinedException

            Copies only the Extended Events named CheckQueries and MonitorUserDefinedException from sqlserver2014a to sqlcluster.
    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
    param (
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter]$Source,
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter]$Destination,
        [PSCredential]
        $SourceSqlCredential,
        [PSCredential]
        $DestinationSqlCredential,
        [object[]]$XeSession,
        [object[]]$ExcludeXeSession,
        [switch]$Force,
        [switch][Alias('Silent')]$EnableException
    )
    begin {

        $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 10
        $destServer = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential -MinimumVersion 10

        $source = $sourceServer.DomainInstanceName
        $destination = $destServer.DomainInstanceName
    }
    process {

        $sourceSqlConn = $sourceServer.ConnectionContext.SqlConnectionObject
        $sourceSqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $sourceSqlConn
        $sourceStore = New-Object  Microsoft.SqlServer.Management.XEvent.XEStore $sourceSqlStoreConnection

        $destSqlConn = $destServer.ConnectionContext.SqlConnectionObject
        $destSqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $destSqlConn
        $destStore = New-Object  Microsoft.SqlServer.Management.XEvent.XEStore $destSqlStoreConnection

        $storeSessions = $sourceStore.Sessions | Where-Object { $_.Name -notin 'AlwaysOn_health', 'system_health' }
        if ($XeSession) {
            $storeSessions = $storeSessions | Where-Object Name -In $XeSession
        }
        if ($ExcludeXeSession) {
            $storeSessions = $storeSessions | Where-Object Name -NotIn $ExcludeXeSession
        }

        Write-Message -Level Verbose -Message "Migrating sessions."
        foreach ($session in $storeSessions) {
            $sessionName = $session.Name

            $copyXeSessionStatus = [pscustomobject]@{
                SourceServer      = $sourceServer.Name
                DestinationServer = $destServer.Name
                Name              = $sessionName
                Type              = "Extended Event"
                Status            = $null
                Notes             = $null
                DateTime          = [DbaDateTime](Get-Date)
            }

            if ($destStore.Sessions[$sessionName] -ne $null) {
                if ($force -eq $false) {
                    $copyXeSessionStatus.Status = "Skipped"
                    $copyXeSessionStatus.Notes = "Already exists"
                    $copyXeSessionStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                    Write-Message -Level Verbose -Message "Extended Event Session '$sessionName' was skipped because it already exists on $destination."
                    Write-Message -Level Verbose -Message "Use -Force to drop and recreate."
                    continue
                }
                else {
                    if ($Pscmdlet.ShouldProcess($destination, "Attempting to drop $sessionName")) {
                        Write-Message -Level Verbose -Message "Extended Event Session '$sessionName' exists on $destination."
                        Write-Message -Level Verbose -Message "Force specified. Dropping $sessionName."

                        try {
                            $destStore.Sessions[$sessionName].Drop()
                        }
                        catch {
                            $copyXeSessionStatus.Status = "Failed"
                            $copyXeSessionStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Stop-Function -Message "Unable to drop session. Moving on." -Target $sessionName -InnerErrorRecord $_ -Continue
                        }
                    }
                }
            }

            if ($Pscmdlet.ShouldProcess($destination, "Migrating session $sessionName")) {
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
                }
                catch {
                    $copyXeSessionStatus.Status = "Failed"
                    $copyXeSessionStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                    Stop-Function -Message "Unable to create session." -Target $sessionName -InnerErrorRecord $_
                }
            }
        }
    }
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Copy-SqlExtendedEvent
    }
}