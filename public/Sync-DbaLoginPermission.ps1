function Sync-DbaLoginPermission {
    <#
    .SYNOPSIS
        Synchronizes login permissions and role memberships between SQL Server instances.

    .DESCRIPTION
        Syncs comprehensive login security settings from a source to destination SQL Server instance, ensuring logins have consistent permissions across environments. This function only modifies permissions for existing logins - it will not create or drop logins themselves.

        The sync process handles server roles (sysadmin, bulkadmin, etc.), server-level permissions (Connect SQL, View any database, etc.), SQL Agent job ownership, credential mappings, database user mappings, database roles (db_owner, db_datareader, etc.), and database-level permissions. This is particularly useful for maintaining consistent security configurations across development, staging, and production environments, or when rebuilding servers and needing to restore login permissions without recreating the logins.

        If a login exists on the source but not the destination, that login is skipped entirely. The function also protects against syncing permissions for system logins, host-based logins, and the currently connected login to prevent accidental lockouts.

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

    .PARAMETER Login
        The login(s) to process. Options for this list are auto-populated from the server. If unspecified, all logins will be processed.

    .PARAMETER ExcludeLogin
        The login(s) to exclude. Options for this list are auto-populated from the server.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration, Login
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Sync-DbaLoginPermission

    .EXAMPLE
        PS C:\> Sync-DbaLoginPermission -Source sqlserver2014a -Destination sqlcluster

        Syncs only SQL Server login permissions, roles, etc. Does not add or drop logins or users. To copy logins and their permissions, use Copy-SqlLogin.

    .EXAMPLE
        PS C:\> Sync-DbaLoginPermission -Source sqlserver2014a -Destination sqlcluster -Exclude realcajun -SourceSqlCredential $scred -DestinationSqlCredential $dcred

        Copies all login permissions except for realcajun using SQL Authentication to connect to each server. If a login already exists on the destination, the permissions will not be migrated.

    .EXAMPLE
        PS C:\> Sync-DbaLoginPermission -Source sqlserver2014a -Destination sqlcluster -Login realcajun, netnerds

        Copies permissions ONLY for logins netnerds and realcajun.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [string[]]$Login,
        [string[]]$ExcludeLogin,
        [switch]$EnableException
    )

    process {
        if (Test-FunctionInterrupt) { return }

        try {
            $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }

        $allLogins = Get-DbaLogin -SqlInstance $sourceServer -Login $Login -ExcludeLogin $ExcludeLogin
        if ($null -eq $allLogins) {
            Stop-Function -Message "No matching logins found for $($Login -join ', ') on $Source"
            return
        }

        # Get current login to not sync permissions for that login.
        $currentLogin = $sourceServer.ConnectionContext.TrueLogin

        foreach ($dest in $Destination) {
            try {
                $destServer = Connect-DbaInstance -SqlInstance $dest -SqlCredential $DestinationSqlCredential -MinimumVersion 8
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $dest -Continue
            }

            $stepCounter = 0
            foreach ($sourceLogin in $allLogins) {
                $loginName = $sourceLogin.Name
                if ($currentLogin -eq $loginName) {
                    Write-Message -Level Verbose -Message "Sync does not modify the permissions of the current login '$loginName'. Skipping."
                    continue
                }

                # Here we don't need the FullComputerName, but only the machine name to compare to the host part of the login name. So ComputerName should be fine.
                $serverName = $sourceServer.ComputerName
                $userBase = ($loginName.Split("\")[0]).ToLowerInvariant()
                if ($serverName -eq $userBase -or $loginName.StartsWith("NT ")) {
                    Write-Message -Level Verbose -Message "Sync does not modify the permissions of host or system login '$loginName'. Skipping."
                    continue
                }

                if ($null -eq ($destLogin = $destServer.Logins.Item($loginName))) {
                    Write-Message -Level Verbose -Message "Login '$loginName' not found on destination. Skipping."
                    continue
                }


                $copyLoginPermissionStatus = [PSCustomObject]@{
                    SourceServer      = $sourceserver.Name
                    DestinationServer = $destServer.Name
                    Name              = $loginName
                    Type              = "Login Permissions"
                    Status            = $null
                    Notes             = $null
                    DateTime          = [DbaDateTime](Get-Date)
                }
                Write-ProgressHelper -Activity "Executing Sync-DbaLoginPermission to sync login permissions from $($sourceServer.Name)" -StepNumber ($stepCounter++) -Message "Updating permissions for $loginName on $($destServer.Name)" -TotalSteps $allLogins.Count
                try {
                    Update-SqlPermission -SourceServer $sourceServer -SourceLogin $sourceLogin -DestServer $destServer -DestLogin $destLogin -EnableException
                    $copyLoginPermissionStatus.Status = "Successful"
                    if ($PSCmdlet.ShouldProcess("Console", "Outputting results for login $loginName permission sync")) {
                        $copyLoginPermissionStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    }
                } catch {
                    $copyLoginPermissionStatus.Status = "Failed"
                    $copyLoginPermissionStatus.Notes = (Get-ErrorMessage -Record $_)
                    $copyLoginPermissionStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    Stop-Function -Message "Issue syncing permissions for login" -Target $loginName -ErrorRecord $_ -Continue
                }
            }
        }
    }
}