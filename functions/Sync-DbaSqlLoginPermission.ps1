function Sync-DbaSqlLoginPermission {
    <#
        .SYNOPSIS
            Copies SQL login permission from one server to another.

        .DESCRIPTION
            Syncs only SQL Server login permissions, roles, etc. Does not add or drop logins. If a matching login does not exist on the destination, the login will be skipped. Credential removal is not currently supported for this operation.

        .PARAMETER Source
            Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

        .PARAMETER SourceSqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Destination
            Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2000 or higher.

        .PARAMETER DestinationSqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

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
            Requires: sysadmin access on SQL Servers
            Limitations: Does not support Application Roles yet

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Sync-DbaSqlLoginPermission

        .EXAMPLE
            Sync-DbaSqlLoginPermission -Source sqlserver2014a -Destination sqlcluster

            Syncs only SQL Server login permissions, roles, etc. Does not add or drop logins or users. To copy logins and their permissions, use Copy-SqlLogin.

        .EXAMPLE
            Sync-DbaSqlLoginPermission -Source sqlserver2014a -Destination sqlcluster -Exclude realcajun -SourceSqlCredential $scred -DestinationSqlCredential $dcred

            Copies all login permissions except for realcajun using SQL Authentication to connect to each server. If a login already exists on the destination, the permissions will not be migrated.

        .EXAMPLE
            Sync-DbaSqlLoginPermission -Source sqlserver2014a -Destination sqlcluster -Login realcajun, netnerds

            Copies permissions ONLY for logins netnerds and realcajun.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [DbaInstanceParameter]$Source,
        [PSCredential]
        $SourceSqlCredential,
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter]$Destination,
        [PSCredential]
        $DestinationSqlCredential,
        [object[]]$Login,
        [object[]]$ExcludeLogin,
        [Alias('Silent')]
        [switch]$EnableException
    )
    begin {
        function Sync-Only {
            [CmdletBinding()]
            param (
                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [object]$sourceServer,
                [object]$destServer,
                [array]$Logins,
                [array]$Exclude
            )

            try {
                $sa = ($destServer.Logins | Where-Object { $_.id -eq 1 }).Name
            }
            catch {
                $sa = "sa"
            }

            foreach ($sourceLogin in $sourceServer.Logins) {

                $username = $sourceLogin.Name
                $currentLogin = $sourceServer.ConnectionContext.TrueLogin

                if (!$Login -and $currentLogin -eq $username) {
                    Write-Message -Level Warning -Message "Sync does not modify the permissions of the current user. Skipping."
                    continue
                }

                if ($null -ne $Logins -and $Logins -notcontains $username) {
                    continue
                }

                if ($Exclude -contains $username -or $username.StartsWith("##") -or $username -eq $sa) {
                    continue
                }

                $serverName = Resolve-NetBiosName $sourceServer
                $userBase = ($username.Split("\")[0]).ToLower()
                if ($serverName -eq $userBase -or $username.StartsWith("NT ")) {
                    continue
                }
                if ($null -eq ($destLogin = $destServer.Logins.Item($username))) {
                    continue
                }

                Update-SqlPermissions -SourceServer $sourceServer -SourceLogin $sourceLogin -DestServer $destServer -DestLogin $destLogin
            }
        }

        if ($source -eq $destination) {
            Stop-Function -Message "Source and Destination SQL Servers are the same. Quitting."
            return
        }

        Write-Message -Level Verbose -Message "Attempting to connect to SQL Servers."
        $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 8
        $destServer = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential -MinimumVersion 8

        $source = $sourceServer.DomainInstanceName
        $destination = $destServer.DomainInstanceName
    }
    process {
        if (Test-FunctionInterrupt) { return }

        if (!$Login) {
            $logins = $sourceServer.Logins.Name
        }

        Sync-Only -SourceServer $sourceServer -DestServer $destServer -Logins $logins -Exclude $ExcludeLogin
    }
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Sync-SqlLoginPermissions
    }
}
