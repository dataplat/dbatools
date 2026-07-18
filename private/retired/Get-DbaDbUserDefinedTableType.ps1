function Get-DbaDbUserDefinedTableType {
    <#
    .SYNOPSIS
        Retrieves user-defined table types from SQL Server databases

    .DESCRIPTION
        Retrieves user-defined table types from SQL Server databases, which are custom data types used as table-valued parameters in stored procedures and functions. This command helps DBAs audit these schema-bound objects, document their structure and usage, or identify dependencies before making database changes. Returns detailed information including column definitions, ownership, and creation dates across multiple databases and instances.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to retrieve user-defined table types from. Accepts database names and supports wildcards for pattern matching.
        Use this when you need to examine table types in specific databases rather than all databases on the instance.

    .PARAMETER ExcludeDatabase
        Specifies databases to exclude from the search for user-defined table types. Accepts database names and wildcards.
        Use this when you want to scan most databases but skip specific ones like system databases or inactive databases.

    .PARAMETER Type
        Filters results to include only specific user-defined table type names. Accepts an array of type names for multiple selections.
        Use this when you need to examine particular table types across databases, such as auditing usage of a specific custom type.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database, UserDefinedTableType, Type
        Author: Ant Green (@ant_green)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbUserDefinedTableType

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.UserDefinedTableType

        Returns one UserDefinedTableType object per user-defined table type found. System objects are automatically excluded.

        Default display properties (via Select-DefaultView):
        - ComputerName: The name of the computer hosting the SQL Server instance
        - InstanceName: The name of the SQL Server instance
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Database: The name of the database containing the user-defined table type
        - ID: The unique identifier (ID) of the user-defined table type within the database
        - Name: The name of the user-defined table type
        - Columns: The collection of columns defined in the table type (ColumnCollection object)
        - Owner: The owner (schema) of the user-defined table type
        - CreateDate: The date and time when the user-defined table type was created
        - IsSystemObject: Boolean indicating whether this is a system object (always False for returned results)
        - Version: The internal version number of the user-defined table type

        Additional properties available (from SMO UserDefinedTableType object):
        - DefaultSchema: The default schema for the table type
        - ExtendedProperties: Extended properties (key/value pairs) for the table type
        - Urn: Unique resource name identifying the object in the SQL Server instance
        - State: The state of the object (Existing, Creating, Pending, etc.)

        All properties from the base SMO object are accessible using Select-Object *.

    .EXAMPLE
        PS C:\> Get-DbaDbUserDefinedTableType -SqlInstance sql2016

        Gets all database user defined table types in all the databases

    .EXAMPLE
        PS C:\> Get-DbaDbUserDefinedTableType -SqlInstance Server1 -Database db1

        Gets all the user defined table types for the db1 database

    .EXAMPLE
        PS C:\> Get-DbaDbUserDefinedTableType -SqlInstance Server1 -Database db1 -Type type1

        Gets type1 user defined table type from db1 database

    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [string[]]$Type,
        [switch]$EnableException
    )

    process {
        if (Test-Bound SqlInstance) {
            $InputObject = Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        foreach ($db in $InputObject) {
            if (!$db.IsAccessible) {
                Write-Message -Level Warning -Message "Database $db is not accessible. Skipping."
                continue
            }
            if ($db.UserDefinedTableTypes.Count -eq 0) {
                Write-Message -Message "No User Defined Table Types exist in the $db database on $instance" -Target $db -Level Output
                continue
            }

            if ($Type) {
                $userDefinedTableTypes = $db.UserDefinedTableTypes | Where-Object Name -in $Type
            } else {
                $userDefinedTableTypes = $db.UserDefinedTableTypes
            }

            foreach ($tabletype in $userDefinedTableTypes) {
                if ( $tabletype.IsSystemObject ) {
                    continue
                }

                Add-Member -Force -InputObject $tabletype -MemberType NoteProperty -Name ComputerName -value $tabletype.Parent.ComputerName
                Add-Member -Force -InputObject $tabletype -MemberType NoteProperty -Name InstanceName -value $tabletype.Parent.InstanceName
                Add-Member -Force -InputObject $tabletype -MemberType NoteProperty -Name SqlInstance -value $tabletype.Parent.SqlInstance
                Add-Member -Force -InputObject $tabletype -MemberType NoteProperty -Name Database -value $db.Name

                $defaults = ('ComputerName', 'InstanceName', 'SqlInstance' , 'Database' , 'ID', 'Name', 'Columns', 'Owner', 'CreateDate', 'IsSystemObject', 'Version')

                Select-DefaultView -InputObject $tabletype -Property $defaults
            }
        }
    }
}