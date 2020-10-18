function Get-DbaAgReplica {
    <#
    .SYNOPSIS
        Returns the availability group replica object found on the server.

    .DESCRIPTION
        Returns the availability group replica object found on the server.

   .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER AvailabilityGroup
        Specify the availability groups to query.

    .PARAMETER Replica
        Return only specific replicas.

    .PARAMETER InputObject
        Enables piped input from Get-DbaAvailabilityGroup.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: AvailabilityGroup, HA, AG
        Author: Shawn Melton (@wsmelton) | Chrissy LeMaire (@cl)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaAgReplica

    .EXAMPLE
        PS C:\> Get-DbaAgReplica -SqlInstance sql2017a

        Returns basic information on all the availability group replicas found on sql2017a

    .EXAMPLE
        PS C:\> Get-DbaAgReplica -SqlInstance sql2017a -AvailabilityGroup SharePoint

        Shows basic information on the replicas found on availability group SharePoint on sql2017a

    .EXAMPLE
        PS C:\> Get-DbaAgReplica -SqlInstance sql2017a | Select-Object *

        Returns full object properties on all availability group replicas found on sql2017a
    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$AvailabilityGroup,
        [string[]]$Replica,
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

        $availabilityReplicas = $InputObject.AvailabilityReplicas
        if ($Replica) {
            $availabilityReplicas = $InputObject.AvailabilityReplicas | Where-Object { $_.Name -in $Replica }
        }

        $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'AvailabilityGroup', 'Name', 'Role', 'ConnectionState', 'RollupSynchronizationState', 'AvailabilityMode', 'BackupPriority', 'EndpointUrl', 'SessionTimeout', 'FailoverMode', 'ReadonlyRoutingList'

        foreach ($agreplica in $availabilityReplicas) {
            Add-Member -Force -InputObject $agreplica -MemberType NoteProperty -Name ComputerName -value $agreplica.Parent.ComputerName
            Add-Member -Force -InputObject $agreplica -MemberType NoteProperty -Name InstanceName -value $agreplica.Parent.InstanceName
            Add-Member -Force -InputObject $agreplica -MemberType NoteProperty -Name SqlInstance -value $agreplica.Parent.SqlInstance
            Add-Member -Force -InputObject $agreplica -MemberType NoteProperty -Name AvailabilityGroup -value $agreplica.Parent.Name
            Add-Member -Force -InputObject $agreplica -MemberType NoteProperty -Name Replica -value $agreplica.Name # backwards compat

            Select-DefaultView -InputObject $agreplica -Property $defaults
        }
    }
}