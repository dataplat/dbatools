function Copy-DbaServerRole {
    <#
    .SYNOPSIS
        Migrates custom server roles and their permissions between SQL Server instances

    .DESCRIPTION
        Copies user-defined server roles from the source server to one or more destination servers. This is essential when migrating SQL Server instances that use custom server roles for granular permission management, or when standardizing security configurations across multiple environments.

        Only custom (user-defined) server roles are copied by default. Fixed server roles like sysadmin, serveradmin, etc. are built into SQL Server and cannot be created or dropped. Use -IncludeFixedRole to also synchronize memberships for fixed roles.

        Server role permissions and memberships are migrated along with the role definition. This includes server-level permissions granted to the role (like CONNECT ANY DATABASE, VIEW ANY DATABASE) and login memberships in the role.

        By default, existing server roles on the destination are skipped to prevent conflicts. Use -Force to drop and recreate existing roles, which will also reapply all permissions and memberships.

    .PARAMETER Source
        Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2012 or higher.

    .PARAMETER SourceSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2012 or higher.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER ServerRole
        Specifies which server roles to migrate from the source server. Only the specified roles will be copied to the destination.
        Use this when you need to migrate specific custom roles rather than all of them, such as when standardizing only certain security roles across environments.

    .PARAMETER ExcludeServerRole
        Specifies which server roles to skip during migration. All custom server roles except the excluded ones will be copied.
        Use this when you want to migrate most roles but exclude problematic ones, or when certain roles are environment-specific and shouldn't be copied.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Force
        Drops and recreates existing custom server roles on the destination server, reapplying all permissions and memberships from the source.
        Use this when you need to update server role permissions that have changed on the source, or when synchronizing role definitions across environments.

    .NOTES
        Tags: Migration, ServerRole, Security
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers, SQL Server 2012+

    .LINK
        https://dbatools.io/Copy-DbaServerRole

    .EXAMPLE
        PS C:\> Copy-DbaServerRole -Source sqlserver2014a -Destination sqlcluster

        Copies all custom server roles from sqlserver2014a to sqlcluster using Windows credentials. If roles with the same name exist on sqlcluster, they will be skipped.

    .EXAMPLE
        PS C:\> Copy-DbaServerRole -Source sqlserver2014a -SourceSqlCredential $scred -Destination sqlcluster -DestinationSqlCredential $dcred -ServerRole "CustomRole1" -Force

        Copies only the custom server role named "CustomRole1" from sqlserver2014a to sqlcluster using SQL credentials. If the role exists on sqlcluster, it will be dropped and recreated because -Force was used.

    .EXAMPLE
        PS C:\> Copy-DbaServerRole -Source sqlserver2014a -Destination sqlcluster -ExcludeServerRole "TestRole" -Force

        Copies all custom server roles found on sqlserver2014a except "TestRole" to sqlcluster. If roles with the same name exist on sqlcluster, they will be updated because -Force was used.

    .EXAMPLE
        PS C:\> Copy-DbaServerRole -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

        Shows what would happen if the command were executed using force.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [object[]]$ServerRole,
        [object[]]$ExcludeServerRole,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        try {
            $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 11
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }

        $sourceRoles = $sourceServer.Roles | Where-Object { $PSItem.IsFixedRole -eq $false -and $PSItem.Name -ne "public" }

        if ($Force) { $ConfirmPreference = "none" }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -MinimumVersion 11
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }

            $destRoles = $destServer.Roles

            foreach ($currentRole in $sourceRoles) {
                $roleName = $currentRole.Name

                $copyRoleStatus = [PSCustomObject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Type              = "Server Role"
                    Name              = $roleName
                    Status            = $null
                    Notes             = $null
                    DateTime          = [DbaDateTime](Get-Date)
                }

                if ($ServerRole -and ($roleName -notin $ServerRole)) {
                    continue
                }

                if ($ExcludeServerRole -and ($roleName -in $ExcludeServerRole)) {
                    continue
                }

                if ($destRoles.Name -contains $roleName) {
                    if ($force -eq $false) {
                        If ($Pscmdlet.ShouldProcess($destinstance, "Server role $roleName exists at destination. Use -Force to drop and migrate.")) {
                            $copyRoleStatus.Status = "Skipped"
                            $copyRoleStatus.Notes = "Already exists on destination"
                            $copyRoleStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Write-Message -Level Verbose -Message "Server role $roleName exists at destination. Use -Force to drop and migrate."
                        }
                        continue
                    } else {
                        If ($Pscmdlet.ShouldProcess($destinstance, "Dropping server role $roleName and recreating")) {
                            try {
                                Write-Message -Level Verbose -Message "Dropping server role $roleName"
                                $destServer.Roles[$roleName].Drop()
                                $destServer.Roles.Refresh()
                            } catch {
                                $copyRoleStatus.Status = "Failed"
                                $copyRoleStatus.Notes = "$PSItem"
                                $copyRoleStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                Write-Message -Level Verbose -Message "Issue dropping server role $roleName on $destinstance | $PSItem"
                                continue
                            }
                        }
                    }
                }

                if ($Pscmdlet.ShouldProcess($destinstance, "Creating server role $roleName")) {
                    try {
                        Write-Message -Level Verbose -Message "Copying server role $roleName"
                        $sql = $currentRole.Script() | Out-String
                        Write-Message -Level Debug -Message $sql
                        $destServer.Query($sql)
                        $destServer.Roles.Refresh()

                        $splatPermissions = @{
                            SqlInstance        = $sourceServer
                            IncludeServerLevel = $true
                        }
                        $sourcePermissions = Get-DbaPermission @splatPermissions | Where-Object Grantee -eq $roleName
                        foreach ($perm in $sourcePermissions) {
                            try {
                                $permSql = $perm.GrantStatement
                                if ($permSql) {
                                    Write-Message -Level Debug -Message "Granting permission: $permSql"
                                    $destServer.Query($permSql)
                                }
                            } catch {
                                Write-Message -Level Warning -Message "Could not grant permission for role $roleName on $destinstance | $PSItem"
                            }
                        }

                        $members = $currentRole.EnumMemberNames()
                        foreach ($member in $members) {
                            if ($destServer.Logins.Name -contains $member) {
                                try {
                                    Write-Message -Level Verbose -Message "Adding login $member to role $roleName"
                                    $destServer.Roles[$roleName].AddMember($member)
                                } catch {
                                    Write-Message -Level Warning -Message "Could not add member $member to role $roleName on $destinstance | $PSItem"
                                }
                            } else {
                                Write-Message -Level Verbose -Message "Login $member does not exist on destination, skipping membership"
                            }
                        }

                        $copyRoleStatus.Status = "Successful"
                        $copyRoleStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    } catch {
                        $copyRoleStatus.Status = "Failed"
                        $copyRoleStatus.Notes = "$PSItem"
                        $copyRoleStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Issue creating server role $roleName on $destinstance | $PSItem"
                        continue
                    }
                }
            }
        }
    }
}
