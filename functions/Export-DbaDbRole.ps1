function Export-DbaDbRole {
    <#
    .SYNOPSIS
        Exports database roles to a T-SQL file. Export includes Role creation, object permissions and Schema ownership.

    .DESCRIPTION
        Exports database roles to a T-SQL file. Export includes Role creation, object permissions and Schema ownership.

        This command is based off of John Eisbrener's post "Fully Script out a MSSQL Database Role"
        Reference:  https://dbaeyes.wordpress.com/2013/04/19/fully-script-out-a-mssql-database-role/

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. SQL Server 2005 and above supported.
        Any databases in CompatibilityLevel 80 or lower will be skipped

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER InputObject
        Enables piping from Get-DbaDatabase and Get-DbaLogin.

     .PARAMETER ScriptingOptionsObject
        An SMO Scripting Object that can be used to customize the output - see New-DbaScriptingOption

    .PARAMETER Database
        The database(s) to process. Options for this list are auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER Role
        The Role(s) to process. If unspecified, all Roles will be processed.

    .PARAMETER ExcludeRole
        The Role(s) to exclude.

    .PARAMETER ExcludeFixedRole
        Excludes all members of fixed roles.

    .PARAMETER IncludeRoleMember
        Include scripting of role members in script

    .PARAMETER Path
        Specifies the directory where the file or files will be exported.
        Will default to Path.DbatoolsExport Configuration entry

    .PARAMETER FilePath
        Specifies the full file path of the output file. If left blank then filename based on Instance name, Database name and date is created.
        If more than one database or instance is input then this parameter should normally be blank.

    .PARAMETER Passthru
        Output script to console only

    .PARAMETER BatchSeparator
        Batch separator for scripting output. Uses the value from configuration Formatting.BatchSeparator by default. This is normally "GO"

    .PARAMETER NoClobber
        If this switch is enabled, a file already existing at the path specified by Path will not be overwritten. This takes precedence over Append switch

    .PARAMETER Append
        If this switch is enabled, content will be appended to a file already existing at the path specified by FilePath. If the file does not exist, it will be created.

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


    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Export, Role
        Author: Patrick Flynn (@sqllensman)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Export-DbaDbRole

    .EXAMPLE
        PS C:\> Export-DbaDbRole -SqlInstance sql2005 -Path C:\temp

        Exports all the Database Roles for SQL Server "sql2005" and writes them to the file "C:\temp\sql2005-logins.sql"

    .EXAMPLE
        PS C:\> Export-DbaDbRole -SqlInstance sqlserver2014a -ExcludeRole realcajun -SqlCredential $scred -Path C:\temp\roles.sql -Append

        Authenticates to sqlserver2014a using SQL Authentication. Exports all roles except for realcajun to C:\temp\roles.sql, and appends to the file if it exists. If not, the file will be created.

    .EXAMPLE
        PS C:\> Export-DbaDbRole -SqlInstance sqlserver2014a -Role realcajun,netnerds -Path C:\temp\roles.sql

        Exports ONLY roles netnerds and realcajun FROM sqlserver2014a to the file C:\temp\roles.sql

    .EXAMPLE
        PS C:\> Export-DbaDbRole -SqlInstance sqlserver2014a -Role realcajun,netnerds -Database HR, Accounting

        Exports ONLY roles netnerds and realcajun FROM sqlserver2014a with the permissions on databases HR and Accounting

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sqlserver2014a -Database HR, Accounting | Export-DbaDbRole

        Exports ONLY roles FROM sqlserver2014a with permissions on databases HR and Accounting

    .EXAMPLE
        PS C:\> Set-DbatoolsConfig -FullName formatting.batchseparator -Value $null
        PS C:\> Export-DbaDbRole -SqlInstance sqlserver2008 -Role realcajun,netnerds -Path C:\temp\roles.sql

        Sets the BatchSeparator configuration to null, removing the default "GO" value.
        Exports ONLY roles netnerds and realcajun FROM sqlserver2008 server, to the C:\temp\roles.sql file, without the "GO" batch separator.

    .EXAMPLE
        PS C:\> Export-DbaDbRole -SqlInstance sqlserver2008 -Role realcajun,netnerds -Path C:\temp\roles.sql -BatchSeparator $null

        Exports ONLY roles netnerds and realcajun FROM sqlserver2008 server, to the C:\temp\roles.sql file, without the "GO" batch separator.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sqlserver2008 | Export-DbaDbRole -Role realcajun

        Exports role realcajun for all databases on sqlserver2008

    .EXAMPLE
        PS C:\> Get-DbaDbRole -SqlInstance sqlserver2008 -ExcludeFixedRole | Export-DbaDbRole

        Exports all roles from all databases on sqlserver2008, excludes all roles marked as as FixedRole

    #>
    [CmdletBinding()]
    param (
        [parameter()]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [Microsoft.SqlServer.Management.Smo.ScriptingOptions]$ScriptingOptionsObject,
        [object[]]$Database,
        [object[]]$Role,
        [object[]]$ExcludeRole,
        [switch]$ExcludeFixedRole,
        [switch]$IncludeRoleMember,
        [string]$Path = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport'),
        [Alias("OutFile", "FileName")]
        [string]$FilePath,
        [switch]$Passthru,
        [string]$BatchSeparator = (Get-DbatoolsConfigValue -FullName 'Formatting.BatchSeparator'),
        [switch]$NoClobber,
        [switch]$Append,
        [switch]$NoPrefix,
        [ValidateSet('ASCII', 'BigEndianUnicode', 'Byte', 'String', 'Unicode', 'UTF7', 'UTF8', 'Unknown')]
        [string]$Encoding = 'UTF8',
        [switch]$EnableException
    )
    begin {
        $null = Test-ExportDirectory -Path $Path
        $outsql = @()
        $outputFileArray = @()
        $roleCollection = New-Object System.Collections.ArrayList
        $executingUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $commandName = $MyInvocation.MyCommand.Name

        $roleSQL = "SELECT
                        N'/*RoleName*/' as RoleName,
                        CASE dp.state
                            WHEN 'D' THEN 'DENY'
                            WHEN 'G' THEN 'GRANT'
                            WHEN 'R' THEN 'REVOKE'
                            WHEN 'W' THEN 'GRANT'
                        END as GrantState,
                        dp.permission_name as Permission,
                        CASE dp.class
                            WHEN 0 THEN ''
                            WHEN 1 THEN --table or column subset on the table
                                CASE WHEN dp.major_id < 0 THEN COALESCE('[sys].[' + OBJECT_NAME(dp.major_id) + ']', '')
                                    ELSE '[' + (SELECT SCHEMA_NAME(schema_id) + '].[' + name FROM sys.objects WHERE object_id = dp.major_id) + ']'
                                END + -- optionally concatenate column names
                                    CASE WHEN MAX(dp.minor_id) > 0 THEN ' (['
                                        + REPLACE((SELECT name + '], [' FROM sys.columns
                                                WHERE object_id = dp.major_id
                                                AND column_id IN (SELECT minor_id FROM sys.database_permissions WHERE major_id = dp.major_id AND USER_NAME(grantee_principal_id) = N'/*RoleName*/')
                                        FOR XML PATH('')) + '])', ', []', '')
                                        ELSE ''
                                    END
                            WHEN 3 THEN 'SCHEMA::[' + SCHEMA_NAME(dp.major_id) + ']'
                            WHEN 4 THEN '' + (SELECT RIGHT(type_desc, 4) + '::[' + name FROM sys.database_principals WHERE principal_id = dp.major_id) + ']'
                            WHEN 5 THEN 'ASSEMBLY::[' + (SELECT name FROM sys.assemblies WHERE assembly_id = dp.major_id) + ']'
                            WHEN 6 THEN 'TYPE::[' + (SELECT name FROM sys.types WHERE user_type_id = dp.major_id) + ']'
                            WHEN 10 THEN 'XML SCHEMA COLLECTION::[' + (SELECT SCHEMA_NAME(schema_id) + '.' + name FROM sys.xml_schema_collections WHERE xml_collection_id = dp.major_id) + ']'
                            WHEN 15 THEN 'MESSAGE TYPE::[' + (SELECT name FROM sys.service_message_types WHERE message_type_id = dp.major_id) + ']'
                            WHEN 16 THEN 'CONTRACT::[' + (SELECT name FROM sys.service_contracts WHERE service_contract_id = dp.major_id) + ']'
                            WHEN 17 THEN 'SERVICE::[' + (SELECT name FROM sys.services WHERE service_id = dp.major_id) + ']'
                            WHEN 18 THEN 'REMOTE SERVICE BINDING::[' + (SELECT name FROM sys.remote_service_bindings WHERE remote_service_binding_id = dp.major_id) + ']'
                            WHEN 19 THEN 'ROUTE::[' + (SELECT name FROM sys.routes WHERE route_id = dp.major_id) + ']'
                            WHEN 23 THEN 'FULLTEXT CATALOG::[' + (SELECT name FROM sys.fulltext_catalogs WHERE fulltext_catalog_id = dp.major_id) + ']'
                            WHEN 24 THEN 'SYMMETRIC KEY::[' + (SELECT name FROM sys.symmetric_keys WHERE symmetric_key_id = dp.major_id) + ']'
                            WHEN 25 THEN 'CERTIFICATE::[' + (SELECT name FROM sys.certificates WHERE certificate_id = dp.major_id) + ']'
                            WHEN 26 THEN 'ASYMMETRIC KEY::[' + (SELECT name FROM sys.asymmetric_keys WHERE asymmetric_key_id = dp.major_id) + ']'
                        END COLLATE DATABASE_DEFAULT  as Type,
                        CASE dp.state WHEN 'W' THEN ' WITH GRANT OPTION' ELSE '' END as GrantType
                    FROM sys.database_permissions dp
                    WHERE USER_NAME(dp.grantee_principal_id) = N'/*RoleName*/'
                    GROUP BY dp.state, dp.major_id, dp.permission_name, dp.class
                    UNION ALL
                    SELECT
                        N'/*RoleName*/' as RoleName,
                        'ALTER' as GrantState,
                        'AUTHORIZATION' as permission_name,
                        'SCHEMA::['+s.[name]+']' as Type,
                        '' as GrantType
                    from sys.schemas s
                    join sys.sysusers u on s.principal_id = u.[uid]
                    where u.[name] = N'/*RoleName*/'"

        $userSQL = "SELECT roles.name as RoleName, users.name as Member
                    FROM sys.database_principals users
                    INNER JOIN sys.database_role_members link
                        ON link.member_principal_id = users.principal_id
                    INNER JOIN sys.database_principals roles
                        ON roles.principal_id = link.role_principal_id
                    WHERE roles.name = N'/*RoleName*/'"

        if (Test-Bound -Not -ParameterName ScriptingOptionsObject) {
            $ScriptingOptionsObject = New-DbaScriptingOption
            $ScriptingOptionsObject.AllowSystemObjects = $false
            $ScriptingOptionsObject.IncludeDatabaseRoleMemberships = $true
            $ScriptingOptionsObject.ContinueScriptingOnError = $false
            $ScriptingOptionsObject.IncludeDatabaseContext = $true
            $ScriptingOptionsObject.IncludeIfNotExists = $false
        }

        if ($ScriptingOptionsObject.NoCommandTerminator) {
            $commandTerminator = ''
        } else {
            $commandTerminator = ';'
        }
        $outsql = @()
    }
    process {
        if (Test-FunctionInterrupt) {
            return
        }

        if (-not $InputObject -and -not $SqlInstance) {
            Stop-Function -Message "You must pipe in a role, database, or server or specify a SqlInstance"
            return
        }

        if ($SqlInstance) {
            $InputObject = $SqlInstance
        }

        foreach ($input in $InputObject) {
            $inputType = $input.GetType().FullName
            switch ($inputType) {
                'Sqlcollaborative.Dbatools.Parameter.DbaInstanceParameter' {
                    Write-Message -Level Verbose -Message "Processing DbaInstanceParameter through InputObject"
                    $databaseRoles = Get-DbaDbRole -SqlInstance $input -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase -Role $Role -ExcludeRole $ExcludeRole -ExcludeFixedRole:$ExcludeFixedRole
                }
                'Microsoft.SqlServer.Management.Smo.Server' {
                    Write-Message -Level Verbose -Message "Processing Server through InputObject"
                    $databaseRoles = Get-DbaDbRole -SqlInstance $input -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase -Role $Role -ExcludeRole $ExcludeRole -ExcludeFixedRole:$ExcludeFixedRole
                }
                'Microsoft.SqlServer.Management.Smo.Database' {
                    Write-Message -Level Verbose -Message "Processing Database through InputObject"
                    $databaseRoles = $input | Get-DbaDbRole -ExcludeDatabase $ExcludeDatabase -Role $Role -ExcludeRole $ExcludeRole -ExcludeFixedRole:$ExcludeFixedRole
                }
                'Microsoft.SqlServer.Management.Smo.DatabaseRole' {
                    Write-Message -Level Verbose -Message "Processing DatabaseRole through InputObject"
                    $databaseRoles = $input
                }
                default {
                    Stop-Function -Message "InputObject is not a server, database, or login."
                    return
                }
            }
            foreach ($dbRole in $databaseRoles) {
                try {
                    $server = $dbRole.Parent.Parent
                    $db = $dbRole.Parent
                    if ($server.VersionMajor -lt 9) {
                        Stop-Function -Message "SQL Server version 9 or higher required - $server not supported." -Continue
                    }
                    $dbCompatibilityLevel = [int]($db.CompatibilityLevel.ToString().Replace('Version', ''))
                    if ($dbCompatibilityLevel -lt 90) {
                        Stop-Function -Message "$db has a compatibility level lower than Version90 and will be skipped." -Target $db -Continue
                    }

                    $outsql += $dbRole.Script($ScriptingOptionsObject)

                    $query = $roleSQL.Replace('/*RoleName*/', "$($dbRole.Name)")
                    $rolePermissions = $($dbRole.Parent).Query($query)

                    foreach ($rolePermission in $rolePermissions) {
                        $script = $rolePermission.GrantState + " " + $rolePermission.Permission
                        if ($rolePermission.Type) {
                            $script += " ON " + $rolePermission.Type
                        }
                        if ($rolePermission.RoleName) {
                            $script += " TO [" + $rolePermission.RoleName + "]"
                        }
                        if ($rolePermission.GrantType) {
                            $script += " WITH GRANT OPTION" + $commandTerminator
                        } else {
                            $script += $commandTerminator
                        }
                        $outsql += "$script"
                    }

                    if ($IncludeRoleMember) {
                        $query = $userSQL.Replace('/*RoleName*/', "$($dbRole.Name)")
                        $roleUsers = $($dbRole.Parent).Query($query)

                        foreach ($roleUser in $roleUsers) {
                            if ($server.VersionMajor -lt 11) {
                                $script += "EXEC sys.sp_addrolemember @rolename=N'$roleName', @membername=N'$userName'"
                            } else {
                                $script = 'ALTER ROLE [' + $roleUser.RoleName + "] ADD MEMBER [" + $roleUser.Member + "]" + $commandTerminator
                            }
                            $outsql += "$script"
                        }
                    }
                    $roleObject = [PSCustomObject]@{
                        Name     = $dbRole.Name
                        Instance = $dbRole.SqlInstance
                        Database = $dbRole.Database
                        Sql      = $outsql
                    }
                    $roleCollection.Add($roleObject) | Out-Null
                    $outsql = @()
                } catch {
                    $outsql = @()
                    Stop-Function -Message "Error occurred processing role $dbRole" -Category ConnectionError -ErrorRecord $_ -Target $server -Continue
                }
            }
        }
    }
    end {
        if (Test-FunctionInterrupt) { return }

        $timeNow = $(Get-Date -Format (Get-DbatoolsConfigValue -FullName 'Formatting.DateTime'))
        foreach ($dbRole in $roleCollection) {
            $instanceName = $dbRole.Instance
            $databaseName = $dbRole.Database

            $outputFileName = $instanceName.Replace('\', '$') + '-' + $databaseName.Replace('\', '$')

            if ($NoPrefix) {
                $prefix = $null
            } else {
                $prefix = "/*`n`tCreated by $executingUser using dbatools $commandName for objects on $instanceName.$databaseName at $timeNow`n`tSee https://dbatools.io/$commandName for more information`n*/"
            }

            if ($BatchSeparator) {
                $sql = $dbRole.SQL -join "`r`n$BatchSeparator`r`n"
                #add the final GO
                $sql += "`r`n$BatchSeparator"
            } else {
                $sql = $dbRole.SQL
            }

            if ($Passthru) {
                if ($null -ne $prefix) {
                    $sql = "$prefix`r`n$sql"
                }
                $sql
            } elseif ($Path -Or $FilePath) {
                if ($outputFileArray -notcontains $outputFileName) {
                    Write-Message -Level Verbose -Message "New File $outputFileName "
                    if ($null -ne $prefix) {
                        $sql = "$prefix`r`n$sql"
                    }
                    $scriptPath = Get-ExportFilePath -Path $PSBoundParameters.Path -FilePath $PSBoundParameters.FilePath -Type sql -ServerName $outputFileName
                    $sql | Out-File -Encoding $Encoding -LiteralPath $scriptPath -Append:$Append -NoClobber:$NoClobber
                    $outputFileArray += $outputFileName
                    Get-ChildItem $scriptPath
                } else {
                    Write-Message -Level Verbose -Message "Adding to $outputFileName "
                    $sql | Out-File -Encoding $Encoding -LiteralPath $scriptPath -Append
                }
            } else {
                $sql
            }
        }
    }
}