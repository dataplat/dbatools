function New-DbaReplCreationScriptOptions {
    <#
    .SYNOPSIS
        Creates a new Microsoft.SqlServer.Replication.CreationScriptOptions enumeration object.

    .DESCRIPTION
        Creates a new Microsoft.SqlServer.Replication.CreationScriptOptions enumeration object that allows you to specify article options.

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