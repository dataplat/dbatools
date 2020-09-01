function Get-DbaPbmPolicy {
    <#
    .SYNOPSIS
        Returns policies from Policy-Based Management from an instance.

    .DESCRIPTION
        Returns details of policies with the option to filter on Category and SystemObjects.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Policy
        Filters results to only show specific policy

    .PARAMETER Category
        Filters results to only show policies in the category selected

    .PARAMETER IncludeSystemObject
        By default system objects are filtered out. Use this parameter to INCLUDE them .

    .PARAMETER InputObject
        Allows piping from Get-DbaPbmStore

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Policy, PolicyBasedManagement, PBM
        Author: Stephen Bennett, https://sqlnotesfromtheunderground.wordpress.com/

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
        [Microsoft.SqlServer.Management.Dmf.PolicyStore[]]$InputObject,
        [switch]$IncludeSystemObject,
        [switch]$EnableException
    )
    process {
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