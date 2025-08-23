function Set-DbaDbOwner {
    <#
    .SYNOPSIS
        Changes database ownership to a specified login when current ownership doesn't match the target.

    .DESCRIPTION
        Changes database ownership to standardize who owns your databases across an instance. This is particularly useful for maintaining consistent ownership patterns after restoring databases from other environments, where databases may have orphaned owners or inconsistent ownership.

        By default, the function sets ownership to 'sa' (or the renamed sysadmin account), but you can specify any valid login. The function only processes user databases and includes safety checks to ensure the target login exists, isn't a Windows group, and isn't already mapped as a user within the database. You can target all databases on an instance or filter to specific databases.

        Best Practice reference: http://weblogs.sqlteam.com/dang/archive/2008/01/13/Database-Owner-Troubles.aspx

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to change ownership for. Accepts database names and supports wildcards for pattern matching.
        When omitted, all user databases on the instance will be processed. System databases are automatically excluded.

    .PARAMETER ExcludeDatabase
        Specifies databases to skip during ownership changes. Useful when processing all databases but need to exclude specific ones.
        Accepts database names and supports wildcards for pattern matching.

    .PARAMETER InputObject
        Accepts database objects from Get-DbaDatabase for pipeline operations. Use this when you need to filter databases with specific criteria before changing ownership.
        Allows for complex database selection logic beyond simple name matching.

    .PARAMETER TargetLogin
        Specifies the login to set as the new database owner. Defaults to 'sa' (or the renamed sysadmin account if sa was renamed).
        The login must exist on the server, cannot be a Windows group, and cannot already be mapped as a user within the target database. Common values include service accounts or standardized admin logins.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database, Owner, DbOwner
        Author: Michael Fal (@Mike_Fal), mikefal.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaDbOwner

    .EXAMPLE
        PS C:\> Set-DbaDbOwner -SqlInstance localhost

        Sets database owner to 'sa' on all databases where the owner does not match 'sa'.

    .EXAMPLE
        PS C:\> Set-DbaDbOwner -SqlInstance localhost -TargetLogin DOMAIN\account

        Sets the database owner to DOMAIN\account on all databases where the owner does not match DOMAIN\account.

    .EXAMPLE
        PS C:\> Set-DbaDbOwner -SqlInstance sqlserver -Database db1, db2

        Sets database owner to 'sa' on the db1 and db2 databases if their current owner does not match 'sa'.

    .EXAMPLE
        PS C:\> $db = Get-DbaDatabase -SqlInstance localhost -Database db1, db2
        PS C:\> $db | Set-DbaDbOwner -TargetLogin DOMAIN\account

        Sets database owner to 'sa' on the db1 and db2 databases if their current owner does not match 'sa'.

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [Alias("Login")]
        [string]$TargetLogin,
        [switch]$EnableException
    )

    process {
        if (-not $InputObject -and -not $SqlInstance) {
            Stop-Function -Message "You must pipe in a database or specify a SqlInstance"
            return
        }

        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        foreach ($db in $InputObject) {
            # Exclude system databases
            if ($db.IsSystemObject) {
                continue
            }
            if (!$db.IsAccessible) {
                Write-Message -Level Warning -Message "Database $db is not accessible. Skipping."
                continue
            }

            $server = $db.Parent
            $instance = $server.Name

            # dynamic sa name for orgs who have changed their sa name
            if (!$TargetLogin) {
                $TargetLogin = ($server.logins | Where-Object { $_.id -eq 1 }).Name
            }

            #Validate login
            if (($server.Logins.Name) -notcontains $TargetLogin) {
                Stop-Function -Message "$TargetLogin is not a valid login on $instance. Moving on." -Continue -EnableException $EnableException
            }

            #Owner cannot be a group
            $TargetLoginObject = $server.Logins | Where-Object { $PSItem.Name -eq $TargetLogin } | Select-Object -property  Name, LoginType
            if ($TargetLoginObject.LoginType -eq 'WindowsGroup') {
                Stop-Function -Message "$TargetLogin is a group, therefore can't be set as owner. Moving on." -Continue -EnableException $EnableException
            }

            $dbName = $db.name
            if ($PSCmdlet.ShouldProcess($instance, "Setting database owner for $dbName to $TargetLogin")) {
                try {
                    Write-Message -Level Verbose -Message "Setting database owner for $dbName to $TargetLogin on $instance."
                    # Set database owner to $TargetLogin (default 'sa')
                    # Ownership validations checks

                    if ($db.Status -notmatch 'Normal') {
                        Write-Message -Level Warning -Message "$dbName on $instance is in a  $($db.Status) state and can not be altered. It will be skipped."
                    }
                    #Database is updatable, not read-only
                    elseif ($db.IsUpdateable -eq $false) {
                        Write-Message -Level Warning -Message "$dbName on $instance is not in an updateable state and can not be altered. It will be skipped."
                    }
                    #Is the login mapped as a user? Logins already mapped in the database can not be the owner
                    elseif ($db.Users.name -contains $TargetLogin) {
                        Write-Message -Level Warning -Message "$dbName on $instance has $TargetLogin as a mapped user. Mapped users can not be database owners."
                    } else {
                        # Make sure the Owner property in the SMO is filled befor the change. See #8528 for details.
                        $null = $db.Owner
                        $db.SetOwner($TargetLogin)
                        # The used version of the SMO does not update the .Owner property, so we have to force this:
                        $db.Alter()
                        [PSCustomObject]@{
                            ComputerName = $server.ComputerName
                            InstanceName = $server.ServiceName
                            SqlInstance  = $server.DomainInstanceName
                            Database     = $dbName
                            Owner        = $TargetLogin
                        }
                    }
                } catch {
                    Stop-Function -Message "Failure updating owner." -ErrorRecord $_ -Target $instance -Continue
                }
            }
        }
    }
}