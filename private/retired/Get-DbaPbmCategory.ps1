function Get-DbaPbmCategory {
    <#
    .SYNOPSIS
        Retrieves Policy-Based Management categories from SQL Server instances for governance and compliance management.

    .DESCRIPTION
        Retrieves all policy categories configured in SQL Server's Policy-Based Management (PBM) feature. Policy categories help organize and group related policies for easier management and selective enforcement across database environments. This function allows DBAs to inventory existing categories, audit category assignments, and understand which categories mandate database subscriptions for automatic policy evaluation.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Category
        Filters results to only show specific policy categories by name. Accepts multiple category names for targeted retrieval.
        Use this when you need to check specific categories rather than retrieving all configured PBM categories.

    .PARAMETER ExcludeSystemObject
        Excludes built-in system policy categories from the results, showing only user-created categories.
        Use this when you want to focus on custom categories that you or your team have created, filtering out SQL Server's default categories.

    .PARAMETER InputObject
        Accepts Policy-Based Management store objects from Get-DbaPbmStore for processing categories from specific stores.
        Use this when you need to work with categories from a pre-filtered set of PBM stores or when chaining multiple PBM commands together.

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

    .OUTPUTS
        Microsoft.SqlServer.Management.Sdk.Sfc.ISfcInstance

        Returns one policy category object per category found on the target PBM store(s). Each category object includes connection context properties and policy category metadata.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Id: The unique identifier for the policy category
        - Name: The name of the policy category
        - MandateDatabaseSubscriptions: Boolean indicating if databases must be subscribed to this category for automatic policy evaluation

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