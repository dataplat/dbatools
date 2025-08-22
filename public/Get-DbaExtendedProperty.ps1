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
        Get extended properties from specific database

    .PARAMETER Name
        Get specific extended properties by name

    .PARAMETER InputObject
        Enables piping from Get-Dba* commands

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
                $servername = $server.Query("SELECT @@servername as servername").servername

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