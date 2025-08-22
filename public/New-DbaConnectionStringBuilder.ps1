function New-DbaConnectionStringBuilder {
    <#
    .SYNOPSIS
        Creates a SqlConnectionStringBuilder object for constructing properly formatted SQL Server connection strings

    .DESCRIPTION
        Creates a Microsoft.Data.SqlClient.SqlConnectionStringBuilder object from either an existing connection string or individual connection parameters. This allows you to programmatically build, modify, or validate connection strings without manually concatenating string values. The function handles authentication methods, encryption settings, connection pooling, and other SQL Server connection options, making it useful for scripts that need to connect to different SQL Server instances with varying configurations.

    .PARAMETER ConnectionString
        A Connection String

    .PARAMETER ApplicationName
        The application name to tell SQL Server the connection is associated with.

    .PARAMETER DataSource
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Credential object used to connect to the SQL Server Instance as a different user. This can be a Windows or SQL Server account. Windows users are determined by the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it contains a backslash.

    .PARAMETER InitialCatalog
        The initial database on the server to connect to.

    .PARAMETER IntegratedSecurity
        Sets to use windows authentication.

    .PARAMETER UserName
        Sql User Name to connect with. Consider using SqlCredential instead.

    .PARAMETER Password
        Password to use to connect with. Consider using SqlCredential instead.

    .PARAMETER MultipleActiveResultSets
        Enable Multiple Active Result Sets.

    .PARAMETER ColumnEncryptionSetting
        Enable Always Encrypted.

    .PARAMETER WorkstationID
        Set the Workstation Id that is associated with the connection.

    .PARAMETER NonPooledConnection
        If this switch is enabled, a non-pooled connection will be requested.

    .PARAMETER Legacy
        Use this switch to create a connection string using System.Data.SqlClient instead of Microsoft.Data.SqlClient.

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