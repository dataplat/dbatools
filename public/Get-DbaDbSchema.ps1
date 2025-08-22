function Get-DbaDbSchema {
    <#
    .SYNOPSIS
        Retrieves database schema objects from SQL Server instances for inventory, security auditing, and management tasks

    .DESCRIPTION
        Returns SQL Server Management Object (SMO) schema objects from one or more databases, allowing you to inspect schema ownership, enumerate database organization, and identify schema-level security configurations. This function is essential for database documentation, security auditing when you need to track who owns which schemas, and migration planning where schema ownership and structure must be preserved. You can filter results by specific schema names, schema owners, or databases, and optionally include system schemas like dbo, sys, and INFORMATION_SCHEMA which are excluded by default.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The target database(s).

    .PARAMETER Schema
        The name(s) of the schema(s)

    .PARAMETER SchemaOwner
        The name(s) of the database user(s) that own(s) the schema(s).

    .PARAMETER IncludeSystemDatabases
        Include the system databases.

    .PARAMETER IncludeSystemSchemas
        Include the system schemas.

    .PARAMETER InputObject
        Allows piping from Get-DbaDatabase.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database, Schema
        Author: Adam Lancaster, github.com/lancasteradam

        dbatools PowerShell module (https://dbatools.io)
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbSchema

    .EXAMPLE
        PS C:\> Get-DbaDbSchema -SqlInstance localhost

        Gets all non-system database schemas from all user databases on the localhost instance. Note: the dbo schema is a system schema and won't be included in the output from this example. To include the dbo schema specify -IncludeSystemSchemas

    .EXAMPLE
        PS C:\> Get-DbaDbSchema -SqlInstance localhost -Schema dbo -IncludeSystemSchemas

        Returns the dbo schema from the databases on the localhost instance.

    .EXAMPLE
        PS C:\> Get-DbaDbSchema -SqlInstance localhost -IncludeSystemDatabases -IncludeSystemSchemas

        Gets all database schemas from all databases on the localhost instance.

    .EXAMPLE
        PS C:\> Get-DbaDbSchema -SqlInstance localhost -Schema TestSchema

        Finds and returns the TestSchema schema from the localhost instance.

    .EXAMPLE
        PS C:\> Get-DbaDbSchema -SqlInstance localhost -SchemaOwner DBUser1

        Finds and returns the schemas owned by DBUser1 from the localhost instance.

    .EXAMPLE
        PS C:\> Get-DbaDbSchema -SqlInstance localhost -Database TestDB -SchemaOwner DBUser1

        Finds and returns the schemas owned by DBUser1 in the TestDB database from the localhost instance.

    .EXAMPLE
        PS C:\> $schema = Get-DbaDbSchema -SqlInstance localhost -Database TestDB -Schema TestSchema
        PS C:\> $schema.Owner = DBUser2
        PS C:\> $schema.Alter()

        Finds the TestSchema in the TestDB on the localhost instance and then changes the schema owner to DBUser2

    .EXAMPLE
        PS C:\> $schema = Get-DbaDbSchema -SqlInstance localhost -Database TestDB -Schema TestSchema
        PS C:\> $schema.Drop()

        Finds the TestSchema in the TestDB on the localhost instance and then drops it. Note: to drop a schema all objects must be transferred to another schema or dropped.

    .EXAMPLE
        PS C:\> $db = Get-DbaDatabase -SqlInstance localhost -Database TestDB
        PS C:\> $schema = $db | Get-DbaDbSchema -Schema TestSchema

        Finds the TestSchema in the TestDB which is passed via pipeline into the Get-DbaDbSchema command.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$Schema,
        [string[]]$SchemaOwner,
        [switch]$IncludeSystemDatabases,
        [switch]$IncludeSystemSchemas,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    process {

        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database -ExcludeSystem:(-not $IncludeSystemDatabases)
        }

        foreach ($db in $InputObject) {
            $schemaList = $db.Schemas | Where-Object { ($_.IsSystemObject -eq $false) -or ($_.IsSystemObject -eq $IncludeSystemSchemas) } | Where-Object { ($_.Name -in $Schema) -or ($null -eq $Schema) } | Where-Object { ($_.Owner -in $SchemaOwner) -or ($null -eq $SchemaOwner) }

            foreach ($sch in $schemaList) {
                Add-Member -Force -InputObject $sch -MemberType NoteProperty -Name ComputerName -value $db.Parent.ComputerName
                Add-Member -Force -InputObject $sch -MemberType NoteProperty -Name InstanceName -value $db.Parent.ServiceName
                Add-Member -Force -InputObject $sch -MemberType NoteProperty -Name SqlInstance -value $db.Parent.DomainInstanceName
                Add-Member -Force -InputObject $sch -MemberType NoteProperty -Name DatabaseName -value $db.Name
                Add-Member -Force -InputObject $sch -MemberType NoteProperty -Name DatabaseId -value $db.Id
                Select-DefaultView -InputObject $sch -Property ComputerName, InstanceName, SqlInstance, Name, IsSystemObject
            }
        }
    }
}