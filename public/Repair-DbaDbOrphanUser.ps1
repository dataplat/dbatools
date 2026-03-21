function Repair-DbaDbOrphanUser {
    <#
    .SYNOPSIS
        Repairs orphaned database users by remapping them to matching server logins or optionally removing them.

    .DESCRIPTION
        Identifies and repairs orphaned database users - users that exist in a database but are no longer associated with a server login. This commonly occurs after database restores, migrations, or when logins are recreated.

        The function searches each database for users where the Login property is empty, then attempts to remap them to existing server logins with matching names. For a login to be eligible for remapping, it must be enabled, not a system object, not locked, and have the exact same name as the orphaned user.

        Uses modern ALTER USER syntax for SQL Server 2005+ or the legacy sp_change_users_login procedure for SQL Server 2000. Optionally removes orphaned users that have no matching server login when -RemoveNotExisting is specified.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to scan for orphaned users. Accepts wildcards for pattern matching and multiple database names.
        Use this when you only need to repair orphaned users in specific databases rather than scanning all databases on the instance.

    .PARAMETER ExcludeDatabase
        Specifies databases to skip when scanning for orphaned users. Useful for avoiding system databases or databases under maintenance.
        Commonly used to exclude tempdb, distribution databases, or databases where orphaned users should remain untouched.

    .PARAMETER Users
        Specifies specific database users to repair rather than processing all orphaned users found.
        Use this when you need to target specific problematic users or when working with large databases where selective repair is preferred.

    .PARAMETER Force
        Bypasses confirmation prompts and forces schema ownership changes to dbo when removing orphaned users.
        Required when orphaned users own database schemas that prevent their removal. Use with caution as it can affect database object ownership.

    .PARAMETER RemoveNotExisting
        Removes orphaned database users that have no corresponding server login instead of just reporting them.
        Use this after database migrations or when cleaning up databases where some users should no longer exist. Exercise caution as this permanently removes users.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        PSCustomObject

        Returns one object per orphaned user found, regardless of whether it was successfully repaired or not. The output indicates the repair status for each user encountered.

        Properties:
        - ComputerName: The name of the computer hosting the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance format)
        - DatabaseName: The name of the database where the orphaned user exists
        - User: The name of the orphaned database user
        - Status: The outcome of the repair attempt. Values are:
            - "Success": User was successfully remapped to their matching server login
            - "No matching login": No matching server login was found for the user (returned only when -RemoveNotExisting is not specified)

        When -RemoveNotExisting is specified, users without matching logins are passed to Remove-DbaDbOrphanUser instead of being returned in the output.

        No output is returned if no orphaned users are found in the specified database(s).

    .NOTES
        Tags: Orphan
        Author: Claudio Silva (@ClaudioESSilva) | Simone Bizzotto (@niphlod)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Repair-DbaDbOrphanUser

    .EXAMPLE
        PS C:\> Repair-DbaDbOrphanUser -SqlInstance sql2005

        Finds and repairs all orphan users of all databases present on server 'sql2005'

    .EXAMPLE
        PS C:\> Repair-DbaDbOrphanUser -SqlInstance sqlserver2014a -SqlCredential $cred

        Finds and repair all orphan users in all databases present on server 'sqlserver2014a'. SQL credentials are used to authenticate to the server.

    .EXAMPLE
        PS C:\> Repair-DbaDbOrphanUser -SqlInstance sqlserver2014a -Database db1, db2

        Finds and repairs all orphan users in both db1 and db2 databases.

    .EXAMPLE
        PS C:\> Repair-DbaDbOrphanUser -SqlInstance sqlserver2014a -Database db1 -Users OrphanUser

        Finds and repairs user 'OrphanUser' in 'db1' database.

    .EXAMPLE
        PS C:\> Repair-DbaDbOrphanUser -SqlInstance sqlserver2014a -Users OrphanUser

        Finds and repairs user 'OrphanUser' on all databases

    .EXAMPLE
        PS C:\> Repair-DbaDbOrphanUser -SqlInstance sqlserver2014a -RemoveNotExisting

        Finds all orphan users of all databases present on server 'sqlserver2014a'. Removes all users that do not have  matching Logins.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [parameter(ValueFromPipeline)]
        [object[]]$Users,
        [switch]$RemoveNotExisting,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $DatabaseCollection = $server.Databases | Where-Object IsAccessible

            if ($Database) {
                $DatabaseCollection = $DatabaseCollection | Where-Object Name -In $Database
            }
            if ($ExcludeDatabase) {
                $DatabaseCollection = $DatabaseCollection | Where-Object Name -NotIn $ExcludeDatabase
            }

            if ($DatabaseCollection.Count -gt 0) {
                foreach ($db in $DatabaseCollection) {
                    try {

                        Write-Message -Level Verbose -Message "Validating users on database '$db'."

                        $UsersToWork = (Get-DbaDbOrphanUser -SqlInstance $server -Database $db.Name).SmoUser
                        if ($Users.Count -gt 0) {
                            $UsersToWork = $UsersToWork | Where-Object { $Users -contains $_.Name }
                        }

                        if ($UsersToWork.Count -gt 0) {
                            Write-Message -Level Verbose -Message "Orphan users found"
                            $UsersToRemove = @()
                            foreach ($User in $UsersToWork) {
                                $ExistLogin = $server.logins | Where-Object {
                                    $_.Isdisabled -eq $False -and
                                    $_.IsSystemObject -eq $False -and
                                    $_.IsLocked -eq $False -and
                                    $_.Name -eq $User.Name
                                }

                                if ($ExistLogin) {
                                    if ($server.versionMajor -gt 8) {
                                        $query = "ALTER USER " + $User + " WITH LOGIN = " + $User
                                    } else {
                                        $query = "EXEC sp_change_users_login 'update_one', '$User'"
                                    }

                                    if ($Pscmdlet.ShouldProcess($db.Name, "Mapping user '$($User.Name)'")) {
                                        $server.Databases[$db.Name].ExecuteNonQuery($query) | Out-Null
                                        Write-Message -Level Verbose -Message "User '$($User.Name)' mapped with their login."

                                        [PSCustomObject]@{
                                            ComputerName = $server.ComputerName
                                            InstanceName = $server.ServiceName
                                            SqlInstance  = $server.DomainInstanceName
                                            DatabaseName = $db.Name
                                            User         = $User.Name
                                            Status       = "Success"
                                        }
                                    }
                                } else {
                                    if ($RemoveNotExisting) {
                                        #add user to collection
                                        $UsersToRemove += $User
                                    } else {
                                        Write-Message -Level Verbose -Message "Orphan user $($User.Name) does not have matching login."
                                        [PSCustomObject]@{
                                            ComputerName = $server.ComputerName
                                            InstanceName = $server.ServiceName
                                            SqlInstance  = $server.DomainInstanceName
                                            DatabaseName = $db.Name
                                            User         = $User.Name
                                            Status       = "No matching login"
                                        }
                                    }
                                }
                            }

                            #With the collection complete invoke remove.
                            if ($RemoveNotExisting) {
                                if ($Force) {
                                    if ($Pscmdlet.ShouldProcess($db.Name, "Remove-DbaDbOrphanUser")) {
                                        Write-Message -Level Verbose -Message "Calling 'Remove-DbaDbOrphanUser' with -Force."
                                        Remove-DbaDbOrphanUser -SqlInstance $server -Database $db.Name -User $UsersToRemove -Force
                                    }
                                } else {
                                    if ($Pscmdlet.ShouldProcess($db.Name, "Remove-DbaDbOrphanUser")) {
                                        Write-Message -Level Verbose -Message "Calling 'Remove-DbaDbOrphanUser'."
                                        Remove-DbaDbOrphanUser -SqlInstance $server -Database $db.Name -User $UsersToRemove
                                    }
                                }
                            }
                        } else {
                            Write-Message -Level Verbose -Message "No orphan users found on database '$db'."
                        }
                        #reset collection
                        $UsersToWork = $null
                    } catch {
                        Stop-Function -Message $_ -Continue
                    }
                }
            } else {
                Write-Message -Level Verbose -Message "There are no databases to analyse."
            }
        }
    }
}