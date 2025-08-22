function Get-DbaAgDatabase {
    <#
    .SYNOPSIS
        Retrieves availability group database information and synchronization status from SQL Server instances.

    .DESCRIPTION
        Retrieves detailed information about databases participating in SQL Server availability groups, including their synchronization state, failover readiness, and replica-specific status. This function queries the availability group configuration from each SQL Server instance to return database-level health and status information that varies depending on whether the replica is primary or secondary. 
        
        Use this command to monitor availability group database health, troubleshoot synchronization issues, verify failover readiness, or generate compliance reports showing which databases are properly synchronized across your availability group replicas. The returned data includes critical operational details like suspension status, join state, and synchronization health that help DBAs quickly identify databases requiring attention.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER AvailabilityGroup
        Specify the availability groups to query.

    .PARAMETER Database
        Specify the database or databases to return. This list is auto-populated from the server for tab completion. Multiple databases can be specified. If none are specified all databases will be processed.

    .PARAMETER InputObject
        Enables piped input from Get-DbaAvailabilityGroup.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: AG, HA
        Author: Shawn Melton (@wsmelton), wsmelton.github.io

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaAgDatabase

    .EXAMPLE
        PS C:\> Get-DbaAgDatabase -SqlInstance sql2017a

        Returns all the databases in each availability group found on sql2017a

    .EXAMPLE
        PS C:\> Get-DbaAgDatabase -SqlInstance sql2017a -AvailabilityGroup AG101

        Returns all the databases in the availability group AG101 on sql2017a

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sqlcluster -AvailabilityGroup SharePoint | Get-DbaAgDatabase -Database Sharepoint_Config

        Returns the database Sharepoint_Config found in the availability group SharePoint on server sqlcluster
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
        if (Test-Bound -Not SqlInstance, InputObject) {
            Stop-Function -Message "You must supply either -SqlInstance or an Input Object"
            return
        }

        if ($SqlInstance) {
            $InputObject += Get-DbaAvailabilityGroup -SqlInstance $SqlInstance -SqlCredential $SqlCredential -AvailabilityGroup $AvailabilityGroup
        }

        foreach ($db in $InputObject.AvailabilityDatabases) {
            if ($Database) {
                if ($db.Name -notin $Database) { continue }
            }
            $ag = $db.Parent
            $server = $db.Parent.Parent
            Add-Member -Force -InputObject $db -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
            Add-Member -Force -InputObject $db -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
            Add-Member -Force -InputObject $db -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
            Add-Member -Force -InputObject $db -MemberType NoteProperty -Name AvailabilityGroup -Value $ag.Name
            Add-Member -Force -InputObject $db -MemberType NoteProperty -Name LocalReplicaRole -Value $ag.LocalReplicaRole

            $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'AvailabilityGroup', 'LocalReplicaRole', 'Name', 'SynchronizationState', 'IsFailoverReady', 'IsJoined', 'IsSuspended'
            Select-DefaultView -InputObject $db -Property $defaults
        }
    }
}