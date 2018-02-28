#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function New-DbaSqlConnectionStringBuilder {
    <#
        .SYNOPSIS
            Returns a System.Data.SqlClient.SqlConnectionStringBuilder with the string specified

        .DESCRIPTION
            Creates a System.Data.SqlClient.SqlConnectionStringBuilder from a connection string.

        .PARAMETER ConnectionString
            A Connection String

        .PARAMETER ApplicationName
            The application name to tell SQL Server the connection is associated with.

        .PARAMETER DataSource
            The Sql Server to connect to.

        .PARAMETER InitialCatalog
            The initial database on the server to connect to.

        .PARAMETER IntegratedSecurity
            Set to true to use windows authentication.

        .PARAMETER UserName
            Sql User Name to connect with.

        .PARAMETER Password
            Password to use to connect with.

        .PARAMETER MultipleActiveResultSets
            Enable Multiple Active Result Sets.

        .PARAMETER ColumnEncryptionSetting
            Enable Always Encrypted.

        .PARAMETER WorkstationID
            Set the Workstation Id that is associated with the connection.

        .NOTES
            Author: zippy1981
            Tags: SqlBuild, ConnectionString, Connection

            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Copyright (C) 2017 Chrissy LeMaire
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/New-DbaSqlConnectionStringBuilder

        .EXAMPLE
            New-DbaSqlConnectionStringBuilder

            Returns an empty ConnectionStringBuilder

        .EXAMPLE
            "Data Source=localhost,1433;Initial Catalog=AlwaysEncryptedSample;UID=sa;PWD=alwaysB3Encrypt1ng;Application Name=Always Encrypted Sample MVC App;Column Encryption Setting=enabled" | New-DbaSqlConnectionStringBuilder

            Returns a connection string builder that can be used to connect to the local sql server instance on the default port.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingUserNameAndPassWordParams", "")]
    param (
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [string[]]$ConnectionString = "",
        [Parameter(Mandatory = $false)]
        [string]$ApplicationName = "dbatools Powershell Module",
        [Parameter(Mandatory = $false)]
        [string]$DataSource = $null,
        [Parameter(Mandatory = $false)]
        [string]$InitialCatalog = $null,
        [Parameter(Mandatory = $false)]
        [Nullable[bool]]$IntegratedSecurity = $null,
        [Parameter(Mandatory = $false)]
        [string]$UserName = $null,
        # No point in securestring here, the memory is never stored securely in memory.
        [Parameter(Mandatory = $false)]
        [string]$Password = $null,
        [Alias('MARS')]
        [Parameter(Mandatory = $false)]
        [switch]$MultipleActiveResultSets,
        [Alias('AlwaysEncrypted')]
        [Parameter(Mandatory = $false)]
        [Data.SqlClient.SqlConnectionColumnEncryptionSetting]$ColumnEncryptionSetting =
        [Data.SqlClient.SqlConnectionColumnEncryptionSetting]::Enabled,
        [Parameter(Mandatory = $false)]
        [string]$WorkstationId = $env:COMPUTERNAME
    )
    process {
        foreach ($cs in $ConnectionString) {
            $builder = New-Object Data.SqlClient.SqlConnectionStringBuilder $cs
            if ($builder.ApplicationName -eq ".Net SqlClient Data Provider") {
                $builder['Application Name'] = $ApplicationName
            }
            if (![string]::IsNullOrWhiteSpace($DataSource)) {
                $builder['Data Source'] = $DataSource
            }
            if (![string]::IsNullOrWhiteSpace($InitialCatalog)) {
                $builder['Initial Catalog'] = $InitialCatalog
            }
            if (![string]::IsNullOrWhiteSpace($IntegratedSecurity)) {
                $builder['Integrated Security'] = $IntegratedSecurity
            }
            if (![string]::IsNullOrWhiteSpace($UserName)) {
                $builder["User ID"] = $UserName
            }
            if (![string]::IsNullOrWhiteSpace($Password)) {
                $builder['Password'] = $Password
            }
            if (![string]::IsNullOrWhiteSpace($WorkstationId)) {
                $builder['Workstation ID'] = $WorkstationId
            }
            if ($MultipleActiveResultSets -eq $true) {
                $builder['MultipleActiveResultSets'] = $true
            }
            if ($ColumnEncryptionSetting -eq [Data.SqlClient.SqlConnectionColumnEncryptionSetting]::Enabled) {
                $builder['Column Encryption Setting'] = [Data.SqlClient.SqlConnectionColumnEncryptionSetting]::Enabled
            }
            $builder
        }
    }
}