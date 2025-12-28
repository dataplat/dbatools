function Get-DbaAgListener {
    <#
    .SYNOPSIS
        Retrieves availability group listener configurations including IP addresses and port numbers.

    .DESCRIPTION
        Retrieves availability group listener configurations from SQL Server instances, providing essential network details needed for client connections and troubleshooting. This function returns listener names, port numbers, IP configurations, and associated availability groups, which is crucial for validating listener setup and diagnosing connection issues. Use this when you need to document your AG infrastructure, verify listener configurations after setup, or troubleshoot client connectivity problems.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER AvailabilityGroup
        Specifies which availability groups to include when retrieving listener information. Supports wildcards for pattern matching.
        Use this when you only need listener details for specific availability groups rather than all groups on the instance.

    .PARAMETER Listener
        Specifies which availability group listeners to return by name. Accepts multiple listener names for filtering results.
        Use this when you need to examine specific listeners during troubleshooting or when documenting particular AG configurations.

    .PARAMETER InputObject
        Accepts availability group objects from Get-DbaAvailabilityGroup for pipeline operations.
        Use this when chaining commands to get listener details for specific availability groups you've already retrieved.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: AG, HA
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
        if (Test-Bound -Not SqlInstance, InputObject) {
            Stop-Function -Message "You must supply either -SqlInstance or an Input Object"
            return
        }

        if ($SqlInstance) {
            $InputObject += Get-DbaAvailabilityGroup -SqlInstance $SqlInstance -SqlCredential $SqlCredential -AvailabilityGroup $AvailabilityGroup -EnableException:$EnableException
        }

        $agListeners = $InputObject.AvailabilityGroupListeners
        if (Test-Bound -ParameterName Listener) {
            $agListeners = $agListeners | Where-Object { $Listener -contains $_.Name }
        }

        $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'AvailabilityGroup', 'Name', 'PortNumber', 'ClusterIPConfiguration'

        foreach ($agListener in $agListeners) {
            $server = $agListener.Parent.Parent
            Add-Member -Force -InputObject $agListener -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
            Add-Member -Force -InputObject $agListener -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
            Add-Member -Force -InputObject $agListener -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
            Add-Member -Force -InputObject $agListener -MemberType NoteProperty -Name AvailabilityGroup -value $agListener.Parent.Name
            Select-DefaultView -InputObject $agListener -Property $defaults
        }
    }
}