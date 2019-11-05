function Get-DbaRgResourcePool {
    <#
    .SYNOPSIS
        Gets Resource Governor Pool objects, including internal or external

    .DESCRIPTION
        Gets Resource Governor Pool objects, including internal or external

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER InputObject
        Allows input to be piped from Get-DbaResourceGovernor

    .PARAMETER Type
        Internal or External

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: ResourceGovernor
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaRgResourcePool

    .EXAMPLE
        PS C:\> Get-DbaRgResourcePool -SqlInstance sql2016

        Gets the internal resource pools on sql2016

    .EXAMPLE
        PS C:\> 'Sql1','Sql2/sqlexpress' | Get-DbaResourceGovernor | Get-DbaRgResourcePool

        Gets the internal resource pools on Sql1 and Sql2/sqlexpress instances

    .EXAMPLE
        PS C:\> 'Sql1','Sql2/sqlexpress' | Get-DbaResourceGovernor | Get-DbaRgResourcePool -Type External

        Gets the external resource pools on Sql1 and Sql2/sqlexpress instances


    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [ValidateSet("Internal", "External")]
        [string]$Type = "Internal",
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.ResourceGovernor[]]$InputObject,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaResourceGovernor -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        }

        foreach ($resourcegov in $InputObject) {
            if ($Type -eq "External") {
                $respool = $resourcegov.ExternalResourcePools
                if ($respool) {
                    $respool | Add-Member -Force -MemberType NoteProperty -Name ComputerName -value $resourcegov.ComputerName
                    $respool | Add-Member -Force -MemberType NoteProperty -Name InstanceName -value $resourcegov.InstanceName
                    $respool | Add-Member -Force -MemberType NoteProperty -Name SqlInstance -value $resourcegov.SqlInstance
                    $respool | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Id, Name, CapCpuPercentage, IsSystemObject, MaximumCpuPercentage, MaximumIopsPerVolume, MaximumMemoryPercentage, MinimumCpuPercentage, MinimumIopsPerVolume, MinimumMemoryPercentage, WorkloadGroups
                }
            } else {
                $respool = $resourcegov.ResourcePools
                if ($respool) {
                    $respool | Add-Member -Force -MemberType NoteProperty -Name ComputerName -value $resourcegov.ComputerName
                    $respool | Add-Member -Force -MemberType NoteProperty -Name InstanceName -value $resourcegov.InstanceName
                    $respool | Add-Member -Force -MemberType NoteProperty -Name SqlInstance -value $resourcegov.SqlInstance
                    $respool | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Id, Name, CapCpuPercentage, IsSystemObject, MaximumCpuPercentage, MaximumIopsPerVolume, MaximumMemoryPercentage, MinimumCpuPercentage, MinimumIopsPerVolume, MinimumMemoryPercentage, WorkloadGroups
                }
            }
        }
    }
}