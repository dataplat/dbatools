function Get-DbaPbmCategory {
    <#
    .SYNOPSIS
        Returns policy categories from policy based management from an instance.

    .DESCRIPTION
        Returns policy categories from policy based management from an instance.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Category
        Filters results to only show specific condition

    .PARAMETER ExcludeSystemObject
        By default system objects are include. Use this parameter to exclude them.

    .PARAMETER InputObject
        Allows piping from Get-DbaPbmStore

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Policy, PolicyBasedManagement, PBM
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaPbmCategory

    .EXAMPLE
        PS C:\> Get-DbaPbmCategory -SqlInstance sql2016

        Returns all policy categories from the sql2016 PBM server

    .EXAMPLE
        PS C:\> Get-DbaPbmCategory -SqlInstance sql2016 -SqlCredential $cred

        Uses a credential $cred to connect and return all policy categories from the sql2016 PBM server

    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Category,
        [Parameter(ValueFromPipeline)]
        [psobject[]]$InputObject,
        [switch]$ExcludeSystemObject,
        [switch]$EnableException
    )
    begin {
        Add-PbmLibrary
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaPbmStore -SqlInstance $instance -SqlCredential $SqlCredential
        }
        foreach ($store in $InputObject) {
            $all = $store.PolicyCategories

            if (-not $ExcludeSystemObject) {
                $all = $all | Where-Object IsSystemObject -ne $true
            }

            if ($Category) {
                $all = $all | Where-Object Name -in $Category
            }

            foreach ($current in $all) {
                Write-Message -Level Verbose -Message "Processing $current"
                Add-Member -Force -InputObject $current -MemberType NoteProperty ComputerName -value $store.ComputerName
                Add-Member -Force -InputObject $current -MemberType NoteProperty InstanceName -value $store.InstanceName
                Add-Member -Force -InputObject $current -MemberType NoteProperty SqlInstance -value $store.SqlInstance
                Select-DefaultView -InputObject $current -Property ComputerName, InstanceName, SqlInstance, Id, Name, MandateDatabaseSubscriptions
            }
        }
    }
}