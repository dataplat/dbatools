function Get-DbaAgListener {
    <#
    .SYNOPSIS
        Returns availability group listeners.

    .DESCRIPTION
        Returns availability group listeners.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER AvailabilityGroup
        Specify the availability groups to query.

    .PARAMETER Listener
        Return only specific listeners.

    .PARAMETER InputObject
        Enables piped input from Get-DbaAvailabilityGroup.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: AvailabilityGroup, HA, AG
        Author: Viorel Ciucu (@viorelciucu)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaAgListener

    .EXAMPLE
        PS C:\> Get-DbaAgListener -SqlInstance sql2017a

        Returns all listeners found on sql2017a

    .EXAMPLE
        PS C:\> Get-DbaAgListener -SqlInstance sql2017a -AvailabilityGroup AG-a

        Returns all listeners found on sql2017a on sql2017a for the availability group AG-a

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sql2017a -AvailabilityGroup OPP | Get-DbaAgListener

        Returns all listeners found on sql2017a on sql2017a for the availability group OPP
    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$AvailabilityGroup,
        [string[]]$Listener,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ($SqlInstance) {
            $InputObject += Get-DbaAvailabilityGroup -SqlInstance $SqlInstance -SqlCredential $SqlCredential -AvailabilityGroup $AvailabilityGroup
        }

        if (Test-Bound -ParameterName Listener) {
            $InputObject = $InputObject | Where-Object { $_.AvailabilityGroupListeners.Name -contains $Listener }
        }

        $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'AvailabilityGroup', 'Name', 'PortNumber', 'ClusterIPConfiguration'

        foreach ($aglistener in $InputObject.AvailabilityGroupListeners) {
            $server = $aglistener.Parent.Parent
            Add-Member -Force -InputObject $aglistener -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
            Add-Member -Force -InputObject $aglistener -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
            Add-Member -Force -InputObject $aglistener -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
            Add-Member -Force -InputObject $aglistener -MemberType NoteProperty -Name AvailabilityGroup -value $aglistener.Parent.Name
            Select-DefaultView -InputObject $aglistener -Property $defaults
        }
    }
}