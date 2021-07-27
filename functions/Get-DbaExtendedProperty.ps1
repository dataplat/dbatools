function Get-DbaExtendedProperty {
    <#
    .SYNOPSIS
        Gets extended properties

    .DESCRIPTION
        Gets extended properties

        This command works out of the box with databases but you can add or get extended properties from any object. Just pipe it in it'll grab the properties and print them out.

        You can get extended properties on all these different types of objects:

        Aggregate
        Assembly
        Column
        Constraint
        Contract
        Database
        Event Notification
        Filegroup
        Function
        Index
        Logical File Name
        Message Type
        Parameter
        Partition Function
        Partition Scheme
        Procedure
        Queue
        Remote Service Binding
        Route
        Rule
        Schema
        Service
        Synonym
        Table
        Trigger
        Type
        View
        Xml Schema Collection

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
        Enables piping from Get-DbaDatabase

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: extended properties
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
                $server = Get-ServerParent $object
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
                Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name Parent -Value $object.Name
                Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name Type -Value $object.GetType().Name

                Select-DefaultView -InputObject $prop -Property ComputerName, InstanceName, SqlInstance, Parent, Type, Name, Value
            }
        }
    }
}