function Test-DbaAvailabilityGroup {
    <#
    .SYNOPSIS
        Evaluates the health of an availability group.

    .DESCRIPTION
        This function evaluates the health of an availability group. This function evaluates SQL Server policy-based management policies.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER AvailabilityGroup
        Return only specific availability groups.

    .PARAMETER AllowUserPolicies

        Indicates that this function tests user policies found in the policy categories of Always On Availability Groups.

    .PARAMETER ShowPolicyDetails

        Indicates that this function displays the result of each policy evaluation that it performs. The function returns one object per policy evaluation. Each policy object includes the results of evaluation. This information includes
        whether the policy passed or not, the policy name, and policy category.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Hadr, HA, AG, AvailabilityGroup
        Author: IJeb Reitsma

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaAvailabilityGroup

    .EXAMPLE

        PS C:\> Test-DbaAvailabilityGroup -SqlInstance sqlserver-0

        Returns the health state on all the Availability Group(s) found on sqlserver-0.

        PS C:\> Test-DbaAvailabilityGroup -SqlInstance sqlserver-0 -AvailabilityGroup test-ag

        Returns the health state on the Availability Group test-ag on sqlserver-0.

        PS C:\> Test-DbaAvailabilityGroup -SqlInstance sqlserver-0 -AvailabilityGroup test-ag -ShowPolicyDetails

        Returns the health state on the Availability Group test-ag on sqlserver-0. Include detailed results.

        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sqlserver-0 | Test-DbaAvailabilityGroup

        Returns the health state on all the Availability Group(s) found on sqlserver-0.

        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sqlserver-0 -AvailabilityGroup test-ag | Test-DbaAvailabilityGroup

        Returns the health state on the Availability Group test-ag on sqlserver-0.

    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$AvailabilityGroup,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]]$InputObject,
        [switch]$AllowUserPolicies,
        [switch]$ShowPolicyDetails,
        [switch]$EnableException
    )
    process {

        if ($SqlInstance) {
            $InputObject += Get-DbaAvailabilityGroup -SqlInstance $SqlInstance -SqlCredential $SqlCredential -AvailabilityGroup $AvailabilityGroup
        }

        foreach ($ag in $InputObject) {
            $results = Test-SqlAvailabilityGroup -Path ($ag.Urn | Convert-UrnToPath) -AllowUserPolicies:$AllowUserPolicies -ShowPolicyDetails:$ShowPolicyDetails
            foreach ($result in $results) {
                Add-Member -Force -InputObject $result -MemberType NoteProperty -Name ComputerName -value $ag.ComputerName
                Add-Member -Force -InputObject $result -MemberType NoteProperty -Name InstanceName -value $ag.InstanceName
                Add-Member -Force -InputObject $result -MemberType NoteProperty -Name SqlInstance -value $ag.SqlInstance
                if (-not $ShowPolicyDetails) {
                    $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'HealthState', 'Name'
                    Select-Object -InputObject $result -Property $defaults
                }
                else {
                    $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'Result', 'TargetObject', 'Category', 'Name'
                    Select-Object -InputObject $result -Property $defaults
                }
            }
        }
    }
}
