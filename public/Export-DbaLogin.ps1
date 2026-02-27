function Export-DbaLogin {
    <#
    .SYNOPSIS
        Generates T-SQL scripts to recreate SQL Server logins with their complete security context for migration and disaster recovery.

    .DESCRIPTION
        Creates executable T-SQL scripts that recreate SQL Server and Windows logins along with their complete security configuration. The export includes login properties (SID, hashed passwords, default database), server-level permissions and role memberships, database user mappings and roles, plus SQL Agent job ownership assignments. This addresses the common challenge where restoring databases doesn't restore the associated logins, leaving applications unable to connect. DBAs use this for server migrations, disaster recovery scenarios, and maintaining consistent security across environments.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. SQL Server 2000 and above supported.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER InputObject
        Accepts piped objects from Get-DbaLogin, Get-DbaDatabase, or Connect-DbaInstance commands.
        Use this when you want to export logins from specific objects rather than specifying instances directly.

    .PARAMETER Login
        Specifies which SQL Server logins to export by name. Accepts wildcards and arrays.
        When specified, only these logins are processed instead of all server logins. Use this to target specific accounts for migration or backup.

    .PARAMETER ExcludeLogin
        Specifies login names to skip during export. Accepts wildcards and arrays.
        Use this to exclude system accounts, service accounts, or other logins that shouldn't be migrated to the target environment.

    .PARAMETER Database
        Limits export to logins that have user mappings in the specified databases. Accepts database names or database objects.
        When specified, only logins with permissions or user accounts in these databases are exported, reducing script size for targeted migrations.

    .PARAMETER ExcludeJobs
        Excludes SQL Agent job ownership assignments from the export script.
        Use this when migrating logins to servers where the associated jobs don't exist or will be owned by different accounts.

    .PARAMETER ExcludeDatabase
        Excludes database user mappings and permissions from the export script.
        Use this when you only need server-level login definitions without their database-specific permissions and role memberships.

    .PARAMETER ExcludePassword
        Excludes hashed password values from SQL login export, replacing them with placeholder text.
        Use this for security compliance when sharing scripts or when passwords will be reset after migration.

    .PARAMETER DefaultDatabase
        Overrides the default database for all exported logins with the specified database name.
        Use this when migrating to servers where the original default databases don't exist, preventing login creation failures.

    .PARAMETER Path
        Specifies the directory where export files will be saved. Defaults to the Path.DbatoolsExport configuration setting.
        Files are automatically named based on instance and timestamp unless FilePath is specified.

    .PARAMETER FilePath
        Specifies the complete file path for the export script. Cannot be used when exporting from multiple instances.
        Use this when you need precise control over the output file location and name.

    .PARAMETER Passthru
        Returns the generated T-SQL script to the PowerShell pipeline instead of saving to file.
        Use this to capture the script in a variable, pipe to other commands, or display directly in the console.

    .PARAMETER BatchSeparator
        Sets the T-SQL batch separator used between statements. Defaults to 'GO' from the Formatting.BatchSeparator configuration.
        Specify an empty string to remove batch separators when the target system doesn't support them.

    .PARAMETER NoClobber
        Prevents overwriting existing files at the specified Path location.
        Use this as a safety measure when you don't want to accidentally replace existing login export scripts.

    .PARAMETER Append
        Adds the generated script to an existing file instead of overwriting it.
        Use this to combine login exports from multiple instances into a single deployment script.

    .PARAMETER DestinationVersion
        Generates T-SQL syntax compatible with the specified SQL Server version. Defaults to the source instance version.
        Use this when migrating to older SQL Server versions that require different syntax for role assignments or other features.

    .PARAMETER NoPrefix
        Excludes the standard dbatools header comment from the generated script.
        Use this when you need clean T-SQL output without metadata comments for automated deployment systems.

    .PARAMETER Encoding
        Sets the character encoding for the output file. Defaults to UTF8.
        Choose the appropriate encoding based on your deployment environment requirements and any special characters in login names.

    .PARAMETER ObjectLevel
        Includes detailed object-level permissions for each database user associated with the exported logins.
        Use this for complete permission migration when you need granular security settings preserved in the target environment.

    .PARAMETER IncludeRolePermissions
        Includes permissions granted to database roles that the login's database users are members of.
        By default, Export-DbaLogin scripts role membership (ALTER ROLE ... ADD MEMBER) but not the permissions granted to those roles.
        Use this switch to also export GRANT/DENY statements for each non-fixed role, ensuring the roles have the correct permissions on the target server.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .NOTES
        Tags: Export, Login
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Export-DbaLogin

    .OUTPUTS
        System.String (when -Passthru is specified or neither -Path nor -FilePath is specified)

        Returns the generated T-SQL script as a string. When -Passthru is specified, the script is sent to the pipeline. If -Path or -FilePath are not specified, the script is returned directly without being saved to a file.

        System.IO.FileInfo (when -Path or -FilePath is specified)

        Returns file information objects for the created export files. Each file contains the generated T-SQL script for login recreation including:
        - CREATE LOGIN statements with password hashes (or placeholder text if -ExcludePassword is used)
        - DEFAULT_DATABASE setting (or the -DefaultDatabase override if specified)
        - Login enabled/disabled status
        - DENY CONNECT SQL restrictions if applicable
        - Server role memberships
        - SQL Agent job ownership assignments (unless -ExcludeJobs is specified)
        - Server-level permissions and securables (for SQL Server 2005+)
        - Credential associations
        - Database user mappings and database roles (unless -ExcludeDatabase is specified)
        - Object-level permissions (if -ObjectLevel is specified)

        The script is formatted with the specified -BatchSeparator (default 'GO') between statements and includes a dbatools header comment unless -NoPrefix is specified.

    .EXAMPLE
        PS C:\> Export-DbaLogin -SqlInstance sql2005 -Path C:\temp\sql2005-logins.sql

        Exports the logins for SQL Server "sql2005" and writes them to the file "C:\temp\sql2005-logins.sql"

    .EXAMPLE
        PS C:\> Export-DbaLogin -SqlInstance sqlserver2014a -ExcludeLogin realcajun -SqlCredential $scred -Path C:\temp\logins.sql -Append

        Authenticates to sqlserver2014a using SQL Authentication. Exports all logins except for realcajun to C:\temp\logins.sql, and appends to the file if it exists. If not, the file will be created.

    .EXAMPLE
        PS C:\> Export-DbaLogin -SqlInstance sqlserver2014a -Login realcajun, netnerds -Path C:\temp\logins.sql

        Exports ONLY logins netnerds and realcajun FROM sqlserver2014a to the file  C:\temp\logins.sql

    .EXAMPLE
        PS C:\> Export-DbaLogin -SqlInstance sqlserver2014a -Login realcajun, netnerds -Database HR, Accounting

        Exports ONLY logins netnerds and realcajun FROM sqlserver2014a with the permissions on databases HR and Accounting

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sqlserver2014a -Database HR, Accounting | Export-DbaLogin

        Exports ONLY logins FROM sqlserver2014a with permissions on databases HR and Accounting

    .EXAMPLE
        PS C:\> Set-DbatoolsConfig -FullName formatting.batchseparator -Value $null
        PS C:\> Export-DbaLogin -SqlInstance sqlserver2008 -Login realcajun, netnerds -Path C:\temp\login.sql

        Exports ONLY logins netnerds and realcajun FROM sqlserver2008 server, to the C:\temp\login.sql file without the 'GO' batch separator.

    .EXAMPLE
        PS C:\> Export-DbaLogin -SqlInstance sqlserver2008 -Login realcajun -Path C:\temp\users.sql -DestinationVersion SQLServer2016

        Exports login realcajun from sqlserver2008 to the file C:\temp\users.sql with syntax to run on SQL Server 2016

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sqlserver2008 -Login realcajun | Export-DbaLogin

        Exports login realcajun from sqlserver2008

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance sqlserver2008, sqlserver2012  | Where-Object { $_.IsDisabled -eq $false } | Export-DbaLogin

        Exports all enabled logins from sqlserver2008 and sqlserver2008

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter()]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [object[]]$Login,
        [object[]]$ExcludeLogin,
        [object[]]$Database,
        [switch]$ExcludeJobs,
        [Alias("ExcludeDatabases")]
        [switch]$ExcludeDatabase,
        [switch]$ExcludePassword,
        [string]$DefaultDatabase,
        [string]$Path = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport'),
        [Alias("OutFile", "FileName")]
        [string]$FilePath,
        [ValidateSet('ASCII', 'BigEndianUnicode', 'Byte', 'String', 'Unicode', 'UTF7', 'UTF8', 'Unknown')]
        [string]$Encoding = 'UTF8',
        [Alias("NoOverwrite")]
        [switch]$NoClobber,
        [switch]$Append,
        [string]$BatchSeparator = (Get-DbatoolsConfigValue -FullName 'Formatting.BatchSeparator'),
        [ValidateSet('SQLServer2000', 'SQLServer2005', 'SQLServer2008/2008R2', 'SQLServer2012', 'SQLServer2014', 'SQLServer2016', 'SQLServer2017', 'SQLServer2019', 'SQLServer2022')]
        [string]$DestinationVersion,
        [switch]$NoPrefix,
        [switch]$Passthru,
        [switch]$ObjectLevel,
        [switch]$IncludeRolePermissions,
        [switch]$EnableException
    )

    begin {
        $null = Test-ExportDirectory -Path $Path
        $outsql = @()
        $instanceArray = @()
        $logonCollection = New-Object System.Collections.ArrayList
        if ($IsLinux -or $IsMacOs) {
            $executingUser = $env:USER
        } else {
            $executingUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        }
        $commandName = $MyInvocation.MyCommand.Name

        $eol = [System.Environment]::NewLine
    }
    process {
        if (Test-FunctionInterrupt) { return }

        if (-not $InputObject -and -not $SqlInstance) {
            Stop-Function -Message "You must pipe in a login, database, or server or specify a SqlInstance"
            return
        }

        if ($SqlInstance) {
            $InputObject = $SqlInstance
        }

        foreach ($input in $InputObject) {
            $inputType = $input.GetType().FullName
            switch ($inputType) {
                'Dataplat.Dbatools.Parameter.DbaInstanceParameter' {
                    Write-Message -Level Verbose -Message "Processing Server through InputObject"
                    try {
                        $server = Connect-DbaInstance -SqlInstance $input -SqlCredential $SqlCredential
                    } catch {
                        Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $input -Continue
                    }
                }
                'Microsoft.SqlServer.Management.Smo.Server' {
                    Write-Message -Level Verbose -Message "Processing Server through InputObject"
                    $server = Connect-DbaInstance -SqlInstance $input -SqlCredential $SqlCredential
                }
                'Microsoft.SqlServer.Management.Smo.Database' {
                    Write-Message -Level Verbose -Message "Processing Database through InputObject"
                    $server = $input.Parent
                    $Database = $input
                }
                'Microsoft.SqlServer.Management.Smo.Login' {
                    Write-Message -Level Verbose -Message "Processing Login through InputObject"
                    $server = $input.Parent
                    $Login = $input
                }
                default {
                    Stop-Function -Message "InputObject is not a server, database, or login."
                    return
                }
            }

            if ($ExcludeDatabase -eq $false -or $Database) {
                # if we got a database or a list of databases passed
                # and we need to enumerate mappings, login.enumdatabasemappings() takes forever
                # the cool thing though is that database.enumloginmappings() is fast. A lot.
                # if we get a list of databases passed (or even the default list of all the databases)
                # we save ourself a call to enumloginmappings if there is no map at all
                $DbMapping = @()
                $DbsToMap = $server.Databases
                if ($Database) {
                    if ($Database[0].GetType().FullName -eq 'Microsoft.SqlServer.Management.Smo.Database') {
                        $DbsToMap = $DbsToMap | Where-Object Name -in $Database.Name
                    } else {
                        $DbsToMap = $DbsToMap | Where-Object Name -in $Database
                    }
                }
                foreach ($db in $DbsToMap) {
                    if ($db.IsAccessible -eq $false) {
                        continue
                    }
                    $dbmap = $db.EnumLoginMappings()
                    foreach ($el in $dbmap) {
                        $DbMapping += [PSCustomObject]@{
                            Database  = $db.Name
                            UserName  = $el.Username
                            LoginName = $el.LoginName
                        }
                    }
                }
            }

            $serverLogins = $server.Logins

            if ($Login) {
                if ($Login[0].GetType().FullName -eq 'Microsoft.SqlServer.Management.Smo.Login') {
                    $serverLogins = $serverLogins | Where-Object { $_.Name -in $Login.Name }
                } else {
                    $serverLogins = $serverLogins | Where-Object { $_.Name -in $Login }
                }
            }

            if ($Database) {
                $serverLogins = $serverLogins | Where-Object { $_.Name -in $DbMapping.LoginName }
            }

            foreach ($sourceLogin in $serverLogins) {
                Write-Message -Level Verbose -Message "Processing login $sourceLogin"
                $userName = $sourceLogin.name

                if ($ExcludeLogin -contains $userName) {
                    Write-Message -Level Warning -Message "Skipping $userName"
                    continue
                }

                if ($userName.StartsWith("##") -or $userName -eq 'sa') {
                    Write-Message -Level Warning -Message "Skipping $userName"
                    continue
                }

                $serverName = $server

                $userBase = ($userName.Split("\")[0]).ToLowerInvariant()
                if ($serverName -eq $userBase -or $userName.StartsWith("NT ")) {
                    if ($Pscmdlet.ShouldProcess("console", "Stating $userName is skipped because it is a local machine name")) {
                        Write-Message -Level Warning -Message "$userName is skipped because it is a local machine name"
                        continue
                    }
                }

                if ($Pscmdlet.ShouldProcess("Outfile", "Adding T-SQL for login $userName")) {
                    if ($Path -or $FilePath) {
                        Write-Message -Level Verbose -Message "Exporting $userName"
                    }

                    $outsql += "$($eol)USE master$eol"
                    # Getting some attributes
                    if ($DefaultDatabase) {
                        $defaultDb = $DefaultDatabase
                    } else {
                        $defaultDb = $sourceLogin.DefaultDatabase
                    }
                    $language = $sourceLogin.Language

                    if ($sourceLogin.PasswordPolicyEnforced -eq $false) {
                        $checkPolicy = "OFF"
                    } else {
                        $checkPolicy = "ON"
                    }

                    if (!$sourceLogin.PasswordExpirationEnabled) {
                        $checkExpiration = "OFF"
                    } else {
                        $checkExpiration = "ON"
                    }

                    # Attempt to script out SQL Login
                    if ($sourceLogin.LoginType -eq "SqlLogin") {
                        if (!$ExcludePassword) {
                            $sourceLoginName = $sourceLogin.name

                            switch ($server.versionMajor) {
                                0 {
                                    $sql = "SELECT CONVERT(VARBINARY(256),password) AS hashedpass FROM master.dbo.syslogins WHERE loginname='$sourceLoginName'"
                                }
                                8 {
                                    $sql = "SELECT CONVERT(VARBINARY(256),password) AS hashedpass FROM dbo.syslogins WHERE name='$sourceLoginName'"
                                }
                                9 {
                                    $sql = "SELECT CONVERT(VARBINARY(256),password_hash) AS hashedpass FROM sys.sql_logins WHERE name='$sourceLoginName'"
                                }
                                default {
                                    $sql = "SELECT CAST(CONVERT(VARCHAR(256), CAST(LOGINPROPERTY(name,'PasswordHash') AS VARBINARY(256)), 1) AS NVARCHAR(MAX)) AS hashedpass FROM sys.server_principals WHERE principal_id = $($sourceLogin.id)"
                                }
                            }

                            try {
                                $hashedPass = $server.ConnectionContext.ExecuteScalar($sql)
                            } catch {
                                $hashedPassDt = $server.Databases['master'].ExecuteWithResults($sql)
                                $hashedPass = $hashedPassDt.Tables[0].Rows[0].Item(0)
                            }

                            if ($hashedPass.GetType().Name -ne "String") {
                                $passString = "0x"; $hashedPass | ForEach-Object {
                                    $passString += ("{0:X}" -f $_).PadLeft(2, "0")
                                }
                                $hashedPass = $passString
                            }
                        } else {
                            $hashedPass = '#######'
                        }

                        $sid = "0x"; $sourceLogin.sid | ForEach-Object {
                            $sid += ("{0:X}" -f $_).PadLeft(2, "0")
                        }
                        $outsql += "IF NOT EXISTS (SELECT loginname FROM master.dbo.syslogins WHERE name = '$userName') CREATE LOGIN [$userName] WITH PASSWORD = $hashedPass HASHED, SID = $sid, DEFAULT_DATABASE = [$defaultDb], CHECK_POLICY = $checkPolicy, CHECK_EXPIRATION = $checkExpiration, DEFAULT_LANGUAGE = [$language]"
                    }
                    # Attempt to script out Windows User
                    elseif ($sourceLogin.LoginType -eq "WindowsUser" -or $sourceLogin.LoginType -eq "WindowsGroup") {
                        $outsql += "IF NOT EXISTS (SELECT loginname FROM master.dbo.syslogins WHERE name = '$userName') CREATE LOGIN [$userName] FROM WINDOWS WITH DEFAULT_DATABASE = [$defaultDb], DEFAULT_LANGUAGE = [$language]"
                    }
                    # This script does not currently support certificate mapped or asymmetric key users.
                    else {
                        Write-Message -Level Warning -Message "$($sourceLogin.LoginType) logins not supported. $($sourceLogin.Name) skipped"
                        continue
                    }

                    if ($sourceLogin.IsDisabled) {
                        $outsql += "ALTER LOGIN [$userName] DISABLE"
                    }

                    if ($sourceLogin.DenyWindowsLogin) {
                        $outsql += "DENY CONNECT SQL TO [$userName]"
                    }
                }

                # Server Roles: sysadmin, bulklogin, etc
                foreach ($role in $server.Roles) {
                    $roleName = $role.Name

                    # SMO changed over time
                    try {
                        $roleMembers = $role.EnumMemberNames()
                    } catch {
                        $roleMembers = $role.EnumServerRoleMembers()
                    }

                    if ($roleMembers -contains $userName) {
                        if (($server.VersionMajor -lt 11 -and [string]::IsNullOrEmpty($destinationVersion)) -or ($DestinationVersion -in "SQLServer2000", "SQLServer2005", "SQLServer2008/2008R2")) {
                            $outsql += "EXEC sp_addsrvrolemember @rolename=N'$roleName', @loginame=N'$userName'"
                        } else {
                            $outsql += "ALTER SERVER ROLE [$roleName] ADD MEMBER [$userName]"
                        }
                    }
                }

                if ($ExcludeJobs -eq $false) {
                    $ownedJobs = $server.JobServer.Jobs | Where-Object { $_.OwnerLoginName -eq $userName }

                    foreach ($ownedJob in $ownedJobs) {
                        $ownedJob = $ownedJob -replace ("'", "''")
                        $outsql += "$($eol)USE msdb$eol"
                        $outsql += "EXEC msdb.dbo.sp_update_job @job_name=N'$ownedJob', @owner_login_name=N'$userName'"
                    }
                }

                if ($server.VersionMajor -ge 9) {
                    # These operations are only supported by SQL Server 2005 and above.
                    # Securables: Connect SQL, View any database, Administer Bulk Operations, etc.

                    $perms = $server.EnumServerPermissions($userName)
                    $outsql += "$($eol)USE master$eol"
                    foreach ($perm in $perms) {
                        $permState = $perm.permissionstate
                        $permType = $perm.PermissionType
                        $grantor = $perm.grantor

                        if ($permState -eq "GrantWithGrant") {
                            $grantWithGrant = "WITH GRANT OPTION"
                            $permState = "GRANT"
                        } else {
                            $grantWithGrant = $null
                        }

                        $outsql += "$permState $permType TO [$userName] $grantWithGrant AS [$grantor]"
                    }

                    # Credential mapping. Credential removal not currently supported for Syncs.
                    $loginCredentials = $server.Credentials | Where-Object { $_.Identity -eq $sourceLogin.Name }
                    foreach ($credential in $loginCredentials) {
                        $credentialName = $credential.Name
                        $outsql += "PRINT '$userName is associated with the $credentialName credential'"
                    }
                }

                if ($ExcludeDatabase -eq $false) {
                    $dbs = $sourceLogin.EnumDatabaseMappings() | Sort-Object DBName

                    if ($Database) {
                        if ($Database[0].GetType().FullName -eq 'Microsoft.SqlServer.Management.Smo.Database') {
                            $dbs = $dbs | Where-Object { $_.DBName -in $Database.Name }
                        } else {
                            $dbs = $dbs | Where-Object { $_.DBName -in $Database }
                        }
                    }

                    # Adding database mappings and securables
                    foreach ($db in $dbs) {
                        $dbName = $db.dbname
                        $sourceDb = $server.Databases[$dbName]
                        $dbUserName = $db.username

                        $outsql += "$($eol)USE [$dbName]$eol"

                        $scriptOptions = New-DbaScriptingOption
                        $scriptVersion = $sourceDb.CompatibilityLevel
                        $scriptOptions.TargetServerVersion = [Microsoft.SqlServer.Management.Smo.SqlServerVersion]::$scriptVersion
                        $scriptOptions.ContinueScriptingOnError = $false
                        $scriptOptions.IncludeDatabaseContext = $false
                        $scriptOptions.IncludeIfNotExists = $true

                        if ($ObjectLevel) {
                            # Exporting all permissions
                            $scriptOptions.AllowSystemObjects = $true
                            $scriptOptions.IncludeDatabaseRoleMemberships = $true

                            $exportSplat = @{
                                SqlInstance            = $server
                                Database               = $dbName
                                User                   = $dbUsername
                                ScriptingOptionsObject = $scriptOptions
                            }
                            # remove batch separator if the $BatchSeparator string is empty
                            if (-Not $BatchSeparator) {
                                $scriptOptions.NoCommandTerminator = $true
                                $exportSplat.ExcludeGoBatchSeparator = $true
                            }
                            try {
                                $userScript = Export-DbaUser @exportSplat -Passthru -EnableException
                                $outsql += $userScript
                            } catch {
                                Stop-Function -Message "Failed to extract permissions for user $dbUserName in database $dbName" -Continue -ErrorRecord $_
                            }

                            if ($IncludeRolePermissions) {
                                foreach ($role in $sourceDb.Roles) {
                                    if ($role.IsFixedRole -eq $false -and $role.EnumMembers() -contains $dbUserName) {
                                        $splatExportRole = @{
                                            SqlInstance    = $server
                                            Database       = $dbName
                                            Role           = $role.Name
                                            Passthru       = $true
                                            NoPrefix       = $true
                                            BatchSeparator = ""
                                        }
                                        try {
                                            $roleScript = Export-DbaDbRole @splatExportRole
                                            if ($roleScript) {
                                                $outsql += $roleScript
                                            }
                                        } catch {
                                            Write-Message -Level Warning -Message "Failed to export permissions for role $($role.Name) in database $dbName : $($_.Exception.Message)"
                                        }
                                    }
                                }
                            }
                        } else {
                            try {
                                $sql = $server.Databases[$dbName].Users[$dbUserName].Script($scriptOptions)
                                $outsql += $sql
                            } catch {
                                Write-Message -Level Warning -Message "User cannot be found in selected database"
                            }

                            # Skipping updating dbowner

                            # Database Roles: db_owner, db_datareader, etc
                            foreach ($role in $sourceDb.Roles) {
                                if ($role.EnumMembers() -contains $dbUserName) {
                                    $roleName = $role.Name
                                    if (($server.VersionMajor -lt 11 -and [string]::IsNullOrEmpty($destinationVersion)) -or ($DestinationVersion -in "SQLServer2000", "SQLServer2005", "SQLServer2008/2008R2")) {
                                        $outsql += "EXEC sp_addrolemember @rolename=N'$roleName', @membername=N'$dbUserName'"
                                    } else {
                                        $outsql += "ALTER ROLE [$roleName] ADD MEMBER [$dbUserName]"
                                    }
                                }
                            }

                            if ($IncludeRolePermissions) {
                                foreach ($role in $sourceDb.Roles) {
                                    if ($role.IsFixedRole -eq $false -and $role.EnumMembers() -contains $dbUserName) {
                                        $splatExportRole = @{
                                            SqlInstance    = $server
                                            Database       = $dbName
                                            Role           = $role.Name
                                            Passthru       = $true
                                            NoPrefix       = $true
                                            BatchSeparator = ""
                                        }
                                        try {
                                            $roleScript = Export-DbaDbRole @splatExportRole
                                            if ($roleScript) {
                                                $outsql += $roleScript
                                            }
                                        } catch {
                                            Write-Message -Level Warning -Message "Failed to export permissions for role $($role.Name) in database $dbName : $($_.Exception.Message)"
                                        }
                                    }
                                }
                            }

                            # Connect, Alter Any Assembly, etc
                            $perms = $sourceDb.EnumDatabasePermissions($dbUserName)
                            foreach ($perm in $perms) {
                                $permState = $perm.PermissionState
                                $permType = $perm.PermissionType
                                $grantor = $perm.Grantor

                                if ($permState -eq "GrantWithGrant") {
                                    $grantWithGrant = "WITH GRANT OPTION"
                                    $permState = "GRANT"
                                } else {
                                    $grantWithGrant = $null
                                }

                                $outsql += "$permState $permType TO [$userName] $grantWithGrant AS [$grantor]"
                            }
                        }
                    }
                }
                $loginObject = [PSCustomObject]@{
                    Name     = $userName
                    Instance = $server.Name
                    Sql      = $outsql
                }
                $logonCollection.Add($loginObject) | Out-Null
                $outsql = @()
            }
        }
    }
    end {
        foreach ($login in $logonCollection) {
            if ($NoPrefix) {
                $prefix = $null
            } else {
                $prefix = "/*$eol`tCreated by $executingUser using dbatools $commandName for objects on $($login.Instance) at $(Get-Date -Format (Get-DbatoolsConfigValue -FullName 'Formatting.DateTime'))$eol`tSee https://dbatools.io/$commandName for more information$eol*/"
            }

            if ($BatchSeparator) {
                $sql = $login.SQL -join "$eol$BatchSeparator$eol"
                #add the final GO
                $sql += "$eol$BatchSeparator"
            } else {
                $sql = $login.SQL
            }



            if ($Passthru) {
                if ($null -ne $prefix) {
                    $sql = $prefix + $sql
                }
                $sql
            } elseif ($Path -Or $FilePath) {
                if ($instanceArray -notcontains $($login.Instance)) {
                    if ($null -ne $prefix) {
                        $sql = $prefix + $sql
                    }
                    $scriptPath = Get-ExportFilePath -Path $PSBoundParameters.Path -FilePath $PSBoundParameters.FilePath -Type sql -ServerName $login.Instance
                    $sql | Out-File -Encoding $Encoding -FilePath $scriptPath -Append:$Append -NoClobber:$NoClobber
                    $instanceArray += $login.Instance
                    Get-ChildItem $scriptPath
                } else {
                    $sql | Out-File -Encoding $Encoding -FilePath $scriptPath -Append
                }
            } else {
                $sql
            }
        }
    }
}