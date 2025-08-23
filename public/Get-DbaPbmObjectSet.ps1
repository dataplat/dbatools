function Get-DbaPbmObjectSet {
    <#
    .SYNOPSIS
        Retrieves Policy-Based Management object sets from SQL Server instances

    .DESCRIPTION
        Retrieves object sets from SQL Server's Policy-Based Management (PBM) feature, which define collections of SQL Server objects that policies can target for compliance monitoring. Object sets group related database objects like tables, stored procedures, or views based on specific criteria, allowing you to apply policies consistently across similar objects. This is essential for DBAs implementing standardized configurations and compliance rules across multiple databases and instances.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER ObjectSet
        Specifies the name(s) of specific Policy-Based Management object sets to retrieve. Accepts multiple values and supports wildcards.
        Use this when you need to examine particular object sets rather than retrieving all available sets from the instance.

    .PARAMETER IncludeSystemObject
        Includes SQL Server system object sets in the results, which are excluded by default to focus on user-defined sets.
        Use this when you need to audit or examine Microsoft's built-in Policy-Based Management object sets for compliance or educational purposes.

    .PARAMETER InputObject
        Accepts Policy-Based Management store objects from Get-DbaPbmStore via pipeline input for processing multiple stores.
        Use this when you need to process object sets from multiple SQL Server instances or when chaining PBM commands together.

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
        https://dbatools.io/Get-DbaPbmObjectSet

    .EXAMPLE
        PS C:\> Get-DbaPbmObjectSet -SqlInstance sql2016

        Returns all object sets from the sql2016 PBM instance

    .EXAMPLE
        PS C:\> Get-DbaPbmObjectSet -SqlInstance sql2016 -SqlCredential $cred

        Uses a credential $cred to connect and return all object sets from the sql2016 PBM instance

    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$ObjectSet,
        [Parameter(ValueFromPipeline)]
        [psobject[]]$InputObject,
        [switch]$IncludeSystemObject,
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
            $all = $store.ObjectSets

            if (-not $IncludeSystemObject) {
                $all = $all | Where-Object IsSystemObject -eq $false
            }

            if ($ObjectSet) {
                $all = $all | Where-Object Name -in $ObjectSet
            }

            foreach ($currentset in $all) {
                Write-Message -Level Verbose -Message "Processing $currentset"
                Add-Member -Force -InputObject $currentset -MemberType NoteProperty ComputerName -value $store.ComputerName
                Add-Member -Force -InputObject $currentset -MemberType NoteProperty InstanceName -value $store.InstanceName
                Add-Member -Force -InputObject $currentset -MemberType NoteProperty SqlInstance -value $store.SqlInstance
                Select-DefaultView -InputObject $currentset -Property ComputerName, InstanceName, SqlInstance, Id, Name, Facet, TargetSets, IsSystemObject
            }
        }
    }
}