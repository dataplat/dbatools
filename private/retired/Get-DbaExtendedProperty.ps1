function Get-DbaExtendedProperty {
    <#
    .SYNOPSIS
        Retrieves custom metadata and documentation stored as extended properties on SQL Server objects

    .DESCRIPTION
        Retrieves extended properties that contain custom metadata, documentation, and business descriptions attached to SQL Server objects. Extended properties are commonly used by DBAs and developers to store object documentation, version information, business rules, and compliance notes directly within the database schema.

        This function discovers what documentation and metadata exists across your database objects, making it invaluable for database documentation audits, compliance reporting, and understanding legacy systems. You can retrieve properties from databases by default, or pipe in any SQL Server object from other dbatools commands to examine its custom metadata.

        Works with all major SQL Server object types including databases, tables, columns, stored procedures, functions, views, indexes, schemas, triggers, and many others. The command handles both direct database queries and piped objects seamlessly, so you can easily incorporate extended property discovery into broader database analysis workflows.

        Perfect for discovering undocumented business logic, finding objects with compliance tags, or building comprehensive database documentation reports from existing metadata.

    .PARAMETER SqlInstance
        The target SQL Server instance

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to search for extended properties. Only applies when connecting directly to SqlInstance.
        Use this when you need to examine extended properties from specific databases rather than all accessible databases on the instance.

    .PARAMETER Name
        Filters results to extended properties with specific names. Accepts multiple property names.
        Use this when you know the exact property names you're looking for, such as finding all objects tagged with 'Description' or 'Version' properties.

    .PARAMETER InputObject
        Accepts SQL Server objects piped from other dbatools commands to examine their extended properties.
        Use this to discover metadata on specific objects like tables, stored procedures, or views returned from commands like Get-DbaDbTable or Get-DbaDbStoredProcedure.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: General, ExtendedProperty
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaExtendedProperty

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.ExtendedProperty

        Returns one extended property object per extended property found on the specified SQL Server objects. When querying by SqlInstance and Database, this includes extended properties at the database level. When piping objects from other dbatools commands, extended properties from those specific objects are returned.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - ParentName: Name of the SQL Server object that owns this extended property
        - Type: The type name of the parent object (e.g., Database, Table, StoredProcedure, Column)
        - Name: The name of the extended property
        - Value: The value or content of the extended property (can be any string data)

        Additional properties available (from SMO ExtendedProperty object):
        - Parent: Reference to the parent SQL Server object
        - Urn: The Uniform Resource Name of the extended property
        - Properties: Collection of property objects
        - State: The current state of the SMO object (Existing, Creating, Pending, etc.)

        The Server property added by this command contains the connection object for programmatic access to the parent SQL Server instance.

    .EXAMPLE
        PS C:\> Get-DbaExtendedProperty -SqlInstance sql2016

        Gets all extended properties on all databases

    .EXAMPLE
        PS C:\> Get-DbaExtendedProperty -SqlInstance Server1 -Database db1

        Gets the extended properties for the db1 database

    .EXAMPLE
        PS C:\> Get-DbaExtendedProperty -SqlInstance Server1 -Database db1 -Name info1, info2

        Gets the info1 and info2 extended properties within the db1 database

    .EXAMPLE
        PS C:\> Get-DbaDbStoredProcedure -SqlInstance localhost -Database tempdb | Get-DbaExtendedProperty

        Get the extended properties for all stored procedures in the tempdb database

    .EXAMPLE
        PS C:\> Get-DbaDbTable -SqlInstance localhost -Database mydb -Table mytable | Get-DbaExtendedProperty

        Get the extended properties for the mytable table in the mydb database
    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [Alias("Property")]
        [string[]]$Name,
        [parameter(ValueFromPipeline)]
        [psobject[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ($SqlInstance) {
            $InputObject = Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database | Where-Object IsAccessible
        }

        foreach ($object in $InputObject) {
            $props = $object.ExtendedProperties

            if ($null -eq $props) {
                Write-Message -Message "No extended properties exist in the $object on $instance" -Target $object -Level Verbose
                continue
            }

            if ($Name) {
                $props = $props | Where-Object Name -in $Name
            }

            # Since the inputobject is so generic, we need to re-build these properties
            $computername = $object.ComputerName
            $instancename = $object.InstanceName
            $sqlname = $object.SqlInstance

            if (-not $computername -or -not $instancename -or -not $sqlname) {
                $server = Get-ConnectionParent $object
                $servername = $server.Query("SELECT @@SERVERNAME AS servername").servername

                if (-not $computername) {
                    $computername = ([DbaInstanceParameter]$servername).ComputerName
                }

                if (-not $instancename) {
                    $instancename = ([DbaInstanceParameter]$servername).InstanceName
                }

                if (-not $sqlname) {
                    $sqlname = $servername
                }
            }

            foreach ($prop in $props) {
                Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name ComputerName -Value $computername
                Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name InstanceName -Value $instancename
                Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name SqlInstance -Value $sqlname
                Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name ParentName -Value $object.Name
                Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name Type -Value $object.GetType().Name
                Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name Server -Value $server


                Select-DefaultView -InputObject $prop -Property ComputerName, InstanceName, SqlInstance, ParentName, Type, Name, Value
            }
        }
    }
}