function Export-DbaServerRole {
    <#
    .SYNOPSIS
        Generates T-SQL scripts for server-level roles including permissions and memberships

    .DESCRIPTION
        Creates complete T-SQL scripts that can recreate server-level roles along with their permissions and memberships on another instance. This eliminates the need to manually recreate security configurations during server migrations or disaster recovery scenarios. The function queries sys.server_permissions to capture all role permissions (GRANT, DENY, REVOKE) and generates the appropriate T-SQL statements for role creation and member assignments.

        Primarily targets SQL Server 2012 and higher where user-defined server roles were introduced, but works on earlier versions to script role memberships for built-in roles.
        This command extends John Eisbrener's post "Fully Script out a MSSQL Database Role"
        Reference:  https://dbaeyes.wordpress.com/2013/04/19/fully-script-out-a-mssql-database-role/

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. SQL Server 2000 and above supported.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER InputObject
        Accepts server role objects from Get-DbaServerRole for pipeline processing. Use this when you need to filter roles first with Get-DbaServerRole before exporting.

    .PARAMETER ScriptingOptionsObject
        Provides custom SMO scripting options to control the generated T-SQL output format. Use New-DbaScriptingOption to create custom options when you need specific formatting requirements like excluding object owners or database context.

    .PARAMETER ServerRole
        Specifies which server-level roles to export by name. Useful when you only need to script specific custom roles instead of all roles on the instance.

    .PARAMETER ExcludeServerRole
        Excludes specific server-level roles from the export by name. Use this to skip problematic roles or roles you don't want to migrate to the target instance.

    .PARAMETER ExcludeFixedRole
        Excludes built-in server roles like sysadmin, serveradmin, and dbcreator from the export. Use this when migrating between instances where you only want to transfer custom user-defined roles. On SQL Server 2008/2008R2, this will exclude all roles since user-defined server roles weren't supported.

    .PARAMETER IncludeRoleMember
        Includes ALTER SERVER ROLE statements to add current role members to the exported script. Essential when you need to recreate both the roles and their membership assignments on the target instance.

    .PARAMETER Path
        Specifies the directory where script files will be saved. Defaults to the Path.DbatoolsExport configuration setting. Use this when you want to organize exports in a specific folder structure for your deployment process.

    .PARAMETER FilePath
        Specifies the complete file path for the exported script. When blank, creates timestamped files using the instance name. Use this when you need consistent file naming for deployment pipelines or when exporting from a single instance.

    .PARAMETER Passthru
        Displays the generated T-SQL script in the console instead of saving to file. Perfect for quick review of the script or when you need to copy-paste the output directly into SSMS.

    .PARAMETER BatchSeparator
        Sets the batch separator used between T-SQL statements in the output. Defaults to the configured value, typically 'GO'. Change this when deploying to tools that use different batch separators or set to empty string to remove separators entirely.

    .PARAMETER NoClobber
        Prevents overwriting existing files at the target location. Use this as a safety measure when running automated exports to avoid accidentally replacing important deployment scripts.

    .PARAMETER Append
        Adds the exported script to an existing file instead of overwriting it. Useful when building comprehensive deployment scripts that combine multiple exports into a single file.

    .PARAMETER NoPrefix
        Excludes the header comment block that contains generation metadata like timestamp and user information. Use this when you need clean T-SQL output without documentation headers for automated deployments.

    .PARAMETER Encoding
        Sets the character encoding for the output file. Defaults to UTF8 which handles international characters correctly. Change to ASCII only if you're certain the role names contain no special characters and need compatibility with older systems.


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
        https://dbatools.io/Export-DbaServerRole

    .OUTPUTS
        System.String

        When -Passthru is specified, or when neither -Path nor -FilePath is provided, returns the generated T-SQL script as a string.

        Properties of the output include:
        - Role creation statements with IF NOT EXISTS clauses
        - GRANT, DENY, and REVOKE permission statements for each role's permissions
        - Optional ALTER SERVER ROLE statements to add current role members (when -IncludeRoleMember is specified)
        - Optional header comment block with generation metadata (unless -NoPrefix is specified)
        - Batch separator statements between T-SQL commands (configurable via -BatchSeparator)

        System.IO.FileInfo

        When -Path or -FilePath is specified (and -Passthru is not used), returns FileInfo objects for each script file created, one per instance processed.

        Properties:
        - FullName: Complete file path where the script was saved
        - Name: File name of the exported script
        - Directory: Directory containing the script file
        - Length: Size of the file in bytes
        - CreationTime: Timestamp when the file was created
        - LastWriteTime: Timestamp of the last modification

    .EXAMPLE
        PS C:\> Export-DbaServerRole -SqlInstance sql2005

        Exports the Server Roles for SQL Server "sql2005" and writes them to the path defined in the ConfigValue 'Path.DbatoolsExport' using a a default name pattern of ServerName-YYYYMMDDhhmmss-serverrole. Uses BatchSeparator defined by Config 'Formatting.BatchSeparator'

    .EXAMPLE
        PS C:\> Export-DbaServerRole -SqlInstance sql2005 -Path C:\temp

        Exports the Server Roles for SQL Server "sql2005" and writes them to the path "C:\temp" using a a default name pattern of ServerName-YYYYMMDDhhmmss-serverrole. Uses BatchSeparator defined by Config 'Formatting.BatchSeparator'

    .EXAMPLE
        PS C:\> Export-DbaServerRole -SqlInstance sqlserver2014a -FilePath C:\temp\ServerRoles.sql

        Exports the Server Roles for SQL Server sqlserver2014a to the file  C:\temp\ServerRoles.sql. Overwrites file if exists

    .EXAMPLE
        PS C:\> Export-DbaServerRole -SqlInstance sqlserver2014a -ServerRole SchemaReader -Passthru

        Exports ONLY ServerRole SchemaReader FROM sqlserver2014a and writes script to console

    .EXAMPLE
        PS C:\> Export-DbaServerRole -SqlInstance sqlserver2008 -ExcludeFixedRole -ExcludeServerRole Public -IncludeRoleMember -FilePath C:\temp\ServerRoles.sql -Append -BatchSeparator ''

        Exports server roles from sqlserver2008, excludes all roles marked as as FixedRole and Public role. Includes RoleMembers and writes to file C:\temp\ServerRoles.sql, appending to file if it exits. Does not include a BatchSeparator

    .EXAMPLE
        PS C:\> Get-DbaServerRole -SqlInstance sqlserver2012, sqlserver2014  | Export-DbaServerRole

        Exports server roles from sqlserver2012, sqlserver2014 and writes them to the path defined in the ConfigValue 'Path.DbatoolsExport' using a a default name pattern of ServerName-YYYYMMDDhhmmss-serverrole

    .EXAMPLE
        PS C:\> Get-DbaServerRole -SqlInstance sqlserver2016 -ExcludeFixedRole -ExcludeServerRole Public | Export-DbaServerRole -IncludeRoleMember

        Exports server roles from sqlserver2016, excludes all roles marked as as FixedRole and Public role. Includes RoleMembers

    #>
    [CmdletBinding()]
    param (
        [parameter()]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [Microsoft.SqlServer.Management.Smo.ScriptingOptions]$ScriptingOptionsObject,
        [string[]]$ServerRole,
        [string[]]$ExcludeServerRole,
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
        if ($IsLinux -or $IsMacOs) {
            $executingUser = $env:USER
        } else {
            $executingUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        }
        $commandName = $MyInvocation.MyCommand.Name

        $roleSQL = "SELECT
                    CASE sperm.state
                        WHEN 'D' THEN 'DENY'
                        WHEN 'G' THEN 'GRANT'
                        WHEN 'R' THEN 'REVOKE'
                        WHEN 'W' THEN 'GRANT'
                    END AS GrantState,
                    sperm.permission_name AS Permission,
                    CASE
                        WHEN sperm.class = 100 THEN ''
                        WHEN sperm.class = 101 AND sp2.type = 'S' THEN 'ON LOGIN::' + QUOTENAME(sp2.name)
                        WHEN sperm.class = 101 AND sp2.type = 'R' THEN 'ON SERVER ROLE::' + QUOTENAME(sp2.name)
                        WHEN sperm.class = 101 AND sp2.type = 'U' THEN 'ON LOGIN::' + QUOTENAME(sp2.name)
                        WHEN sperm.class = 105 THEN 'ON ENDPOINT::' + QUOTENAME(ep.name)
                        WHEN sperm.class = 108 THEN 'ON AVAILABILITY GROUP::' + QUOTENAME(ag.name)
                        ELSE ''
                    END AS OnClause,
                    QUOTENAME(sp.name) AS RoleName,
                    CASE
                        WHEN sperm.state = 'W' THEN 'WITH GRANT OPTION AS ' + QUOTENAME(gsp.name)
                        ELSE ''
                    END AS GrantOption
                FROM sys.server_permissions sperm
                INNER JOIN sys.server_principals sp
                    ON sp.principal_id = sperm.grantee_principal_id
                INNER JOIN sys.server_principals gsp
                    ON gsp.principal_id = sperm.grantor_principal_id
                LEFT JOIN sys.endpoints ep
                    ON ep.endpoint_id = sperm.major_id
                    AND sperm.class = 105
                LEFT JOIN sys.server_principals sp2
                    ON sp2.principal_id = sperm.major_id
                    AND sperm.class = 101
                LEFT JOIN
                (
                    SELECT
                        ar.replica_metadata_id,
                        ag.name
                    FROM sys.availability_groups ag
                    INNER JOIN sys.availability_replicas ar
                        ON ag.group_id = ar.group_id
                ) ag
                    ON ag.replica_metadata_id = sperm.major_id
                    AND sperm.class = 108
                WHERE sp.type='R'
                AND sp.name=N'/*RoleName*/'"

        if (Test-Bound -Not -ParameterName ScriptingOptionsObject) {
            $ScriptingOptionsObject = New-DbaScriptingOption
            $ScriptingOptionsObject.AllowSystemObjects = $false
            $ScriptingOptionsObject.ContinueScriptingOnError = $false
            $ScriptingOptionsObject.IncludeDatabaseContext = $true
            $ScriptingOptionsObject.IncludeIfNotExists = $true
            $ScriptingOptionsObject.ScriptOwner = $true
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
            Stop-Function -Message "You must pipe in a ServerRole or server or specify a SqlInstance"
            return
        }

        if ($SqlInstance) {
            $InputObject = $SqlInstance
        }

        foreach ($input in $InputObject) {
            $inputType = $input.GetType().FullName
            switch ($inputType) {
                'Dataplat.Dbatools.Parameter.DbaInstanceParameter' {
                    Write-Message -Level Verbose -Message "Processing DbaInstanceParameter through InputObject"
                    $serverRoles = Get-DbaServerRole -SqlInstance $input -SqlCredential $SqlCredential  -ServerRole $ServerRole -ExcludeServerRole $ExcludeServerRole -ExcludeFixedRole:$ExcludeFixedRole
                }
                'Microsoft.SqlServer.Management.Smo.Server' {
                    Write-Message -Level Verbose -Message "Processing Server through InputObject"
                    $serverRoles = Get-DbaServerRole -SqlInstance $input -SqlCredential $SqlCredential -ServerRole $ServerRole -ExcludeServerRole $ExcludeServerRole -ExcludeFixedRole:$ExcludeFixedRole
                }
                'Microsoft.SqlServer.Management.Smo.ServerRole' {
                    Write-Message -Level Verbose -Message "Processing ServerRole through InputObject"
                    $serverRoles = $input
                }
                default {
                    Stop-Function -Message "InputObject is not a server or serverrole."
                    return
                }
            }

            foreach ($role in $serverRoles) {
                $server = $role.Parent

                if ($server.ServerType -eq 'SqlAzureDatabase') {
                    Stop-Function -Message "The SqlAzureDatabase - $server is not supported." -Continue
                }

                try {
                    # Get user defined Server roles
                    if ($server.VersionMajor -ge 11) {
                        $outsql += $role.Script($ScriptingOptionsObject)

                        $query = $roleSQL.Replace('/*RoleName*/', "$($role.Name)")
                        $rolePermissions = $server.Query($query)

                        foreach ($rolePermission in $rolePermissions) {
                            $script = $rolePermission.GrantState + " " + $rolePermission.Permission
                            if ($rolePermission.OnClause) {
                                $script += " " + $rolePermission.OnClause
                            }
                            if ($rolePermission.RoleName) {
                                $script += " TO " + $rolePermission.RoleName
                            }
                            if ($rolePermission.GrantOption) {
                                $script += " " + $rolePermission.GrantOption + $commandTerminator
                            } else {
                                $script += $commandTerminator
                            }
                            $outsql += "$script"
                        }
                    }

                    if ($IncludeRoleMember) {
                        foreach ($roleUser in $role.Login) {
                            $script = 'ALTER SERVER ROLE [' + $role.Role + "] ADD MEMBER [" + $roleUser + "]" + $commandTerminator
                            $outsql += "$script"
                        }
                    }
                    if ($outsql) {
                        $roleObject = [PSCustomObject]@{
                            Name     = $role.Name
                            Instance = $role.SqlInstance
                            Sql      = $outsql
                        }
                    }
                    $roleCollection.Add($roleObject) | Out-Null
                    $outsql = @()
                } catch {
                    $outsql = @()
                    Stop-Function -Message "Error occurred processing role $Role" -Category ConnectionError -ErrorRecord $_ -Target $role.SqlInstance -Continue
                }
            }
        }
    }
    end {
        if (Test-FunctionInterrupt) { return }

        $eol = [System.Environment]::NewLine

        $timeNow = $(Get-Date -Format (Get-DbatoolsConfigValue -FullName 'Formatting.DateTime'))
        foreach ($role in $roleCollection) {
            $instanceName = $role.Instance

            if ($NoPrefix) {
                $prefix = $null
            } else {
                $prefix = "/*$eol`tCreated by $executingUser using dbatools $commandName for objects on $instanceName.$databaseName at $timeNow$eol`tSee https://dbatools.io/$commandName for more information$eol*/"
            }

            if ($BatchSeparator) {
                $sql = $role.SQL -join "$eol$BatchSeparator$eol"
                #add the final GO
                $sql += "$eol$BatchSeparator"
            } else {
                $sql = $role.SQL
            }

            if ($Passthru) {
                if ($null -ne $prefix) {
                    $sql = "$prefix$eol$sql"
                }
                $sql
            } elseif ($Path -Or $FilePath) {
                $outputFileName = $instanceName.Replace('\', '$')
                if ($outputFileArray -notcontains $outputFileName) {
                    Write-Message -Level Verbose -Message "New File $outputFileName "
                    if ($null -ne $prefix) {
                        $sql = "$prefix$eol$sql"
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