function New-DbaReplCreationScriptOptions {
    <#
    .SYNOPSIS
        Creates replication article creation script options for controlling which database objects are replicated

    .DESCRIPTION
        Creates a Microsoft.SqlServer.Replication.CreationScriptOptions object that controls which database objects and properties are included when replicating tables through SQL Server replication. This determines what gets scripted at the subscriber when articles are added to publications - things like indexes, constraints, triggers, and identity columns.

        By default, includes the same options that SQL Server Management Studio uses when adding articles: primary objects, custom procedures, identity properties, timestamps, clustered indexes, primary keys, collation, unique keys, and constraint replication settings. Use -NoDefaults to start with a blank slate and specify only the options you want.

        This object is typically used with Add-DbaReplArticle to precisely control what database schema elements are replicated to subscribers, avoiding common issues like missing indexes or constraints that can impact subscriber performance.

        See https://learn.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.replication.creationscriptoptions for more information

    .PARAMETER Options
        The options to set on published articles.
        See https://docs.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.replication.creationscriptoptions for a list of available options

    .PARAMETER NoDefaults
        If specified, no default options will be set on the object

        Defaults are copied from when you add an article in SQL Server Management Studio and include:
            PrimaryObject, CustomProcedures, Identity, KeepTimestamp,
            ClusteredIndexes, DriPrimaryKey, Collation, DriUniqueKeys,
            MarkReplicatedCheckConstraintsAsNotForReplication,
            MarkReplicatedForeignKeyConstraintsAsNotForReplication, and Schema

    .NOTES
        Tags: repl, Replication, Script
        Author: Jess Pomfret (@jpomfret), jesspomfret.com

        Website: https://dbatools.io
        Copyright: (c) 2023 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaReplCreationScriptOptions

    .EXAMPLE
        PS C:\> $cso = New-DbaReplCreationScriptOptions -Options NonClusteredIndexes, Statistics
        PS C:\> $article = @{
        >> SqlInstance           = 'mssql1'
        >> Database              = 'pubs'
        >> PublicationName       = 'testPub'
        >> Name                  = 'stores'
        >> CreationScriptOptions = $cso
        >> }
        PS C:\> Add-DbaReplArticle @article -EnableException

        Adds the stores table to the testPub publication from mssql1.pubs with the NonClusteredIndexes and Statistics options set
        includes default options.


    .EXAMPLE
        PS C:\> $cso = New-DbaReplCreationScriptOptions -Options ClusteredIndexes, Identity -NoDefaults
        PS C:\> $article = @{
        >> SqlInstance           = 'mssql1'
        >> Database              = 'pubs'
        >> PublicationName       = 'testPub'
        >> Name                  = 'stores'
        >> CreationScriptOptions = $cso
        >> }
        PS C:\> Add-DbaReplArticle @article -EnableException

        Adds the stores table to the testPub publication from mssql1.pubs with the ClusteredIndexes and Identity options set, excludes default options.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    param (
        [String[]]$Options,
        [switch]$NoDefaults
    )

    $cso = New-Object Microsoft.SqlServer.Replication.CreationScriptOptions

    if (-not $NoDefaults) {
        'PrimaryObject', 'CustomProcedures', 'Identity', 'KeepTimestamp', 'ClusteredIndexes', 'DriPrimaryKey', 'Collation', 'DriUniqueKeys', 'MarkReplicatedCheckConstraintsAsNotForReplication', 'MarkReplicatedForeignKeyConstraintsAsNotForReplication', 'Schema' | ForEach-Object { $cso += $_ }
    }

    foreach ($opt in $options) {
        $cso += $opt
    }

    $cso
}