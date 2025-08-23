function Get-DbaPbmPolicy {
    <#
    .SYNOPSIS
        Retrieves Policy-Based Management policies from SQL Server instances for compliance auditing and configuration review.

    .DESCRIPTION
        Retrieves all Policy-Based Management policies configured on SQL Server instances, allowing DBAs to audit compliance configurations and review policy settings across their environment. This function connects to the PBM store and returns policy details including categories, conditions, and evaluation modes. Use this when you need to document existing policies, troubleshoot policy evaluations, or verify compliance configurations without manually navigating through SQL Server Management Studio's Policy-Based Management node.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Policy
        Specifies one or more policy names to retrieve, filtering the results to only those policies. Supports exact name matching for targeted policy retrieval.
        Use this when you need to examine specific policies rather than all policies on the instance.

    .PARAMETER Category
        Filters results to show only policies belonging to specific policy categories. Categories help organize policies by function or compliance framework.
        Use this to focus on policies related to specific areas like security, performance, or maintenance checks.

    .PARAMETER IncludeSystemObject
        Includes Microsoft's built-in system policies in the results, which are excluded by default. System policies cover standard SQL Server best practices.
        Use this when you need to review or document all policies including Microsoft's predefined compliance policies.

    .PARAMETER InputObject
        Accepts PBM store objects from Get-DbaPbmStore via pipeline, allowing efficient processing of multiple instances. Enables chaining PBM commands together.
        Use this when building complex PBM workflows or when you already have PBM store objects from previous commands.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Policy, PolicyBasedManagement, PBM
        Author: Stephen Bennett, sqlnotesfromtheunderground.wordpress.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaPbmPolicy

    .EXAMPLE
        PS C:\> Get-DbaPbmPolicy -SqlInstance sql2016

        Returns all policies from sql2016 server

    .EXAMPLE
        PS C:\> Get-DbaPbmPolicy -SqlInstance sql2016 -SqlCredential $cred

        Uses a credential $cred to connect and return all policies from sql2016 instance

    .EXAMPLE
        PS C:\> Get-DbaPbmPolicy -SqlInstance sql2016 -Category MorningCheck

        Returns all policies from sql2016 server that part of the PolicyCategory MorningCheck

    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Policy,
        [string[]]$Category,
        [parameter(ValueFromPipeline)]
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
            $allpolicies = $store.Policies

            if (-not $IncludeSystemObject) {
                $allpolicies = $allpolicies | Where-Object IsSystemObject -eq $false
            }

            if ($Category) {
                $allpolicies = $allpolicies | Where-Object PolicyCategory -in $Category
            }

            if ($Policy) {
                $allpolicies = $allpolicies | Where-Object Name -in $Policy
            }

            foreach ($currentpolicy in $allpolicies) {
                Write-Message -Level Verbose -Message "Processing $currentpolicy"
                Add-Member -Force -InputObject $currentpolicy -MemberType NoteProperty ComputerName -value $store.ComputerName
                Add-Member -Force -InputObject $currentpolicy -MemberType NoteProperty InstanceName -value $store.InstanceName
                Add-Member -Force -InputObject $currentpolicy -MemberType NoteProperty SqlInstance -value $store.SqlInstance

                Select-DefaultView -InputObject $currentpolicy -ExcludeProperty HelpText, HelpLink, Urn, Properties, Metadata, Parent, IdentityKey, HasScript, PolicyEvaluationStarted, ConnectionProcessingStarted, TargetProcessed, ConnectionProcessingFinished, PolicyEvaluationFinished, PropertyMetadataChanged, PropertyChanged
            }
        }
    }
}