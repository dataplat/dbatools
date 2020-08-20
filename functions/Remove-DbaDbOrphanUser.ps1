function Remove-DbaDbOrphanUser {
    <#
    .SYNOPSIS
        Drop orphan users with no existing login to map

    .DESCRIPTION
        Allows the removal of orphan users from one or more databases

        Orphaned users in SQL Server occur when a database user is based on a login in the master database, but the login no longer exists in master.
        This can occur when the login is deleted, or when the database is moved to another server where the login does not exist.

        If user is the owner of the schema with the same name and if if the schema does not have any underlying objects the schema will be dropped.

        If user owns more than one schema, the owner of the schemas that does not have the same name as the user, will be changed to 'dbo'. If schemas have underlying objects, you must specify the -Force parameter so the user can be dropped.

        If a login of the same name exists (which could be re-mapped with Repair-DbaDbOrphanUser)  the drop will not be performed unless you specify the -Force parameter (only when calling from Repair-DbaDbOrphanUser.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the database(s) to process. Options for this list are auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        Specifies the database(s) to exclude from processing. Options for this list are auto-populated from the server

    .PARAMETER User
        Specifies the list of users to remove.

    .PARAMETER Force
        If this switch is enabled:
        If exists any schema which owner is the User, this will force the change of the owner to 'dbo'.
        If a login of the same name exists the drop will not be performed unless you specify this parameter.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Orphan, Database, Security, Login
        Author: Claudio Silva (@ClaudioESSilva) | Simone Bizzotto (@niphlod)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaDbOrphanUser

    .EXAMPLE
        PS C:\> Remove-DbaDbOrphanUser -SqlInstance sql2005

        Finds and drops all orphan users without matching Logins in all databases present on server 'sql2005'.

    .EXAMPLE
        PS C:\> Remove-DbaDbOrphanUser -SqlInstance sqlserver2014a -SqlCredential $cred

        Finds and drops all orphan users without matching Logins in all databases present on server 'sqlserver2014a'. SQL Server authentication will be used in connecting to the server.

    .EXAMPLE
        PS C:\> Remove-DbaDbOrphanUser -SqlInstance sqlserver2014a -Database db1, db2 -Force

        Finds and drops orphan users even if they have a matching Login on both db1 and db2 databases.

    .EXAMPLE
        PS C:\> Remove-DbaDbOrphanUser -SqlInstance sqlserver2014a -ExcludeDatabase db1, db2 -Force

        Finds and drops orphan users even if they have a matching Login from all databases except db1 and db2.

    .EXAMPLE
        PS C:\> Remove-DbaDbOrphanUser -SqlInstance sqlserver2014a -User OrphanUser

        Removes user OrphanUser from all databases only if there is no matching login.

    .EXAMPLE
        PS C:\> Remove-DbaDbOrphanUser -SqlInstance sqlserver2014a -User OrphanUser -Force

        Removes user OrphanUser from all databases even if they have a matching Login. Any schema that the user owns will change ownership to dbo.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [parameter(ValueFromPipeline)]
        [object[]]$User,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {
        foreach ($Instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $Instance -SqlCredential $SqlCredential
            } catch {
                Write-Message -Level Warning -Message "Can't connect to $Instance or access denied. Skipping."
                continue
            }

            $DatabaseCollection = $server.Databases | Where-Object IsAccessible

            if ($Database) {
                $DatabaseCollection = $DatabaseCollection | Where-Object Name -In $Database
            }
            if ($ExcludeDatabase) {
                $DatabaseCollection = $DatabaseCollection | Where-Object Name -NotIn $ExcludeDatabase
            }

            $CallStack = Get-PSCallStack | Select-Object -Property *
            if ($CallStack.Count -eq 1) {
                $StackSource = $CallStack[0].Command
            } else {
                #-2 because index base is 0 and we want the one before the last (the last is the actual command)
                $StackSource = $CallStack[($CallStack.Count - 2)].Command
            }

            if ($DatabaseCollection) {
                foreach ($db in $DatabaseCollection) {
                    try {
                        #if SQL 2012 or higher only validate databases with ContainmentType = NONE
                        if ($server.versionMajor -gt 10) {
                            if ($db.ContainmentType -ne [Microsoft.SqlServer.Management.Smo.ContainmentType]::None) {
                                Write-Message -Level Warning -Message "Database '$db' is a contained database. Contained databases can't have orphaned users. Skipping validation."
                                Continue
                            }
                        }

                        if ($StackSource -eq "Repair-DbaDbOrphanUser") {
                            Write-Message -Level Verbose -Message "Call origin: Repair-DbaDbOrphanUser."
                            #Will use collection from parameter ($User)
                        } else {
                            Write-Message -Level Verbose -Message "Validating users on database $db."

                            $users = @()
                            if ($User.Count -eq 0) {
                                #the third validation will remove from list sql users without login  or mapped to certificate. The rule here is Sid with length higher than 16
                                $users += $db.Users | Where-Object { $_.Login -eq "" -and ($_.ID -gt 4) -and (($_.Sid.Length -gt 16 -and $_.LoginType -in @([Microsoft.SqlServer.Management.Smo.LoginType]::SqlLogin, [Microsoft.SqlServer.Management.Smo.LoginType]::Certificate)) -eq $false) }
                                $users += $db.Users | Where-Object { ($_.Name -notin $server.Logins.Name) -and ($_.ID -gt 4) -and ($_.Sid.Length -gt 16 -and $_.LoginType -in @([Microsoft.SqlServer.Management.Smo.LoginType]::WindowsUser, [Microsoft.SqlServer.Management.Smo.LoginType]::WindowsGroup)) }
                            } else {
                                Write-Message -Level Verbose -Message "Validating users on database $db."
                                #the fourth validation will remove from list sql users without login or mapped to certificate. The rule here is Sid with length higher than 16
                                $users += $db.Users | Where-Object { $_.Login -eq "" -and ($_.ID -gt 4) -and ($User -contains $_.Name) -and (($_.Sid.Length -gt 16 -and $_.LoginType -in @([Microsoft.SqlServer.Management.Smo.LoginType]::SqlLogin, [Microsoft.SqlServer.Management.Smo.LoginType]::Certificate)) -eq $false) }
                                $users += $db.Users | Where-Object { ($_.Name -notin $server.Logins.Name) -and ($_.ID -gt 4) -and ($User -contains $_.Name) -and ($_.Sid.Length -gt 16 -and $_.LoginType -in @([Microsoft.SqlServer.Management.Smo.LoginType]::WindowsUser, [Microsoft.SqlServer.Management.Smo.LoginType]::WindowsGroup)) }
                            }
                        }

                        if ($users.Count -gt 0) {
                            Write-Message -Level Verbose -Message "Orphan users found."
                            foreach ($dbuser in $users) {
                                $SkipUser = $false

                                $ExistLogin = $null

                                if ($StackSource -ne "Repair-DbaDbOrphanUser") {
                                    #Need to validate Existing Login because the call does not came from Repair-DbaDbOrphanUser
                                    $ExistLogin = $server.logins | Where-Object {
                                        $_.Isdisabled -eq $False -and
                                        $_.IsSystemObject -eq $False -and
                                        $_.IsLocked -eq $False -and
                                        $_.Name -eq $dbuser.Name
                                    }
                                }

                                #Schemas only appears on SQL Server 2005 (v9.0)
                                if ($server.versionMajor -gt 8) {

                                    #reset variables
                                    $AlterSchemaOwner = ""
                                    $DropSchema = ""

                                    #Validate if user owns any schema
                                    $Schemas = @()
                                    $Schemas = $db.Schemas | Where-Object Owner -eq $dbuser.Name

                                    if (@($Schemas).Count -gt 0) {
                                        Write-Message -Level Verbose -Message "User $dbuser owns one or more schemas."

                                        foreach ($sch in $Schemas) {
                                            <#
                                                On sql server 2008 or lower the EnumObjects method does not accept empty parameter.
                                                0x1FFFFFFF is the way we can say we want everything known by those versions

                                                When it is a higher version we can use empty to get all
                                            #>
                                            if ($server.versionMajor -lt 11) {
                                                $NumberObjects = ($db.EnumObjects(0x1FFFFFFF) | Where-Object { $_.Schema -eq $sch.Name } | Measure-Object).Count
                                            } else {
                                                $NumberObjects = ($db.EnumObjects() | Where-Object { $_.Schema -eq $sch.Name } | Measure-Object).Count
                                            }

                                            if ($NumberObjects -gt 0) {
                                                if ($Force) {
                                                    Write-Message -Level Verbose -Message "Parameter -Force was used! The schema '$($sch.Name)' have $NumberObjects underlying objects. We will change schema owner to 'dbo' and drop the user."

                                                    if ($Pscmdlet.ShouldProcess($db.Name, "Changing schema '$($sch.Name)' owner to 'dbo'. -Force used.")) {
                                                        $AlterSchemaOwner += "ALTER AUTHORIZATION ON SCHEMA::[$($sch.Name)] TO [dbo]`r`n"

                                                        [pscustomobject]@{
                                                            ComputerName      = $server.ComputerName
                                                            InstanceName      = $server.ServiceName
                                                            SqlInstance       = $server.DomainInstanceName
                                                            DatabaseName      = $db.Name
                                                            SchemaName        = $sch.Name
                                                            Action            = "ALTER OWNER"
                                                            SchemaOwnerBefore = $sch.Owner
                                                            SchemaOwnerAfter  = "dbo"
                                                        }
                                                    }
                                                } else {
                                                    Write-Message -Level Warning -Message "Schema '$($sch.Name)' owned by user $($dbuser.Name) have $NumberObjects underlying objects. If you want to change the schemas' owner to 'dbo' and drop the user anyway, use -Force parameter. Skipping user '$dbuser'."
                                                    $SkipUser = $true
                                                    break
                                                }
                                            } else {
                                                if ($sch.Name -eq $dbuser.Name) {
                                                    Write-Message -Level Verbose -Message "The schema '$($sch.Name)' have the same name as user $dbuser. Schema will be dropped."

                                                    if ($Pscmdlet.ShouldProcess($db.Name, "Dropping schema '$($sch.Name)'.")) {
                                                        $DropSchema += "DROP SCHEMA [$($sch.Name)]"

                                                        [pscustomobject]@{
                                                            ComputerName      = $server.ComputerName
                                                            InstanceName      = $server.ServiceName
                                                            SqlInstance       = $server.DomainInstanceName
                                                            DatabaseName      = $db.Name
                                                            SchemaName        = $sch.Name
                                                            Action            = "DROP"
                                                            SchemaOwnerBefore = $sch.Owner
                                                            SchemaOwnerAfter  = "N/A"
                                                        }
                                                    }
                                                } else {
                                                    Write-Message -Level Warning -Message "Schema '$($sch.Name)' does not have any underlying object. Ownership will be changed to 'dbo' so the user can be dropped. Remember to re-check permissions on this schema."

                                                    if ($Pscmdlet.ShouldProcess($db.Name, "Changing schema '$($sch.Name)' owner to 'dbo'.")) {
                                                        $AlterSchemaOwner += "ALTER AUTHORIZATION ON SCHEMA::[$($sch.Name)] TO [dbo]`r`n"

                                                        [pscustomobject]@{
                                                            ComputerName      = $server.ComputerName
                                                            InstanceName      = $server.ServiceName
                                                            SqlInstance       = $server.DomainInstanceName
                                                            DatabaseName      = $db.Name
                                                            SchemaName        = $sch.Name
                                                            Action            = "ALTER OWNER"
                                                            SchemaOwnerBefore = $sch.Owner
                                                            SchemaOwnerAfter  = "dbo"
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                    } else {
                                        Write-Message -Level Verbose -Message "User $dbuser does not own any schema. Will be dropped."
                                    }

                                    $query = "$AlterSchemaOwner `r`n$DropSchema `r`nDROP USER " + $dbuser

                                    Write-Message -Level Debug -Message $query
                                } else {
                                    $query = "EXEC master.dbo.sp_droplogin @loginame = N'$($dbuser.name)'"
                                }

                                if ($ExistLogin) {
                                    if (-not $SkipUser) {
                                        if ($Force) {
                                            if ($Pscmdlet.ShouldProcess($db.Name, "Dropping user $dbuser using -Force")) {
                                                $server.Databases[$db.Name].ExecuteNonQuery($query) | Out-Null
                                                Write-Message -Level Verbose -Message "User $dbuser was dropped from $($db.Name). -Force parameter was used."
                                            }
                                        } else {
                                            Write-Message -Level Warning -Message "Orphan user $($dbuser.Name) has a matching login. The user will not be dropped. If you want to drop anyway, use -Force parameter."
                                            Continue
                                        }
                                    }
                                } else {
                                    if (-not $SkipUser) {
                                        if ($Pscmdlet.ShouldProcess($db.Name, "Dropping user $dbuser")) {
                                            $server.Databases[$db.Name].ExecuteNonQuery($query) | Out-Null
                                            Write-Message -Level Verbose -Message "User $dbuser was dropped from $($db.Name)."
                                        }
                                    }
                                }
                            }
                        } else {
                            Write-Message -Level Verbose -Message "No orphan users found on database $db."
                        }
                        #reset collection
                        $users = $null
                    } catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Target $db -Continue
                    }
                }
            } else {
                Write-Message -Level Verbose -Message "There are no databases to analyse."
            }
        }
    }
}