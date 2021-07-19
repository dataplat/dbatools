function New-DbaConnectionStringBuilder {
    <#
    .SYNOPSIS
        Returns a Microsoft.Data.SqlClient.SqlConnectionStringBuilder with the string specified

    .DESCRIPTION
        Creates a Microsoft.Data.SqlClient.SqlConnectionStringBuilder from a connection string.

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
        [string]$WorkstationId = $env:COMPUTERNAME
    )
    process {
        $pooled = (-not $NonPooledConnection)
        if ($SqlCredential -and ($Username -or $Password)) {
            Stop-Function -Message "You can only specify SQL Credential or Username/Password, not both."
            return
        }
        if ($SqlCredential) {
            $UserName = $SqlCredential.UserName
            $Password = $SqlCredential.GetNetworkCredential().Password
        }
        if (-not $UserName) {
            $PSBoundParameters.IntegratedSecurity = $true
        }

        foreach ($cs in $ConnectionString) {
            if ($Legacy) {
                $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder $cs
            } else {
                $builder = New-Object Microsoft.Data.SqlClient.SqlConnectionStringBuilder $cs
            }

            if ($builder.ApplicationName -in "Framework Microsoft SqlClient Data Provider", ".Net SqlClient Data Provider") {
                $builder['Application Name'] = $ApplicationName
            }
            if ($PSBoundParameters.DataSource) {
                $builder['Data Source'] = $DataSource
            }
            if ($PSBoundParameters.InitialCatalog) {
                $builder['Initial Catalog'] = $InitialCatalog
            }
            if ($PSBoundParameters.IntegratedSecurity) {
                $builder['Integrated Security'] = $PSBoundParameters.IntegratedSecurity
            }
            if ($UserName) {
                $builder["User ID"] = $UserName
            }
            if ($Password) {
                $builder['Password'] = $Password
            }
            if ($WorkstationId) {
                $builder['Workstation ID'] = $WorkstationId
            }
            if ($MultipleActiveResultSets -eq $true) {
                $builder['MultipleActiveResultSets'] = $true
            }
            if ($ColumnEncryptionSetting -eq "Enabled") {
                $builder['Column Encryption Setting'] = "Enabled"
            }
            if ($pooled) {
                $builder['Pooled'] = $pooled
            }
            $builder
        }
    }
}