function Add-DbaExtendedProperty {
    <#
    .SYNOPSIS
        Adds extended properties to SQL Server objects for metadata storage and documentation

    .DESCRIPTION
        Creates custom metadata properties on SQL Server objects to store documentation, version information, business context, or compliance tags. Extended properties are stored in the database system catalogs and don't affect object performance but provide valuable context for DBAs managing complex environments.

        This command accepts piped input from any dbatools Get-Dba* command, making it easy to bulk-apply properties across multiple objects. You can add extended properties to databases directly or target specific object types, including:

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
        Specifies which databases to target when adding extended properties directly to database objects. Accepts wildcards for pattern matching.
        Use this when you want to add metadata to entire databases rather than piping specific objects from Get-Dba* commands.

    .PARAMETER Name
        Sets the name identifier for the extended property being created. Must be unique per object.
        Common examples include "Version", "Owner", "Purpose", "DataClassification", or "LastModified" for documentation and compliance tracking.

    .PARAMETER Value
        Defines the content stored in the extended property as a string value. Can contain any text including version numbers, descriptions, dates, or JSON data.
        Keep values concise as they're stored in system catalogs and are visible in SQL Server Management Studio object properties.

    .PARAMETER InputObject
        Accepts SQL Server objects from any Get-Dba* command that supports extended properties. Works with tables, views, procedures, functions, and many other object types.
        This is the primary method for bulk-applying extended properties across multiple objects in your database environment.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

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
        https://dbatools.io/Add-DbaExtendedProperty

    .EXAMPLE
        PS C:\> Add-DbaExtendedProperty -SqlInstance Server1 -Database db1 -Name version -Value "1.0.0"

        Sets the version extended property for the db1 database to 1.0.0

    .EXAMPLE
        PS C:\> Get-DbaDbStoredProcedure -SqlInstance localhost -Database tempdb | Add-DbaExtendedProperty -Name SPVersion -Value 10.2

        Creates an extended property for all stored procedures in the tempdb database named SPVersion with a value of 10.2

    .EXAMPLE
        PS C:\> Get-DbaDbTable -SqlInstance localhost -Database mydb -Table mytable | Add-DbaExtendedProperty -Name MyExtendedProperty -Value "This is a test"

        Creates an extended property named MyExtendedProperty for the mytable table in the mydb, with a value of "This is a test"
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [parameter(Mandatory)]
        [Alias("Property")]
        [string]$Name,
        [parameter(Mandatory)]
        [string]$Value,
        [parameter(ValueFromPipeline)]
        [psobject[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ($SqlInstance) {
            $InputObject = Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database | Where-Object IsAccessible
        }

        foreach ($object in $InputObject) {
            try {
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

                if ($Pscmdlet.ShouldProcess($object.Name, "Adding an extended propernamed named $Name with a value of '$Value'")) {
                    $prop = New-Object Microsoft.SqlServer.Management.Smo.ExtendedProperty ($object, $Name, $Value)
                    $prop.Create()
                    Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name ComputerName -Value $computername
                    Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name InstanceName -Value $instancename
                    Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name SqlInstance -Value $sqlname
                    Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name ParentName -Value $object.Name
                    Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name Type -Value $object.GetType().Name
                    Add-Member -Force -InputObject $prop -MemberType NoteProperty -Name Server -Value $server

                    Select-DefaultView -InputObject $prop -Property ComputerName, InstanceName, SqlInstance, ParentName, Type, Name, Value
                }
            } catch {
                Stop-Function -Message "Failed to add extended property $Name with a value of '$Value' to $($object.Name)" -ErrorRecord $_
            }
        }
    }
}