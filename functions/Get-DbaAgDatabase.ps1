#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Get-DbaAgDatabase {
<#
    .SYNOPSIS
        Outputs the databases involved in the Availability Group(s) found on the server.

    .DESCRIPTION
        Default view provides most common set of properties for information on the database in an Availability Group(s).

        Information returned on the database will be specific to that replica, whether it is primary or a secondary.

        This command will return an SMO object, but it is the AvailabilityDatabases object and not the Server.Databases object.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the SqlInstance instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)
    
    .PARAMETER AvailabilityGroup
        Specify the availability groups to query.

    .PARAMETER Database
        Specify the database or databases to return. This list is auto-populated from the server for tab completion. Multiple databases can be specified. If none are specified all databases will be processed.

    .PARAMETER InputObject
        Enables piped input from Get-DbaAvailabilityGroup
    
    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Hadr, HA, AG, AvailabilityGroup, Replica
        Author: Shawn Melton (@wsmelton), https://wsmelton.github.io

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaAgDatabase

    .EXAMPLE
        PS C:\> Get-DbaAgDatabase -SqlInstance sql2017a

        Returns basic information on all the databases in each availability group found on sql2017a

    .EXAMPLE
        PS C:\> Get-DbaAgDatabase -SqlInstance sql2017a -AvailabilityGroup AG101

        Returns basic information on all the databases in the availability group AG101 on sql2017a

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sqlcluster -AvailabilityGroup SharePoint -Database Sharepoint_Config | Get-DbaAgDatabase

        Returns basic information on the database Sharepoint_Config found in the availability group SharePoint on server sqlcluster

#>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$AvailabilityGroup,
        [string[]]$Database,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]]$InputObject,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaAvailabilityGroup -SqlInstance $instance -SqlCredential $SqlCredential -AvailabilityGroup $AvailabilityGroup
        }
        
        if (Test-Bound -ParameterName Database) {
            $InputObject = $InputObject | Where-Object { $_.AvailabilityDatabases.Name -contains $Listener }
        }
        
        foreach ($ag in $InputObject.AvailabilityDatabases) {
            $server = $ag.Parent.Parent
            foreach ($db in $dbs) {
                Add-Member -Force -InputObject $db -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                Add-Member -Force -InputObject $db -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                Add-Member -Force -InputObject $db -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                Add-Member -Force -InputObject $db -MemberType NoteProperty -Name Replica -value $server.ComputerName
                
                $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'Parent as AvailabilityGroup', 'Replica', 'Name as DatabaseName', 'SynchronizationState', 'IsFailoverReady', 'IsJoined', 'IsSuspended'
                Select-DefaultView -InputObject $db -Property $defaults
            }
        }
    }
}