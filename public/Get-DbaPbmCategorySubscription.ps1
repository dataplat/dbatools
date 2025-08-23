function Get-DbaPbmCategorySubscription {
    <#
    .SYNOPSIS
        Retrieves database subscriptions to Policy-Based Management categories that control automatic policy evaluation.

    .DESCRIPTION
        Retrieves all database subscriptions to policy categories from SQL Server's Policy-Based Management feature. These subscriptions determine which databases are subject to automatic policy evaluation for specific policy categories. When a database subscribes to a category (either voluntarily or through mandatory subscription), all policies in that category will be automatically evaluated against the database. This is essential for auditing policy compliance, troubleshooting evaluation failures, and understanding which databases are governed by which policy sets.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER InputObject
        Accepts Policy-Based Management store objects from Get-DbaPbmStore for pipeline processing.
        Use this when you need to query category subscriptions from an already retrieved PBM store object, improving performance when working with multiple PBM operations on the same instance.

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
        https://dbatools.io/Get-DbaPbmCategorySubscription

    .EXAMPLE
        PS C:\> Get-DbaPbmCategorySubscription -SqlInstance sql2016

        Returns all policy category subscriptions from the sql2016 PBM server

    .EXAMPLE
        PS C:\> Get-DbaPbmCategorySubscription -SqlInstance sql2016 -SqlCredential $cred

        Uses a credential $cred to connect and return all policy category subscriptions from the sql2016 PBM server

    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Parameter(ValueFromPipeline)]
        [psobject[]]$InputObject,
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
            $all = $store.PolicycategorySubscriptions

            foreach ($current in $all) {
                Write-Message -Level Verbose -Message "Processing $current"
                Add-Member -Force -InputObject $current -MemberType NoteProperty ComputerName -value $store.ComputerName
                Add-Member -Force -InputObject $current -MemberType NoteProperty InstanceName -value $store.InstanceName
                Add-Member -Force -InputObject $current -MemberType NoteProperty SqlInstance -value $store.SqlInstance
                Select-DefaultView -InputObject $current -ExcludeProperty Properties, Urn, Parent
            }
        }
    }
}