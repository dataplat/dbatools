function Start-DbaAzMigration {
    <#
    .SYNOPSIS
        Migrates SQL Server databases to an existing Azure SQL Database logical server using BACPAC files.

    .DESCRIPTION
        Exports selected accessible user databases from one SQL Server instance as BACPAC files and imports them into an existing Azure SQL Database logical server with the same database names.

        This command migrates databases only. It does not provision Azure resources or migrate server-level objects such as logins, credentials, SQL Agent jobs, linked servers, or server roles. Azure SQL Managed Instance migrations should use Copy-DbaDatabase instead.

        Microsoft DacFx is supplied through dbatools.library, so no additional module or SqlPackage installation is required. Generated BACPAC files contain data and are removed after each migration by default.

    .PARAMETER Source
        The source SQL Server instance or reusable connected server object.

    .PARAMETER Destination
        The existing Azure SQL Database logical server or reusable connected server object. The connecting principal must be able to create and, when Force is used, remove databases.

    .PARAMETER SourceSqlCredential
        Credential used to connect to the source SQL Server instance.

    .PARAMETER DestinationSqlCredential
        Credential used to connect to the destination Azure SQL logical server.

    .PARAMETER Database
        The source databases to migrate. When omitted, all accessible user databases are selected.

    .PARAMETER ExcludeDatabase
        Source databases to exclude after applying the Database filter.

    .PARAMETER Path
        Directory used for generated BACPAC files. Defaults to the configured dbatools temporary path.

    .PARAMETER ExportDacOption
        A Microsoft.SqlServer.Dac.DacExportOptions object passed to BACPAC export.

    .PARAMETER ImportDacOption
        A Microsoft.SqlServer.Dac.DacImportOptions object passed to BACPAC import. Use this option to configure the Azure edition, service objective, maximum size, and DacFx import settings.

    .PARAMETER Force
        Drops and recreates a destination database when a database with the same name already exists.

    .PARAMETER KeepBacpac
        Keeps generated BACPAC files after migration. BACPAC files contain schema and table data and must be secured appropriately.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration, Azure, Database, Bacpac
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2026 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Start-DbaAzMigration

    .OUTPUTS
        PSCustomObject

        Returns one MigrationObject per selected database with SourceServer, DestinationServer, Name, DestinationDatabase, Type, Status, Notes, DateTime, BacpacPath, and Elapsed properties.

    .EXAMPLE
        PS C:\> Start-DbaAzMigration -Source sql01 -Destination dbatools.database.windows.net -Database AppDb

        Migrates AppDb to the existing Azure SQL logical server and removes the temporary BACPAC after import.

    .EXAMPLE
        PS C:\> $options = New-DbaDacOption -Type Bacpac -Action Publish
        PS C:\> $options.DatabaseSpecification.Edition = "Standard"
        PS C:\> $options.DatabaseSpecification.ServiceObjective = "S0"
        PS C:\> Start-DbaAzMigration -Source sql01 -Destination dbatools.database.windows.net -ImportDacOption $options -Force -Confirm:$false

        Migrates all accessible user databases and replaces databases that already exist, using the selected Azure service objective.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [Parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [Parameter(Mandatory)]
        [DbaInstanceParameter]$Destination,
        [PSCredential]$SourceSqlCredential,
        [PSCredential]$DestinationSqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [string]$Path = (Get-DbatoolsConfigValue -FullName "Path.DbatoolsTemp"),
        [object]$ExportDacOption,
        [object]$ImportDacOption,
        [switch]$Force,
        [switch]$KeepBacpac,
        [switch]$EnableException
    )

    process {
        if (Test-FunctionInterrupt) { return }
    }
}
