function Export-DbaUser {
    <#
    .SYNOPSIS
        Generates T-SQL scripts to recreate database users with their complete security context including roles and permissions

    .DESCRIPTION
        Creates comprehensive T-SQL scripts that fully recreate database users along with their security assignments and permissions. The generated scripts include user creation statements, role memberships, database-level permissions (like CONNECT, SELECT, INSERT), and granular object-level permissions for tables, views, stored procedures, functions, and other database objects.

        This function is essential for migrating users between environments, documenting security configurations for compliance audits, creating deployment scripts for application users, or preparing disaster recovery procedures. Each exported script is self-contained and includes all necessary role creation statements to avoid dependency issues during execution.

        The function examines the complete security context for each user, including custom database roles, explicit permissions granted at the database level, and specific object permissions across all supported SQL Server object types (tables, views, procedures, functions, assemblies, certificates, schemas, and Service Broker objects).

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. SQL Server 2000 and above supported.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to export users from. Accepts wildcards for pattern matching.
        Use this when you need to export users from specific databases instead of all databases on the instance.

    .PARAMETER ExcludeDatabase
        Specifies databases to exclude from user export operations. Accepts wildcards for pattern matching.
        Useful when exporting from most databases but need to skip system databases or specific application databases.

    .PARAMETER User
        Exports only the specified database users by name. Accepts multiple user names.
        Use this when you need to export specific application users or service accounts rather than all database users.

    .PARAMETER DestinationVersion
        Specifies the target SQL Server version for the generated T-SQL script syntax compatibility.
        Use this when migrating users to a different SQL Server version than the source database compatibility level.

    .PARAMETER Encoding
        Sets the character encoding for the output T-SQL script file. Defaults to UTF8.
        Change this when you need to match specific encoding requirements for your deployment tools or source control systems.

    .PARAMETER Path
        Sets the directory path where user script files will be created. Creates individual files per user when FilePath is not specified.
        Use this when organizing exported scripts by directory structure for different environments or applications.

    .PARAMETER FilePath
        Sets the complete file path for a single consolidated script containing all exported users.
        Use this when you need all user definitions in one file for batch deployment or version control.

    .PARAMETER InputObject
        Accepts database objects piped from Get-DbaDatabase for processing specific database collections.
        Use this in pipeline operations when you have pre-filtered database objects to process.

    .PARAMETER NoClobber
        Prevents overwriting existing files during export operations.
        Use this safety feature when running exports to avoid accidentally replacing existing user scripts.

    .PARAMETER Append
        Adds the exported user scripts to the end of an existing file instead of creating a new file.
        Use this when consolidating user exports from multiple instances or databases into a single deployment script.

    .PARAMETER Passthru
        Returns the T-SQL script to the console instead of writing to a file.
        Use this for copying scripts to clipboard, reviewing output before saving, or integrating with other PowerShell operations.

    .PARAMETER Template
        Replaces actual usernames and login names with placeholders {templateUser} and {templateLogin} in the generated script.
        Use this when creating reusable deployment scripts that can be parameterized for different environments or applications.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER ScriptingOptionsObject
        Provides a custom ScriptingOptions object to control detailed T-SQL generation behavior and formatting.
        Use this for advanced scenarios requiring specific scripting options beyond the standard Export-DbaUser parameters.

    .PARAMETER ExcludeGoBatchSeparator
        Removes the 'GO' batch separator statements from the generated T-SQL script.
        Use this when the target deployment tool or application doesn't support batch separators or requires continuous T-SQL.

    .NOTES
        Tags: User, Export
        Author: Claudio Silva (@ClaudioESSilva)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Export-DbaUser

    .OUTPUTS
        System.String (when -Passthru is specified)

        Returns the generated T-SQL script containing CREATE USER statements, role memberships, database permissions, and object-level permissions as raw text.

        System.IO.FileInfo (default)

        Returns file system object(s) for the created T-SQL script file(s). When generating one file per user (using -Path without -FilePath), returns one FileInfo object per user file. When consolidating to a single file (using -FilePath), returns one FileInfo object for that file.

    .EXAMPLE
        PS C:\> Export-DbaUser -SqlInstance sql2005 -FilePath C:\temp\sql2005-users.sql

        Exports SQL for the users in server "sql2005" and writes them to the file "C:\temp\sql2005-users.sql"

    .EXAMPLE
        PS C:\> Export-DbaUser -SqlInstance sqlserver2014a $scred -FilePath C:\temp\users.sql -Append

        Authenticates to sqlserver2014a using SQL Authentication. Exports all users to C:\temp\users.sql, and appends to the file if it exists. If not, the file will be created.

    .EXAMPLE
        PS C:\> Export-DbaUser -SqlInstance sqlserver2014a -User User1, User2 -FilePath C:\temp\users.sql

        Exports ONLY users User1 and User2 from sqlserver2014a to the file C:\temp\users.sql

    .EXAMPLE
        PS C:\> Export-DbaUser -SqlInstance sqlserver2014a -User User1, User2 -Path C:\temp

        Exports ONLY users User1 and User2 from sqlserver2014a to the folder C:\temp. One file per user will be generated

    .EXAMPLE
        PS C:\> Export-DbaUser -SqlInstance sqlserver2008 -User User1 -FilePath C:\temp\users.sql -DestinationVersion SQLServer2016

        Exports user User1 from sqlserver2008 to the file C:\temp\users.sql with syntax to run on SQL Server 2016

    .EXAMPLE
        PS C:\> Export-DbaUser -SqlInstance sqlserver2008 -Database db1,db2 -FilePath C:\temp\users.sql

        Exports ONLY users from db1 and db2 database on sqlserver2008 server, to the C:\temp\users.sql file.

    .EXAMPLE
        PS C:\> $options = New-DbaScriptingOption
        PS C:\> $options.ScriptDrops = $false
        PS C:\> $options.WithDependencies = $true
        PS C:\> Export-DbaUser -SqlInstance sqlserver2008 -Database db1,db2 -FilePath C:\temp\users.sql -ScriptingOptionsObject $options

        Exports ONLY users from db1 and db2 database on sqlserver2008 server, to the C:\temp\users.sql file.
        It will not script drops but will script dependencies.

    .EXAMPLE
        PS C:\> Export-DbaUser -SqlInstance sqlserver2008 -Database db1,db2 -FilePath C:\temp\users.sql -ExcludeGoBatchSeparator

        Exports ONLY users from db1 and db2 database on sqlserver2008 server, to the C:\temp\users.sql file without the 'GO' batch separator.

    .EXAMPLE
        PS C:\> Export-DbaUser -SqlInstance sqlserver2008 -Database db1 -User user1 -Template -PassThru

        Exports user1 from database db1, replacing loginname and username with {templateLogin} and {templateUser} correspondingly.


    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    [OutputType([String], [System.IO.FileInfo])]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [string[]]$User,
        [ValidateSet('SQLServer2000', 'SQLServer2005', 'SQLServer2008/2008R2', 'SQLServer2012', 'SQLServer2014', 'SQLServer2016', 'SQLServer2017', 'SQLServer2019', 'SQLServer2022')]
        [string]$DestinationVersion,
        [string]$Path = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport'),
        [Alias("OutFile", "FileName")]
        [string]$FilePath,
        [ValidateSet('ASCII', 'BigEndianUnicode', 'Byte', 'String', 'Unicode', 'UTF7', 'UTF8', 'Unknown')]
        [string]$Encoding = 'UTF8',
        [Alias("NoOverwrite")]
        [switch]$NoClobber,
        [switch]$Append,
        [switch]$Passthru,
        [switch]$Template,
        [switch]$EnableException,
        [Microsoft.SqlServer.Management.Smo.ScriptingOptions]$ScriptingOptionsObject = $null,
        [switch]$ExcludeGoBatchSeparator
    )

    begin {
        $null = Test-ExportDirectory -Path $Path

        $outsql = $script:pathcollection = $instanceArray = @()
        $GenerateFilePerUser = $false

        $versions = @{
            'SQLServer2000'        = 'Version80'
            'SQLServer2005'        = 'Version90'
            'SQLServer2008/2008R2' = 'Version100'
            'SQLServer2012'        = 'Version110'
            'SQLServer2014'        = 'Version120'
            'SQLServer2016'        = 'Version130'
            'SQLServer2017'        = 'Version140'
            'SQLServer2019'        = 'Version150'
            'SQLServer2022'        = 'Version160'
        }

        $versionName = @{
            'Version80'  = 'SQLServer2000'
            'Version90'  = 'SQLServer2005'
            'Version100' = 'SQLServer2008/2008R2'
            'Version110' = 'SQLServer2012'
            'Version120' = 'SQLServer2014'
            'Version130' = 'SQLServer2016'
            'Version140' = 'SQLServer2017'
            'Version150' = 'SQLServer2019'
            'Version160' = 'SQLServer2022'
        }

        $eol = [System.Environment]::NewLine

    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        # To keep the filenames generated and re-use (append) if needed
        $usersProcessed = @{ }

        foreach ($db in $InputObject) {

            if ([string]::IsNullOrEmpty($destinationVersion)) {
                #Get compatibility level for scripting the objects
                $scriptVersion = $db.CompatibilityLevel
            } else {
                $scriptVersion = $versions[$destinationVersion]
            }
            $versionNameDesc = $versionName[$scriptVersion.ToString()]

            #If not passed create new ScriptingOption. Otherwise use the one that was passed
            if ($null -eq $ScriptingOptionsObject) {
                $ScriptingOptionsObject = New-DbaScriptingOption
                $ScriptingOptionsObject.TargetServerVersion = [Microsoft.SqlServer.Management.Smo.SqlServerVersion]::$scriptVersion
                $ScriptingOptionsObject.AllowSystemObjects = $false
                $ScriptingOptionsObject.IncludeDatabaseRoleMemberships = $true
                $ScriptingOptionsObject.ContinueScriptingOnError = $false
                $ScriptingOptionsObject.IncludeDatabaseContext = $false
                $ScriptingOptionsObject.IncludeIfNotExists = $true
            }

            Write-Message -Level Verbose -Message "Validating users on database $db"

            if ($User) {
                $users = $db.Users | Where-Object { $User -contains $_.Name -and $_.IsSystemObject -eq $false -and $_.Name -notlike "##*" }
            } else {
                $users = $db.Users
            }

            # Generate the file path
            if (Test-Bound -ParameterName FilePath -Not) {
                $GenerateFilePerUser = $true
            } else {
                # Generate a new file name with passed/default path
                $FilePath = Get-ExportFilePath -Path $PSBoundParameters.Path -FilePath $PSBoundParameters.FilePath -Type sql -ServerName $db.Parent.Name -Unique
            }

            $stepCounter = 0
            foreach ($dbuser in $users) {
                # Clear output for each user
                $outsql = @()
                $sql = ""

                if ($GenerateFilePerUser) {
                    if ($null -eq $usersProcessed[$dbuser.Name]) {
                        # If user and not specific output file, create file name without database name.
                        $FilePath = Get-ExportFilePath -Path $PSBoundParameters.Path -FilePath $PSBoundParameters.FilePath -Type sql -ServerName $("$($db.Parent.Name)-$($dbuser.Name)") -Unique
                        $usersProcessed[$dbuser.Name] = $FilePath
                    } else {
                        $Append = $true
                        $FilePath = $usersProcessed[$dbuser.Name]
                    }
                }

                if ($Passthru) {
                    $progressMessage = "Generating script for user $dbuser"
                } else {
                    $progressMessage = "Generating script ($FilePath) for user $dbuser"
                }
                Write-ProgressHelper -TotalSteps $users.Count -Activity "Exporting from $($db.Name)" -StepNumber ($stepCounter++) -Message $progressMessage

                #setting database
                if (((Test-Bound ScriptingOptionsObject) -and $ScriptingOptionsObject.IncludeDatabaseContext) -or - (Test-Bound ScriptingOptionsObject -Not)) {
                    $useDatabase = "USE [" + $db.Name + "]"
                }

                try {
                    <#
                    In this approach, we do not maintain a variable to track the roles that have been scripted. Our method involves a
                    consistent verification process for each user against the complete list of roles. This ensures that we dynamically
                    include only the roles to which a user belongs. For example, consider two users: user1 is associated with role1 and
                    role2, while user2 is associated with role1 and role3.

                    Attempting to memorize the scripted roles could result in Transact-SQL (T-SQL) statements such as:

                    IF NOT EXISTS (role1)
                      CREATE ROLE role1
                    IF NOT EXISTS (role2)
                      CREATE ROLE role2
                    IF NOT EXISTS (user1)
                      CREATE USER user1
                    ADD user1 TO role1
                    ADD user1 TO role2

                    -- And for another user:

                    IF NOT EXISTS (role3)
                      CREATE ROLE role3
                    IF NOT EXISTS (user2)
                      CREATE USER user2
                    ADD user2 TO role1
                    ADD user2 TO role3

                    However, this script inadvertently introduces a dependency issue. To ensure user2 is properly configured, the script
                    segment for user1 must be executed first due to the shared role1. To circumvent this issue and remove interdependencies,
                    we opt to match each user against all potential roles. Consequently, roles are scripted per user membership, resulting
                    in T-SQL like:

                    IF NOT EXISTS (role1)
                      CREATE ROLE role1
                    IF NOT EXISTS (role2)
                      CREATE ROLE role2
                    IF NOT EXISTS (user1)
                      CREATE USER user1
                    ADD user1 TO role1
                    ADD user1 TO role2

                    -- And for another user:

                    IF NOT EXISTS (role1)
                      CREATE ROLE role1
                    IF NOT EXISTS (role3)
                      CREATE ROLE role3
                    IF NOT EXISTS (user2)
                      CREATE USER user2
                    ADD user2 TO role1
                    ADD user2 TO role3

                    While this method may produce some redundant code (e.g., checking and creating role1 twice), it guarantees that each
                    portion of the script is self-sufficient and can be executed independently of others. Therefore, users can selectively
                    execute any segment of the script without concern for execution order or dependencies.
                    #>
                    #Fixed Roles #Dependency Issue. Create Role, before add to role.
                    foreach ($role in ($db.Roles | Where-Object { $_.IsFixedRole -eq $false })) {
                        # Check if the user is a member of the role
                        $isUserMember = $role.EnumMembers() | Where-Object { $_ -eq $dbuser.Name }
                        if ($isUserMember) {
                            foreach ($rolePermissionScript in $role.Script($ScriptingOptionsObject)) {
                                $outsql += "$($rolePermissionScript.ToString())"
                            }
                        }
                    }

                    #Database Create User(s) and add to Role(s)
                    foreach ($dbUserPermissionScript in $dbuser.Script($ScriptingOptionsObject)) {
                        if ($dbuserPermissionScript.Contains("sp_addrolemember")) {
                            $execute = "EXEC "
                        } else {
                            $execute = ""
                        }
                        $permissionScript = $dbUserPermissionScript.ToString()
                        if ($Template) {
                            $escapedUsername = [regex]::Escape($dbuser.Name)
                            $permissionScript = $permissionScript -replace "\`[$escapedUsername\`]", '[{templateUser}]'
                            $permissionScript = $permissionScript -replace "'$escapedUsername'", "'{templateUser}'"
                            if ($dbuser.Login) {
                                $escapedLogin = [regex]::Escape($dbuser.Login)
                                $permissionScript = $permissionScript -replace "\`[$escapedLogin\`]", '[{templateLogin}]'
                                $permissionScript = $permissionScript -replace "'$escapedLogin'", "'{templateLogin}'"
                            }

                        }
                        $outsql += "$execute$($permissionScript)"
                    }

                    #Database Permissions
                    foreach ($databasePermission in $db.EnumDatabasePermissions() | Where-Object { @("sa", "dbo", "information_schema", "sys") -notcontains $_.Grantee -and $_.Grantee -notlike "##*" -and ($dbuser.Name -contains $_.Grantee) }) {
                        if ($databasePermission.PermissionState -eq "GrantWithGrant") {
                            $withGrant = " WITH GRANT OPTION"
                            $grantDatabasePermission = 'GRANT'
                        } else {
                            $withGrant = ""
                            $grantDatabasePermission = $databasePermission.PermissionState.ToString().ToUpper()
                        }
                        if ($Template) {
                            $grantee = "{templateUser}"
                        } else {
                            $grantee = $databasePermission.Grantee
                        }

                        $outsql += "$($grantDatabasePermission) $($databasePermission.PermissionType) TO [$grantee]$withGrant AS [$($databasePermission.Grantor)];"
                    }

                    #Database Object Permissions
                    # NB: This is a bit of a mess for a couple of reasons
                    # 1. $db.EnumObjectPermissions() doesn't enumerate all object types
                    # 2. Some (x)Collection types can have EnumObjectPermissions() called
                    #    on them directly (e.g. AssemblyCollection); others can't (e.g.
                    #    ApplicationRoleCollection). Those that can't we iterate the
                    #    collection explicitly and add each object's permission.

                    $perms = New-Object System.Collections.ArrayList

                    $null = $perms.AddRange($db.EnumObjectPermissions($dbuser.Name))

                    foreach ($item in $db.ApplicationRoles) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.Assemblies) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.Certificates) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.DatabaseRoles) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.FullTextCatalogs) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.FullTextStopLists) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.SearchPropertyLists) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.ServiceBroker.MessageTypes) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.RemoteServiceBindings) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.ServiceBroker.Routes) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.ServiceBroker.ServiceContracts) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.ServiceBroker.Services) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    if ($scriptVersion -ne "Version80") {
                        foreach ($item in $db.AsymmetricKeys) {
                            $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                        }
                    }

                    foreach ($item in $db.SymmetricKeys) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.XmlSchemaCollections) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($objectPermission in $perms | Where-Object { @("sa", "dbo", "information_schema", "sys") -notcontains $_.Grantee -and $_.Grantee -notlike "##*" -and $_.Grantee -eq $dbuser.Name }) {
                        switch ($objectPermission.ObjectClass) {
                            'ApplicationRole' {
                                $object = 'APPLICATION ROLE::[{0}]' -f $objectPermission.ObjectName
                            }
                            'AsymmetricKey' {
                                $object = 'ASYMMETRIC KEY::[{0}]' -f $objectPermission.ObjectName
                            }
                            'Certificate' {
                                $object = 'CERTIFICATE::[{0}]' -f $objectPermission.ObjectName
                            }
                            'DatabaseRole' {
                                $object = 'ROLE::[{0}]' -f $objectPermission.ObjectName
                            }
                            'FullTextCatalog' {
                                $object = 'FULLTEXT CATALOG::[{0}]' -f $objectPermission.ObjectName
                            }
                            'FullTextStopList' {
                                $object = 'FULLTEXT STOPLIST::[{0}]' -f $objectPermission.ObjectName
                            }
                            'MessageType' {
                                $object = 'Message Type::[{0}]' -f $objectPermission.ObjectName
                            }
                            'ObjectOrColumn' {
                                if ($scriptVersion -ne "Version80") {
                                    $object = 'OBJECT::[{0}].[{1}]' -f $objectPermission.ObjectSchema, $objectPermission.ObjectName
                                    if ($null -ne $objectPermission.ColumnName) {
                                        $object += '([{0}])' -f $objectPermission.ColumnName
                                    }
                                }
                                #At SQL Server 2000 OBJECT did not exists
                                else {
                                    $object = '[{0}].[{1}]' -f $objectPermission.ObjectSchema, $objectPermission.ObjectName
                                }
                            }
                            'RemoteServiceBinding' {
                                $object = 'REMOTE SERVICE BINDING::[{0}]' -f $objectPermission.ObjectName
                            }
                            'Schema' {
                                $object = 'SCHEMA::[{0}]' -f $objectPermission.ObjectName
                            }
                            'SearchPropertyList' {
                                $object = 'SEARCH PROPERTY LIST::[{0}]' -f $objectPermission.ObjectName
                            }
                            'Service' {
                                $object = 'SERVICE::[{0}]' -f $objectPermission.ObjectName
                            }
                            'ServiceContract' {
                                $object = 'CONTRACT::[{0}]' -f $objectPermission.ObjectName
                            }
                            'ServiceRoute' {
                                $object = 'ROUTE::[{0}]' -f $objectPermission.ObjectName
                            }
                            'SqlAssembly' {
                                $object = 'ASSEMBLY::[{0}]' -f $objectPermission.ObjectName
                            }
                            'SymmetricKey' {
                                $object = 'SYMMETRIC KEY::[{0}]' -f $objectPermission.ObjectName
                            }
                            'User' {
                                $object = 'USER::[{0}]' -f $objectPermission.ObjectName
                            }
                            'UserDefinedType' {
                                $object = 'TYPE::[{0}].[{1}]' -f $objectPermission.ObjectSchema, $objectPermission.ObjectName
                            }
                            'XmlNamespace' {
                                $object = 'XML SCHEMA COLLECTION::[{0}]' -f $objectPermission.ObjectName
                            }
                        }

                        if ($objectPermission.PermissionState -eq "GrantWithGrant") {
                            $withGrant = " WITH GRANT OPTION"
                            $grantObjectPermission = 'GRANT'
                        } else {
                            $withGrant = ""
                            $grantObjectPermission = $objectPermission.PermissionState.ToString().ToUpper()
                        }
                        if ($Template) {
                            $grantee = "{templateUser}"
                        } else {
                            $grantee = $objectPermission.Grantee
                        }

                        $outsql += "$grantObjectPermission $($objectPermission.PermissionType) ON $object TO [$grantee]$withGrant AS [$($objectPermission.Grantor)];"
                    }

                } catch {
                    Stop-Function -Message "This user may be using functionality from $($versionName[$db.CompatibilityLevel.ToString()]) that does not exist on the destination version ($versionNameDesc)." -Continue -InnerErrorRecord $_ -Target $db
                }

                if (@($outsql.Count) -gt 0) {
                    if ($ExcludeGoBatchSeparator) {
                        $sql = "$useDatabase $outsql"
                    } else {
                        if ($useDatabase) {
                            $sql = "$useDatabase$($eol)GO$eol" + ($outsql -join "$($eol)GO$eol")
                        } else {
                            $sql = $outsql -join "$($eol)GO$eol"
                        }
                        #add the final GO
                        $sql += "$($eol)GO"
                    }
                }

                if (-not $Passthru) {
                    # If generate a file per user, clean the collection to populate with next one
                    if ($GenerateFilePerUser) {
                        if (-not [string]::IsNullOrEmpty($sql)) {
                            $sql | Out-File -Encoding:$Encoding -FilePath $FilePath -Append:$Append -NoClobber:$NoClobber
                            Get-ChildItem -Path $FilePath
                        }
                    } else {
                        $dbUserInstance = $dbuser.Parent.Parent.Name

                        if ($instanceArray -notcontains $($dbUserInstance)) {
                            $sql | Out-File -Encoding:$Encoding -FilePath $FilePath -Append:$Append -NoClobber:$NoClobber
                            $instanceArray += $dbUserInstance
                        } else {
                            $sql | Out-File -Encoding:$Encoding -FilePath $FilePath -Append
                        }
                    }
                } else {
                    $sql
                }
            }
        }
        # Just a single file, output path once here
        if (-Not $GenerateFilePerUser -and $FilePath) {
            Get-ChildItem -Path $FilePath
        }
    }
}