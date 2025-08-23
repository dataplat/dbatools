function New-DbaConnectionStringBuilder {
    <#
    .SYNOPSIS
        Creates a SqlConnectionStringBuilder object for constructing properly formatted SQL Server connection strings

    .DESCRIPTION
        Creates a Microsoft.Data.SqlClient.SqlConnectionStringBuilder object from either an existing connection string or individual connection parameters. This allows you to programmatically build, modify, or validate connection strings without manually concatenating string values. The function handles authentication methods, encryption settings, connection pooling, and other SQL Server connection options, making it useful for scripts that need to connect to different SQL Server instances with varying configurations.

    .PARAMETER ConnectionString
        Specifies an existing SQL Server connection string to use as the foundation for the builder object. The function will parse this string and populate the builder with its values.
        Use this when you need to modify or validate an existing connection string rather than building one from scratch.

    .PARAMETER ApplicationName
        Sets the application name that identifies your script or application to SQL Server in monitoring tools and logs. Defaults to "dbatools Powershell Module".
        Useful for tracking connection sources in SQL Server's sys.dm_exec_sessions and activity monitor when troubleshooting performance or connection issues.

    .PARAMETER DataSource
        Specifies the SQL Server instance name for the connection string. Can include server name, instance name, and port (e.g., "ServerName\InstanceName,1433").
        Use this to set or override the server target when building connection strings for different environments or instances.

    .PARAMETER SqlCredential
        Credential object used to connect to the SQL Server Instance as a different user. This can be a Windows or SQL Server account. Windows users are determined by the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it contains a backslash.

    .PARAMETER InitialCatalog
        Sets the default database context for the connection. When specified, queries will execute in this database unless explicitly changed.
        Use this when your script needs to work with a specific database rather than connecting to the server's default database.

    .PARAMETER IntegratedSecurity
        Enables Windows Authentication for the connection, using the current user's Windows credentials to authenticate to SQL Server.
        Use this when connecting to SQL Server instances configured for Windows Authentication mode or mixed mode with your current Windows account.

    .PARAMETER UserName
        Specifies the SQL Server login name for SQL Server Authentication. Cannot be used with SqlCredential parameter.
        Consider using SqlCredential parameter instead for better security as it avoids exposing credentials in plain text.

    .PARAMETER Password
        Specifies the password for SQL Server Authentication when using the UserName parameter. Cannot be used with SqlCredential parameter.
        Consider using SqlCredential parameter instead for better security as it avoids exposing passwords in plain text or command history.

    .PARAMETER MultipleActiveResultSets
        Enables Multiple Active Result Sets (MARS) allowing multiple commands to be executed concurrently on a single connection.
        Use this when your script needs to execute overlapping commands or maintain multiple data readers on the same connection simultaneously.

    .PARAMETER ColumnEncryptionSetting
        Enables Always Encrypted functionality for the connection, allowing access to encrypted columns in SQL Server databases.
        Use this when connecting to databases with Always Encrypted columns that your application needs to decrypt and work with.

    .PARAMETER WorkstationID
        Sets the workstation identifier that appears in SQL Server logs and monitoring tools to identify the source computer. Defaults to the current computer name.
        Useful for tracking connections by source machine in sys.dm_exec_sessions or when troubleshooting connection issues in multi-server environments.

    .PARAMETER NonPooledConnection
        Disables connection pooling, creating a dedicated connection that bypasses the connection pool. By default, connections are pooled for better performance.
        Use this for diagnostic scenarios or when you need to ensure complete connection isolation, though it may impact performance.

    .PARAMETER Legacy
        Creates the connection string builder using the older System.Data.SqlClient library instead of the newer Microsoft.Data.SqlClient library.
        Use this only when working with legacy applications or frameworks that specifically require the older SQL Client library for compatibility.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: SqlBuild, ConnectionString, Connection
        Author: zippy1981 | Chrissy LeMaire (@cl)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaConnectionStringBuilder

    .EXAMPLE
        PS C:\> New-DbaConnectionStringBuilder

        Returns an empty ConnectionStringBuilder

    .EXAMPLE
        PS C:\> "Data Source=localhost,1433;Initial Catalog=AlwaysEncryptedSample;UID=sa;PWD=alwaysB3Encrypt1ng;Application Name=Always Encrypted Sample MVC App;Column Encryption Setting=enabled" | New-DbaConnectionStringBuilder

        Returns a connection string builder that can be used to connect to the local sql server instance on the default port.

    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingUserNameAndPassWordParams", "")]
    param (
        [Parameter(ValueFromPipeline)]
        [string[]]$ConnectionString = "",
        [string]$ApplicationName = "dbatools Powershell Module",
        [Alias("SqlInstance")]
        [string]$DataSource,
        [PSCredential]$SqlCredential,
        [Alias("Database")]
        [string]$InitialCatalog,
        [switch]$IntegratedSecurity,
        [string]$UserName,
        [string]$Password,
        [Alias('MARS')]
        [switch]$MultipleActiveResultSets,
        [Alias('AlwaysEncrypted')]
        [ValidateSet("Enabled")]
        [string]$ColumnEncryptionSetting,
        [switch]$Legacy,
        [switch]$NonPooledConnection,
        [string]$WorkstationID = $env:COMPUTERNAME,
        [switch]$EnableException
    )
    process {
        $pooling = (-not $NonPooledConnection)
        if ($SqlCredential -and ($Username -or $Password)) {
            Stop-Function -Message "You can only specify SQL Credential or Username/Password, not both." -EnableException $EnableException
            return
        }
        if ($SqlCredential) {
            $UserName = $SqlCredential.UserName
            $Password = $SqlCredential.GetNetworkCredential().Password
        }

        foreach ($cs in $ConnectionString) {
            if ($Legacy) {
                $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder $cs
            } else {
                $builder = New-Object Microsoft.Data.SqlClient.SqlConnectionStringBuilder $cs
            }

            if (!$builder.ShouldSerialize('Application Name')) {
                $builder['Application Name'] = $ApplicationName
            }
            if (Test-Bound -ParameterName DataSource) {
                $builder['Data Source'] = $DataSource
            }
            if (Test-Bound -ParameterName InitialCatalog) {
                $builder['Initial Catalog'] = $InitialCatalog
            }
            if (Test-Bound -ParameterName IntegratedSecurity) {
                if ($IntegratedSecurity) {
                    $builder['Integrated Security'] = $true
                } else {
                    $builder['Integrated Security'] = $false
                }
            }
            if ($UserName) {
                $builder["User ID"] = $UserName
            } elseif (!$IntegratedSecurity) {
                $builder['Integrated Security'] = $false
            }
            if ($Password) {
                $builder['Password'] = $Password
            }
            if (!$builder.ShouldSerialize('Workstation ID')) {
                $builder['Workstation ID'] = $WorkstationID
            }
            if (Test-Bound -ParameterName WorkstationID) {
                $builder['Workstation ID'] = $WorkstationID
            }
            if (Test-Bound -ParameterName MultipleActiveResultSets) {
                if ($MultipleActiveResultSets) {
                    $builder['MultipleActiveResultSets'] = $true
                } else {
                    $builder['MultipleActiveResultSets'] = $false
                }
            }
            if ($ColumnEncryptionSetting -eq "Enabled") {
                $builder['Column Encryption Setting'] = "Enabled"
            }
            if (-not($builder.ShouldSerialize('Pooling'))) {
                $builder['Pooling'] = $pooling
            }
            if (Test-Bound -ParameterName NonPooledConnection) {
                $builder['Pooling'] = $pooling
            }
            $builder
        }
    }
}