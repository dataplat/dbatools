function Get-DbaPolicy {
    <#
    .SYNOPSIS
    Returns polices from policy based management from an instance.

    .DESCRIPTION
    Returns details of policies with the option to filter on Category and SystemObjects.

    .PARAMETER SqlInstance
    SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
    Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER Policy
    Filters results to only show specific policy

    .PARAMETER Category
    Filters results to only show policies in the category selected

    .PARAMETER IncludeSystemObject
    By default system objects are filtered out. Use this parameter to INCLUDE them .

    .PARAMETER EnableException
    By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
    Author: Stephen Bennett (https://sqlnotesfromtheunderground.wordpress.com/)
    Tags: Policy, PoilcyBasedManagement

    Website: https://dbatools.io
    Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
    License: MIT https://opensource.org/licenses/MIT

    .LINK
    https://dbatools.io/Get-DbaPolicy

    .EXAMPLE
    Get-DbaPolicy -SqlInstance sql2016

    Returns all policies from sql2016 server

    .EXAMPLE
    Get-DbaPolicy -SqlInstance sql2016 -SqlCredential $cred

    Uses a credential $cred to connect and return all policies from sql2016 instance

    .EXAMPLE
    Get-DbaPolicy -SqlInstance sql2016 -Category MorningCheck

    Returns all policies from sql2016 server that part of the PolicyCategory MorningCheck
#>
    [CmdletBinding()]
    param (
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential][System.Management.Automation.CredentialAttribute()]
        $SqlCredential,
        [string[]]$Policy,
        [string[]]$Category,
        [switch]$IncludeSystemObject,
        [Alias('Silent')]
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Attempting to connect to $instance"

            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                $sqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $server.ConnectionContext.SqlConnectionObject
                # DMF is the Declarative Management Framework, Policy Based Management's old name
                $store = New-Object Microsoft.SqlServer.Management.DMF.PolicyStore $sqlStoreConnection
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $server -Continue
            }

            $allpolicies = $store.Policies

            if (-not $IncludeSystemObject) {
                $allpolicies = $allpolicies | Where-Object { $_.IsSystemObject -eq 0 }
            }

            if ($Category) {
                $allpolicies = $allpolicies | Where-Object { $_.PolicyCategory -in $Category }
            }

            if ($Policy) {
                $allpolicies = $allpolicies | Where-Object { $_.Name -in $Policy }
            }

            foreach ($currentpolicy in $allpolicies) {
                Write-Message -Level Verbose -Message "Processing $currentpolicy"
                Add-Member -Force -InputObject $currentpolicy -MemberType NoteProperty ComputerName -value $server.NetName
                Add-Member -Force -InputObject $currentpolicy -MemberType NoteProperty InstanceName -value $server.ServiceName
                Add-Member -Force -InputObject $currentpolicy -MemberType NoteProperty SqlInstance -value $server.DomainInstanceName

                Select-DefaultView -InputObject $currentpolicy -ExcludeProperty HelpText, HelpLink, Urn, Properties, Metadata, Parent, IdentityKey, HasScript, PolicyEvaluationStarted, ConnectionProcessingStarted, TargetProcessed, ConnectionProcessingFinished, PolicyEvaluationFinished, PropertyMetadataChanged, PropertyChanged
            }
        }
    }
}
