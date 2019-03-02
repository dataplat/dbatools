function Connect-SqlInstance {
    <#
    .SYNOPSIS
        Internal function to establish smo connections.

    .DESCRIPTION
        Internal function to establish smo connections.

        Can interpret any of the following types of information:
        - String
        - Smo Server objects
        - Smo Linked Server objects

        Related Docs, Pull Requests and Issues:

    Connect commands and alt Windows Credential fix
    https://github.com/sqlcollaborative/dbatools/pull/3835

    Connect-*Instance, fix errors with Windows logins
    https://github.com/sqlcollaborative/dbatools/pull/4426

    Invoke-DbaSqlQuery fails to use proper Windows credentials
    https://github.com/sqlcollaborative/dbatools/issues/3780

    Fixed auth issue
    https://github.com/sqlcollaborative/dbatools/pull/3809

    Connecting to an Instance of SQL Server
    https://docs.microsoft.com/en-us/sql/relational-databases/server-management-objects-smo/create-program/connecting-to-an-instance-of-sql-server

    SQL Server Connection Pooling (ADO.NET)
    https://docs.microsoft.com/en-us/dotnet/framework/data/adonet/sql-server-connection-pooling

    .PARAMETER SqlInstance
        The SQL Server instance to restore to.

    .PARAMETER SqlCredential
        Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted.

    .PARAMETER ParameterConnection
        This call is for dynamic parameters only and is no longer used, actually.

    .PARAMETER AzureUnsupported
        Throw if Azure is detected but not supported

    .PARAMETER RegularUser
        The connection doesn't require SA privileges.
        By default, the assumption is that SA is no longer required.

    .PARAMETER MinimumVersion
       The minimum version that the calling command will support

    .PARAMETER StatementTimeout
        Sets the number of seconds a statement is given to run before failing with a timeout error.

    .EXAMPLE
        Connect-SqlInstance -SqlInstance sql2014

        Connect to the Server sql2014 with native credentials.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidDefaultValueSwitchParameter", "")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingEmptyCatchBlock", "")]
    param (
        [Parameter(Mandatory)]
        [object]$SqlInstance,
        [object]$SqlCredential,
        [switch]$ParameterConnection,
        [switch]$RegularUser = $true,
        [int]$StatementTimeout,
        [int]$MinimumVersion,
        [switch]$AzureUnsupported,
        [switch]$NonPooled
    )

    #region Utility functions
    function Invoke-TEPPCacheUpdate {
        [CmdletBinding()]
        param (
            [System.Management.Automation.ScriptBlock]$ScriptBlock
        )

        try {
            [ScriptBlock]::Create($scriptBlock).Invoke()
        } catch {
            # If the SQL Server version doesn't support the feature, we ignore it and silently continue
            if ($_.Exception.InnerException.InnerException.GetType().FullName -eq "Microsoft.SqlServer.Management.Sdk.Sfc.InvalidVersionEnumeratorException") {
                return
            }

            if ($ENV:APPVEYOR_BUILD_FOLDER -or ([Sqlcollaborative.Dbatools.Message.MEssageHost]::DeveloperMode)) { throw }
            else {
                Write-Message -Level Warning -Message "Failed TEPP Caching: $($scriptBlock.ToString() | Select-String '"(.*?)"' | ForEach-Object { $_.Matches[0].Groups[1].Value })" -ErrorRecord $_ 3>$null
            }
        }
    }
    #endregion Utility functions

    #region Ensure Credential integrity
    <#
    Usually, the parameter type should have been not object but off the PSCredential type.
    When binding null to a PSCredential type parameter on PS3-4, it'd then show a prompt, asking for username and password.

    In order to avoid that and having to refactor lots of functions (and to avoid making regular scripts harder to read), we created this workaround.
    #>
    if ($SqlCredential) {
        if ($SqlCredential.GetType() -ne [System.Management.Automation.PSCredential]) {
            throw "The credential parameter was of a non-supported type. Only specify PSCredentials such as generated from Get-Credential. Input was of type $($SqlCredential.GetType().FullName)"
        }
    }
    #endregion Ensure Credential integrity

    #region Safely convert input into instance parameters
    <#
    This is a bit ugly, but:
    In some cases functions would directly pass their own input through when the parameter on the calling function was typed as [object[]].
    This would break the base parameter class, as it'd automatically be an array and the parameterclass is not designed to handle arrays (Shouldn't have to).

    Note: Multiple servers in one call were never supported, those old functions were liable to break anyway and should be fixed soonest.
    #>
    if ($SqlInstance.GetType() -eq [Sqlcollaborative.Dbatools.Parameter.DbaInstanceParameter]) {
        [DbaInstanceParameter]$ConvertedSqlInstance = $SqlInstance
        if ($ConvertedSqlInstance.Type -like "SqlConnection") {
            [DbaInstanceParameter]$ConvertedSqlInstance = New-Object Microsoft.SqlServer.Management.Smo.Server($ConvertedSqlInstance.InputObject)
        }
    } else {
        [DbaInstanceParameter]$ConvertedSqlInstance = [DbaInstanceParameter]($SqlInstance | Select-Object -First 1)

        if ($SqlInstance.Count -gt 1) {
            Write-Message -Level Warning -EnableException $true -Message "More than on server was specified when calling Connect-SqlInstance from $((Get-PSCallStack)[1].Command)"
        }
    }
    #endregion Safely convert input into instance parameters

    #region Input Object was a server object
    if ($ConvertedSqlInstance.InputObject.GetType() -eq [Microsoft.SqlServer.Management.Smo.Server]) {
        $server = $ConvertedSqlInstance.InputObject
        $authtypeSMO = $SqlCredential.UserName -like '*\*'
        if ($server.ConnectionContext.IsOpen -eq $false) {
            if ($NonPooled) {
                # When the Connect method is called, the connection is not automatically released.
                # The Disconnect method must be called explicitly to release the connection to the connection pool.
                # https://docs.microsoft.com/en-us/sql/relational-databases/server-management-objects-smo/create-program/disconnecting-from-an-instance-of-sql-server
                $server.ConnectionContext.Connect()
            } elseif ($authtypeSMO -eq "Windows Authentication with Credential") {
                # Make it connect in a natural way, hard to explain.
                # See https://docs.microsoft.com/en-us/sql/relational-databases/server-management-objects-smo/create-program/connecting-to-an-instance-of-sql-server
                $null = $server.Information.Version

                # Sometimes, however, the above may not connect as promised. Force it.
                # See https://github.com/sqlcollaborative/dbatools/pull/4426
                if ($server.ConnectionContext.IsOpen -eq $false) {
                    $server.ConnectionContext.Connect()
                }
            } else {
                # SqlConnectionObject.Open() enables connection pooling does not support
                # alternative Windows Credentials and passes default credentials
                # See https://github.com/sqlcollaborative/dbatools/pull/3809
                $server.ConnectionContext.SqlConnectionObject.Open()
            }
        }

        # Register the connected instance, so that the TEPP updater knows it's been connected to and starts building the cache
        [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::SetInstance($ConvertedSqlInstance.FullSmoName.ToLower(), $server.ConnectionContext.Copy(), ($server.ConnectionContext.FixedServerRoles -match "SysAdmin"))

        # Update cache for instance names
        if ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] -notcontains $ConvertedSqlInstance.FullSmoName.ToLower()) {
            [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] += $ConvertedSqlInstance.FullSmoName.ToLower()
        }

        # Update lots of registered stuff
        if (-not [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppSyncDisabled) {
            $FullSmoName = $ConvertedSqlInstance.FullSmoName.ToLower()
            foreach ($scriptBlock in ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppGatherScriptsFast)) {
                Invoke-TEPPCacheUpdate -ScriptBlock $scriptBlock
            }
        }

        # Make ComputerName easily available in the server object
        if (-not $server.ComputerName) {
            if (-not $server.NetName -or $SqlInstance -match '\.') {
                $parsedcomputername = $ConvertedSqlInstance.ComputerName
            } else {
                $parsedcomputername = $server.NetName
            }
            Add-Member -InputObject $server -NotePropertyName ComputerName -NotePropertyValue $parsedcomputername -Force
        }
        return $server
    }
    #endregion Input Object was a server object

    #region Input Object was anything else

    $server = New-Object Microsoft.SqlServer.Management.Smo.Server $ConvertedSqlInstance.FullSmoName
    $server.ConnectionContext.ApplicationName = "dbatools PowerShell module - dbatools.io"
    if ($ConvertedSqlInstance.IsConnectionString) { $server.ConnectionContext.ConnectionString = $ConvertedSqlInstance.InputObject }

    try {
        if (Test-Bound -ParameterName 'StatementTimeout') {
            $server.ConnectionContext.StatementTimeout = $StatementTimeout
        }
        $server.ConnectionContext.ConnectTimeout = [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout

        if ($null -ne $SqlCredential.UserName) {
            $username = ($SqlCredential.UserName).TrimStart("\")

            # support both ad\username and username@ad
            if ($username -like "*\*" -or $username -like "*@*") {
                if ($username -like "*\*") {
                    $domain, $login = $username.Split("\")
                    $authtype = "Windows Authentication with Credential"
                    if ($domain) {
                        $formatteduser = "$login@$domain"
                    } else {
                        $formatteduser = $username.Split("\")[1]
                    }
                } else {
                    $formatteduser = $SqlCredential.UserName
                }

                $server.ConnectionContext.LoginSecure = $true
                $server.ConnectionContext.ConnectAsUser = $true
                $server.ConnectionContext.ConnectAsUserName = $formatteduser
                $server.ConnectionContext.ConnectAsUserPassword = ($SqlCredential).GetNetworkCredential().Password
            } else {
                $authtype = "SQL Authentication"
                $server.ConnectionContext.LoginSecure = $false
                $server.ConnectionContext.set_Login($username)
                $server.ConnectionContext.set_SecurePassword($SqlCredential.Password)
            }
        }
    } catch { }

    try {
        if ($NonPooled) {
            # When the Connect method is called, the connection is not automatically released.
            # The Disconnect method must be called explicitly to release the connection to the connection pool.
            # https://docs.microsoft.com/en-us/sql/relational-databases/server-management-objects-smo/create-program/disconnecting-from-an-instance-of-sql-server
            $server.ConnectionContext.Connect()
        } elseif ($authtype -eq "Windows Authentication with Credential") {
            # Make it connect in a natural way, hard to explain.
            # See https://docs.microsoft.com/en-us/sql/relational-databases/server-management-objects-smo/create-program/connecting-to-an-instance-of-sql-server
            $null = $server.Information.Version

            # Sometimes, however, the above may not connect as promised. Force it.
            # See https://github.com/sqlcollaborative/dbatools/pull/4426
            if ($server.ConnectionContext.IsOpen -eq $false) {
                $server.ConnectionContext.Connect()
            }
        } else {
            # SqlConnectionObject.Open() enables connection pooling does not support
            # alternative Windows Credentials and passes default credentials
            # See https://github.com/sqlcollaborative/dbatools/pull/3809
            $server.ConnectionContext.SqlConnectionObject.Open()
        }
    } catch {
        $message = $_.Exception.InnerException.InnerException
        if ($message) {
            # This is messy but it works to provide users with straightforward & detailed errors
            $message = $message.ToString()
            $message = ($message -Split '-->')[0]
            $message = ($message -Split 'at System.Data.SqlClient')[0]
            $message = ($message -Split 'at System.Data.ProviderBase')[0]

            if ($message -match "network path was not found") {
                $message = "Can't connect to $sqlinstance`: System.Data.SqlClient.SqlException (0x80131904): A network-related or instance-specific error occurred while establishing a connection to SQL Server. The server was not found or was not accessible. Verify that the instance name is correct and that SQL Server is configured to allow remote connections."
            }

            throw "Can't connect to $ConvertedSqlInstance`: $message "
        } else {
            throw $_
        }
    }

    if ($MinimumVersion -and $server.VersionMajor) {
        if ($server.versionMajor -lt $MinimumVersion) {
            throw "SQL Server version $MinimumVersion required - $server not supported."
        }
    }

    if ($AzureUnsupported -and $server.DatabaseEngineType -eq "SqlAzureDatabase") {
        throw "Azure SQL Database not supported"
    }

    if (-not $RegularUser) {
        if ($server.ConnectionContext.FixedServerRoles -notmatch "SysAdmin") {
            throw "Not a sysadmin on $ConvertedSqlInstance. Quitting."
        }
    }
    #'PrimaryFilePath' seems the culprit for slow SMO on databases
    $Fields2000_Db = 'Collation', 'CompatibilityLevel', 'CreateDate', 'ID', 'IsAccessible', 'IsFullTextEnabled', 'IsSystemObject', 'IsUpdateable', 'LastBackupDate', 'LastDifferentialBackupDate', 'LastLogBackupDate', 'Name', 'Owner', 'ReadOnly', 'RecoveryModel', 'ReplicationOptions', 'Status', 'Version'
    $Fields200x_Db = $Fields2000_Db + @('BrokerEnabled', 'DatabaseSnapshotBaseName', 'IsMirroringEnabled', 'Trustworthy')
    $Fields201x_Db = $Fields200x_Db + @('ActiveConnections', 'AvailabilityDatabaseSynchronizationState', 'AvailabilityGroupName', 'ContainmentType', 'EncryptionEnabled')

    $Fields2000_Login = 'CreateDate', 'DateLastModified', 'DefaultDatabase', 'DenyWindowsLogin', 'IsSystemObject', 'Language', 'LanguageAlias', 'LoginType', 'Name', 'Sid', 'WindowsLoginAccessType'
    $Fields200x_Login = $Fields2000_Login + @('AsymmetricKey', 'Certificate', 'Credential', 'ID', 'IsDisabled', 'IsLocked', 'IsPasswordExpired', 'MustChangePassword', 'PasswordExpirationEnabled', 'PasswordPolicyEnforced')
    $Fields201x_Login = $Fields200x_Login + @('PasswordHashAlgorithm')

    try {
        if ($Server.ServerType -ne 'SqlAzureDatabase') {
            $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Trigger], 'IsSystemObject')
            $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Schema], 'IsSystemObject')
            $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.SqlAssembly], 'IsSystemObject')
            $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Table], 'IsSystemObject')
            $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.View], 'IsSystemObject')
            $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.StoredProcedure], 'IsSystemObject')
            $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.UserDefinedFunction], 'IsSystemObject')

            if ($server.VersionMajor -eq 8) {
                # 2000
                $initFieldsDb = New-Object System.Collections.Specialized.StringCollection
                [void]$initFieldsDb.AddRange($Fields2000_Db)
                $initFieldsLogin = New-Object System.Collections.Specialized.StringCollection
                [void]$initFieldsLogin.AddRange($Fields2000_Login)
                $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Database], $initFieldsDb)
                $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Login], $initFieldsLogin)
            } elseif ($server.VersionMajor -eq 9 -or $server.VersionMajor -eq 10) {
                # 2005 and 2008
                $initFieldsDb = New-Object System.Collections.Specialized.StringCollection
                [void]$initFieldsDb.AddRange($Fields200x_Db)
                $initFieldsLogin = New-Object System.Collections.Specialized.StringCollection
                [void]$initFieldsLogin.AddRange($Fields200x_Login)
                $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Database], $initFieldsDb)
                $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Login], $initFieldsLogin)
            } else {
                # 2012 and above
                $initFieldsDb = New-Object System.Collections.Specialized.StringCollection
                [void]$initFieldsDb.AddRange($Fields201x_Db)
                $initFieldsLogin = New-Object System.Collections.Specialized.StringCollection
                [void]$initFieldsLogin.AddRange($Fields201x_Login)
                $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Database], $initFieldsDb)
                $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Login], $initFieldsLogin)
            }
        }
    } catch {
        # perhaps a DLL issue, continue going
    }

    # Register the connected instance, so that the TEPP updater knows it's been connected to and starts building the cache
    [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::SetInstance($ConvertedSqlInstance.FullSmoName.ToLower(), $server.ConnectionContext.Copy(), ($server.ConnectionContext.FixedServerRoles -match "SysAdmin"))

    # Update cache for instance names
    if ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] -notcontains $ConvertedSqlInstance.FullSmoName.ToLower()) {
        [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] += $ConvertedSqlInstance.FullSmoName.ToLower()
    }

    # Update lots of registered stuff
    if (-not [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppSyncDisabled) {
        $FullSmoName = $ConvertedSqlInstance.FullSmoName.ToLower()
        foreach ($scriptBlock in ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppGatherScriptsFast)) {
            Invoke-TEPPCacheUpdate -ScriptBlock $scriptBlock
        }
    }

    if (-not $server.ComputerName) {
        if (-not $server.NetName -or $SqlInstance -match '\.') {
            $parsedcomputername = $ConvertedSqlInstance.ComputerName
        } else {
            $parsedcomputername = $server.NetName
        }
        Add-Member -InputObject $server -NotePropertyName ComputerName -NotePropertyValue $parsedcomputername -Force
    }
    return $server
    #endregion Input Object was anything else
}