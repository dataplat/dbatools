function Copy-DbaDbViewData {
    <#
    .SYNOPSIS
        Copies data from SQL Server views to destination tables using high-performance bulk copy operations.

    .DESCRIPTION
        Extracts data from SQL Server views and bulk copies it to destination tables, either on the same instance or across different servers.
        Uses SqlBulkCopy for optimal performance when migrating view data, materializing view results, or creating data snapshots from complex views.
        Supports custom queries against views, identity preservation, constraint checking, and automatic destination table creation.
        Handles large datasets efficiently with configurable batch sizes and minimal resource overhead compared to traditional INSERT statements.

    .PARAMETER SqlInstance
        Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the source instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        Target SQL Server instance where view data will be copied to. Accepts one or more SQL Server instances.
        Specify this when copying view data to a different server than the source, or when doing cross-instance data transfers.

    .PARAMETER DestinationSqlCredential
        Alternative credentials for authenticating to the destination instance. Required when your current Windows credentials don't have access to the target server.
        Use this for cross-domain scenarios, SQL authentication, or when the destination requires different security context than the source.

    .PARAMETER Database
        Source database containing the view to copy data from. Required when not using pipeline input.
        Must exist on the source instance and your account must have read permissions on the specified view.

    .PARAMETER DestinationDatabase
        Target database where copied view data will be inserted. Defaults to the same database name as the source.
        Use this when copying data to a different database name on the destination instance or for cross-database copies within the same server.

    .PARAMETER View
        Source view name to copy data from. Accepts 2-part ([schema].[view]) or 3-part ([database].[schema].[view]) names.
        Use square brackets for names with spaces or special characters. Required to specify which view's data to extract and copy.

    .PARAMETER DestinationTable
        Target table name where view data will be inserted. Defaults to the same name as the source view.
        Use this when copying to a table with a different name or schema, or when materializing view data into a permanent table structure.

    .PARAMETER Query
        Custom SQL SELECT query to use as the data source instead of copying the entire view. Supports 3 or 4-part object names.
        Use this when you need to filter rows, join the view with other tables, or transform data during the copy operation. Still requires specifying a View parameter for metadata purposes.

    .PARAMETER AutoCreateTable
        Automatically creates the destination table if it doesn't exist, using the same structure as the source view.
        Essential for initial data migrations or when materializing view data into new tables where destination tables haven't been created yet.

    .PARAMETER BatchSize
        Number of rows to process in each bulk copy batch. Defaults to 50000 rows.
        Reduce this value for memory-constrained systems or increase it for faster transfers when copying large view result sets with sufficient memory.

    .PARAMETER NotifyAfter
        Number of rows to process before displaying progress updates. Defaults to 5000 rows.
        Set to a lower value for frequent updates on small view datasets or higher for less verbose output on large view copies.

    .PARAMETER NoTableLock
        Disables the default table lock (TABLOCK) on the destination table during bulk copy operations.
        Use this when you need to allow concurrent read access to the destination table, though it may reduce bulk copy performance.

    .PARAMETER CheckConstraints
        Enables constraint checking during bulk copy operations. By default, constraints are ignored for performance.
        Use this when data integrity validation is more important than copy speed, particularly when copying view data to tables with strict business rules.

    .PARAMETER FireTriggers
        Enables INSERT triggers to fire during bulk copy operations. By default, triggers are bypassed for performance.
        Use this when you need audit trails, logging, or other trigger-based business logic to execute during the view data copy.

    .PARAMETER KeepIdentity
        Preserves the original identity column values from the source view. By default, the destination generates new identity values.
        Essential when copying view data that includes identity columns and you need to maintain exact ID relationships in the destination table.

    .PARAMETER KeepNulls
        Preserves NULL values from the source view data instead of replacing them with destination column defaults.
        Use this when you need exact source data reproduction from the view, especially when NULL has specific business meaning versus default values.

    .PARAMETER Truncate
        Removes all existing data from the destination table before copying new view data. Prompts for confirmation unless -Force is used.
        Essential for refresh scenarios where you want to replace all destination data with current view data.

    .PARAMETER BulkCopyTimeOut
        Maximum time in seconds to wait for bulk copy operations to complete. Defaults to 5000 seconds (83 minutes).
        Increase this value when copying very large view result sets that may take longer than the default timeout period.

    .PARAMETER InputObject
        Accepts view objects from Get-DbaDbView for pipeline operations.
        Use this to copy data from multiple views by piping them from Get-DbaDbView, allowing batch processing of view data copies.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Table, Data
        Author: Stephen Swan (@jaxnoth)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Copy-DbaDbViewData

    .EXAMPLE
        PS C:\> Copy-DbaDbViewData -SqlInstance sql1 -Destination sql2 -Database dbatools_from -View dbo.test_view

        Copies all the data from view dbo.test_view (2-part name) in database dbatools_from on sql1 to view test_view in database dbatools_from on sql2.

    .EXAMPLE
        PS C:\> Copy-DbaDbViewData -SqlInstance sql1 -Destination sql2 -Database dbatools_from -DestinationDatabase dbatools_dest -DestinationTable [Schema].[test table]

        Copies all the data from view [Schema].[test view] (2-part name) in database dbatools_from on sql1 to table [Schema].[test table] in database dbatools_dest on sql2

    .EXAMPLE
        PS C:\> Get-DbaDbView -SqlInstance sql1 -Database tempdb -View vw1, vw2 | Copy-DbaDbViewData -DestinationTable tb3

        Copies all data from Views vw1 and vw2 in tempdb on sql1 to tb3 in tempdb on sql1

    .EXAMPLE
        PS C:\> Get-DbaDbView -SqlInstance sql1 -Database tempdb -View vw1, vw2 | Copy-DbaDbViewData -Destination sql2

        Copies data from tbl1 in tempdb on sql1 to tbl1 in tempdb on sql2
        then
        Copies data from tbl2 in tempdb on sql1 to tbl2 in tempdb on sql2

    .EXAMPLE
        PS C:\> Copy-DbaDbViewData -SqlInstance sql1 -Destination sql2 -Database dbatools_from -View test_view -KeepIdentity -Truncate

        Copies all the data in view test_view from sql1 to sql2, using the database dbatools_from, keeping identity columns and truncating the destination

    .EXAMPLE
        PS C:\> $params = @{
        >> SqlInstance = 'sql1'
        >> Destination = 'sql2'
        >> Database = 'dbatools_from'
        >> DestinationDatabase = 'dbatools_dest'
        >> View = '[Schema].[View]'
        >> DestinationTable = '[dbo].[View.Copy]'
        >> KeepIdentity = $true
        >> KeepNulls = $true
        >> Truncate = $true
        >> BatchSize = 10000
        >> }
        >>
        PS C:\> Copy-DbaDbViewData @params

        Copies all the data from view [Schema].[View] in database dbatools_from on sql1 to table [dbo].[Table.Copy] in database dbatools_dest on sql2
        Keeps identity columns and Nulls, truncates the destination and processes in BatchSize of 10000.

    .EXAMPLE
        PS C:\> $params = @{
        >> SqlInstance = 'server1'
        >> Destination = 'server1'
        >> Database = 'AdventureWorks2017'
        >> DestinationDatabase = 'AdventureWorks2017'
        >> View = '[AdventureWorks2017].[Person].[EmailPromotion]'
        >> BatchSize = 10000
        >> Query = "SELECT * FROM [OtherDb].[Person].[Person] where EmailPromotion = 1"
        >> }
        >>
        PS C:\> Copy-DbaDbViewData @params

        Copies data returned from the query on server1 into the AdventureWorks2017 on server1.
        This query uses a 3-part name to reference the object in the query value, it will try to find the view named "Person" in the schema "Person" and database "OtherDb".
        Copy is processed in BatchSize of 10000 rows. See the -Query param documentation for more details.
    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess)]
    param (
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [string]$Database,
        [string]$DestinationDatabase,
        [string[]]$View,
        [string]$Query,
        [switch]$AutoCreateTable,
        [int]$BatchSize = 50000,
        [int]$NotifyAfter = 5000,
        [string]$DestinationTable,
        [switch]$NoTableLock,
        [switch]$CheckConstraints,
        [switch]$FireTriggers,
        [switch]$KeepIdentity,
        [switch]$KeepNulls,
        [switch]$Truncate,
        [int]$BulkCopyTimeOut = 5000,
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.TableViewBase[]]$InputObject,
        [switch]$EnableException
    )

    process {
        Copy-DbaDbTableData @PSBoundParameters
    }
}