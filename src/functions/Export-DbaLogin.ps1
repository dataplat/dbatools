function Export-DbaLogin {
    <#
    .SYNOPSIS
        Exports Windows and SQL Logins to a T-SQL file. Export includes login, SID, password, default database, default language, server permissions, server roles, db permissions, db roles.

    .DESCRIPTION
        Exports Windows and SQL Logins to a T-SQL file. Export includes login, SID, password, default database, default language, server permissions, server roles, db permissions, db roles.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. SQL Server 2000 and above supported.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER InputObject
        Enables piping from Get-DbaDatabase, Get-DbaLogin and more.

    .PARAMETER Login
        The login(s) to process. Options for this list are auto-populated from the server. If unspecified, all logins will be processed.

    .PARAMETER ExcludeLogin
        The login(s) to exclude. Options for this list are auto-populated from the server.

    .PARAMETER Database
        The database(s) to process. Options for this list are auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeJobs
        If this switch is enabled, Agent job ownership will not be exported.

    .PARAMETER ExcludeDatabase
        If this switch is enabled, mappings for databases will not be exported.

    .PARAMETER ExcludePassword
        If this switch is enabled, hashed passwords will not be exported.

   .PARAMETER DefaultDatabase
        If this switch is enabled, all logins will be scripted with specified default database,
        that could help to successfully import logins on server that is missing default database for login.

    .PARAMETER Path
        Specifies the directory where the file or files will be exported.
        Will default to Path.DbatoolsExport Configuration entry

    .PARAMETER FilePath
        Specifies the full file path of the output file. If left blank then filename based on Instance name and date is created.
        If more than one instance is input then this parameter should be blank.

    .PARAMETER Passthru
        Output script to console

    .PARAMETER BatchSeparator
        Batch separator for scripting output. Uses the value from configuration Formatting.BatchSeparator by default. This is normally "GO"

    .PARAMETER NoClobber
        If this switch is enabled, a file already existing at the path specified by Path will not be overwritten.

    .PARAMETER Append
        If this switch is enabled, content will be appended to a file already existing at the path specified by Path. If the file does not exist, it will be created.

    .PARAMETER DestinationVersion
        To say to which version the script should be generated. If not specified will use instance major version.

    .PARAMETER NoPrefix
        Do not include a Prefix

    .PARAMETER Encoding
        Specifies the file encoding. The default is UTF8.

        Valid values are:
        -- ASCII: Uses the encoding for the ASCII (7-bit) character set.
        -- BigEndianUnicode: Encodes in UTF-16 format using the big-endian byte order.
        -- Byte: Encodes a set of characters into a sequence of bytes.
        -- String: Uses the encoding type for a string.
        -- Unicode: Encodes in UTF-16 format using the little-endian byte order.
        -- UTF7: Encodes in UTF-7 format.
        -- UTF8: Encodes in UTF-8 format.
        -- Unknown: The encoding type is unknown or invalid. The data can be treated as binary.

    .PARAMETER ObjectLevel
        Include object-level permissions for each user associated with copied login.

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
        [ValidateSet('SQLServer2000', 'SQLServer2005', 'SQLServer2008/2008R2', 'SQLServer2012', 'SQLServer2014', 'SQLServer2016', 'SQLServer2017', 'SQLServer2019')]
        [string]$DestinationVersion,
        [switch]$NoPrefix,
        [switch]$Passthru,
        [switch]$ObjectLevel,
        [switch]$EnableException
    )

    begin {
        $null = Test-ExportDirectory -Path $Path
        $outsql = @()
        $instanceArray = @()
        $logonCollection = New-Object System.Collections.ArrayList
        $executingUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $commandName = $MyInvocation.MyCommand.Name

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
                'Sqlcollaborative.Dbatools.Parameter.DbaInstanceParameter' {
                    Write-Message -Level Verbose -Message "Processing Server through InputObject"
                    $server = Connect-SqlInstance -SqlInstance $input -SqlCredential $SqlCredential
                }
                'Microsoft.SqlServer.Management.Smo.Server' {
                    Write-Message -Level Verbose -Message "Processing Server through InputObject"
                    $server = Connect-SqlInstance -SqlInstance $input -SqlCredential $SqlCredential
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
                        $DbMapping += [pscustomobject]@{
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

                    $outsql += "`r`nUSE master`r`n"
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
                                    $sql = "SELECT CONVERT(VARBINARY(256),password_hash) as hashedpass FROM sys.sql_logins WHERE name='$sourceLoginName'"
                                }
                                default {
                                    $sql = "SELECT CAST(CONVERT(varchar(256), CAST(LOGINPROPERTY(name,'PasswordHash') AS VARBINARY(256)), 1) AS NVARCHAR(max)) AS hashedpass FROM sys.server_principals WHERE principal_id = $($sourceLogin.id)"
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
                            $outsql += "EXEC sys.sp_addsrvrolemember @rolename=N'$roleName', @loginame=N'$userName'"
                        } else {
                            $outsql += "ALTER SERVER ROLE [$roleName] ADD MEMBER [$userName]"
                        }
                    }
                }

                if ($ExcludeJobs -eq $false) {
                    $ownedJobs = $server.JobServer.Jobs | Where-Object { $_.OwnerLoginName -eq $userName }

                    foreach ($ownedJob in $ownedJobs) {
                        $ownedJob = $ownedJob -replace ("'", "''")
                        $outsql += "`r`nUSE msdb`r`n"
                        $outsql += "EXEC msdb.dbo.sp_update_job @job_name=N'$ownedJob', @owner_login_name=N'$userName'"
                    }
                }

                if ($server.VersionMajor -ge 9) {
                    # These operations are only supported by SQL Server 2005 and above.
                    # Securables: Connect SQL, View any database, Administer Bulk Operations, etc.

                    $perms = $server.EnumServerPermissions($userName)
                    $outsql += "`r`nUSE master`r`n"
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

                        $outsql += "`r`nUSE [$dbName]`r`n"

                        if ($ObjectLevel) {
                            # Exporting all permissions
                            $scriptOptions = New-DbaScriptingOption
                            $scriptVersion = $sourceDb.CompatibilityLevel
                            $scriptOptions.TargetServerVersion = [Microsoft.SqlServer.Management.Smo.SqlServerVersion]::$scriptVersion
                            $scriptOptions.AllowSystemObjects = $true
                            $scriptOptions.IncludeDatabaseRoleMemberships = $true
                            $scriptOptions.ContinueScriptingOnError = $false
                            $scriptOptions.IncludeDatabaseContext = $false
                            $scriptOptions.IncludeIfNotExists = $true

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
                        } else {
                            try {
                                $sql = $server.Databases[$dbName].Users[$dbUserName].Script()
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
                                        $outsql += "EXEC sys.sp_addrolemember @rolename=N'$roleName', @membername=N'$dbUserName'"
                                    } else {
                                        $outsql += "ALTER ROLE [$roleName] ADD MEMBER [$dbUserName]"
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
                $prefix = "/*`r`n`tCreated by $executingUser using dbatools $commandName for objects on $($login.Instance) at $(Get-Date -Format (Get-DbatoolsConfigValue -FullName 'Formatting.DateTime'))`r`n`tSee https://dbatools.io/$commandName for more information`r`n*/"
            }

            if ($BatchSeparator) {
                $sql = $login.SQL -join "`r`n$BatchSeparator`r`n"
                #add the final GO
                $sql += "`r`n$BatchSeparator"
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
