function Get-DbaDbForeignKey {
    <#
    .SYNOPSIS
        Retrieves foreign key constraints from SQL Server database tables

    .DESCRIPTION
        Retrieves all foreign key constraint definitions from tables across one or more SQL Server databases.
        Essential for documenting referential integrity relationships, analyzing table dependencies before migrations, and troubleshooting cascade operations.
        Returns detailed foreign key properties including referenced tables, schema information, and constraint status (enabled/disabled, checked/unchecked).
        Supports filtering by database and excluding system tables to focus on user-defined constraints.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to scan for foreign key constraints. Accepts database names, wildcards, or arrays.
        Use this when you need to focus on specific databases rather than scanning all accessible databases on the instance.

    .PARAMETER ExcludeDatabase
        Excludes specific databases from the foreign key scan. Useful for skipping large databases, test environments, or databases known to have no relevant constraints.
        Commonly used to exclude system databases like master, model, msdb, and tempdb when focusing on user databases.

    .PARAMETER ExcludeSystemTable
        Excludes system tables from the foreign key analysis, focusing only on user-created tables.
        Use this switch when documenting application schemas or analyzing business logic relationships, as system table foreign keys are typically not relevant for most DBA tasks.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database, ForeignKey, Table
        Author: Claudio Silva (@ClaudioESSilva), claudioessilva.eu

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbForeignKey

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.ForeignKey

        Returns one ForeignKey object per foreign key constraint found in the specified databases. Each object represents a single foreign key relationship between tables.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Database: The database name containing the foreign key
        - Schema: The schema name containing the table with the foreign key
        - Table: The table name that contains the foreign key (referencing table)
        - ID: Unique identifier of the foreign key constraint
        - CreateDate: DateTime when the foreign key constraint was created
        - DateLastModified: DateTime when the foreign key constraint was last modified
        - Name: The name of the foreign key constraint
        - IsEnabled: Boolean indicating if the foreign key constraint is currently enabled
        - IsChecked: Boolean indicating if the constraint is enforced during INSERT/UPDATE operations
        - NotForReplication: Boolean indicating if the constraint applies to replication operations
        - ReferencedKey: The primary key or unique key being referenced by this foreign key
        - ReferencedTable: The name of the table being referenced (referenced table)
        - ReferencedTableSchema: The schema name of the referenced table

        Additional properties available (from SMO ForeignKey object):
        - Columns: Collection of columns that make up the foreign key
        - DeleteAction: Action to take when the referenced row is deleted (NoAction, Cascade, SetNull, SetDefault)
        - UpdateAction: Action to take when the referenced key is updated (NoAction, Cascade, SetNull, SetDefault)
        - DatabaseEngineEdition: The SQL Server edition where the foreign key exists
        - DatabaseEngineType: The type of database engine
        - IsMemoryOptimized: Boolean indicating if the parent table is memory-optimized
        - IsSystemNamed: Boolean indicating if the constraint was system-generated (auto-named)
        - State: SMO object state (Existing, Creating, Dropping, etc.)
        - Urn: Unique Resource Name for the constraint
        - ExtendedProperties: Extended properties attached to the constraint

        All properties from the base SMO ForeignKey object are accessible even though only default properties are displayed without using Select-Object *.

    .EXAMPLE
        PS C:\> Get-DbaDbForeignKey -SqlInstance sql2016

        Gets all database Foreign Keys.

    .EXAMPLE
        PS C:\> Get-DbaDbForeignKey -SqlInstance Server1 -Database db1

        Gets the Foreign Keys for the db1 database.

    .EXAMPLE
        PS C:\> Get-DbaDbForeignKey -SqlInstance Server1 -ExcludeDatabase db1

        Gets the Foreign Keys for all databases except db1.

    .EXAMPLE
        PS C:\> Get-DbaDbForeignKey -SqlInstance Server1 -ExcludeSystemTable

        Gets the Foreign Keys from all tables that are not system objects from all databases.

    .EXAMPLE
        PS C:\> 'Sql1','Sql2/sqlexpress' | Get-DbaDbForeignKey

        Gets the Foreign Keys for the databases on Sql1 and Sql2/sqlexpress.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$ExcludeSystemTable,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $databases = $server.Databases | Where-Object IsAccessible

            if ($Database) {
                $databases = $databases | Where-Object Name -In $Database
            }
            if ($ExcludeDatabase) {
                $databases = $databases | Where-Object Name -NotIn $ExcludeDatabase
            }

            foreach ($db in $databases) {
                if (!$db.IsAccessible) {
                    Write-Message -Level Warning -Message "Database $db is not accessible. Skipping."
                    continue
                }

                foreach ($tbl in $db.Tables) {
                    if ( (Test-Bound -ParameterName ExcludeSystemTable) -and $tbl.IsSystemObject ) {
                        continue
                    }

                    if ($tbl.ForeignKeys.Count -eq 0) {
                        Write-Message -Message "No Foreign Keys exist in $tbl table on the $db database on $instance" -Target $tbl -Level Verbose
                        continue
                    }

                    foreach ($fk in $tbl.ForeignKeys) {
                        Add-Member -Force -InputObject $fk -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                        Add-Member -Force -InputObject $fk -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                        Add-Member -Force -InputObject $fk -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                        Add-Member -Force -InputObject $fk -MemberType NoteProperty -Name Database -value $db.Name
                        Add-Member -Force -InputObject $fk -MemberType NoteProperty -Name Schema -Value $tbl.Schema
                        Add-Member -Force -InputObject $fk -MemberType NoteProperty -Name Table -Value $tbl.Name

                        $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Schema', 'Table', 'ID', 'CreateDate',
                        'DateLastModified', 'Name', 'IsEnabled', 'IsChecked', 'NotForReplication', 'ReferencedKey', 'ReferencedTable', 'ReferencedTableSchema'
                        Select-DefaultView -InputObject $fk -Property $defaults
                    }
                }
            }
        }
    }
}