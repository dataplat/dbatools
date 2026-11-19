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
        Specifies which database object properties to include when creating replicated tables at subscribers. Controls what gets scripted beyond the basic table structure.
        Use this to add specific elements like NonClusteredIndexes, Statistics, CheckConstraints, or ForeignKeys that aren't included in the default set.
        Common values include Statistics for performance, NonClusteredIndexes for query optimization, or Triggers for business logic replication.

    .PARAMETER NoDefaults
        Excludes the standard replication options that SQL Server Management Studio applies automatically when adding articles.
        Use this when you need precise control over which schema elements are replicated and want to avoid the default behavior.
        Without this switch, includes PrimaryObject, CustomProcedures, Identity, KeepTimestamp, ClusteredIndexes, DriPrimaryKey, Collation, DriUniqueKeys, and constraint replication settings.

    .OUTPUTS
        Microsoft.SqlServer.Replication.CreationScriptOptions

        Returns a CreationScriptOptions enum instance that encapsulates the selected replication schema options.
        This object can be passed to Add-DbaReplArticle's CreationScriptOptions parameter to control which schema elements are replicated to subscribers.

        The object represents a combination of zero or more schema option flags, including:
        - PrimaryObject: The table structure
        - CustomProcedures: Custom stored procedures
        - Identity: Identity column properties
        - KeepTimestamp: Timestamp columns
        - ClusteredIndexes: Clustered indexes
        - NonClusteredIndexes: Non-clustered indexes
        - DriPrimaryKey: Primary key constraints
        - DriForeignKeys: Foreign key constraints
        - DriUniqueKeys: Unique key constraints
        - CheckConstraints: Check constraints
        - Collation: Column-level collation
        - MarkReplicatedCheckConstraintsAsNotForReplication: Check constraints marked as not for replication
        - MarkReplicatedForeignKeyConstraintsAsNotForReplication: Foreign key constraints marked as not for replication
        - Schema: Database schema association
        - And 27+ additional replication schema options

        See https://learn.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.replication.creationscriptoptions for the complete list of available options.

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