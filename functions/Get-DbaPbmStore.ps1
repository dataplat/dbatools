function Get-DbaPbmStore {
    <#
    .SYNOPSIS
        Returns the policy based management store.

    .DESCRIPTION
        Returns the policy based management store.

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
        By default system objects are filtered out. Use this parameter to include them.

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
        https://dbatools.io/Get-DbaPbmStore

    .EXAMPLE
        PS C:\> Get-DbaPbmStore -SqlInstance sql2016

        Return the policy store from the sql2016 instance

    .EXAMPLE
        PS C:\> Get-DbaPbmStore -SqlInstance sql2016 -SqlCredential $cred

        Uses a credential $cred to connect and return the policy store from the sql2016 instance

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {

            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
                $sqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $server.ConnectionContext.SqlConnectionObject
                # DMF is the Declarative Management Framework, Policy Based Management's old name
                $store = New-Object Microsoft.SqlServer.Management.DMF.PolicyStore $sqlStoreConnection
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            Add-Member -Force -InputObject $store -MemberType NoteProperty ComputerName -value $server.ComputerName
            Add-Member -Force -InputObject $store -MemberType NoteProperty InstanceName -value $server.ServiceName
            Add-Member -Force -InputObject $store -MemberType NoteProperty SqlInstance -value $server.DomainInstanceName

            Select-DefaultView -InputObject $store -ExcludeProperty SqlStoreConnection, ConnectionContext, Properties, Urn, Parent, DomainInstanceName, Metadata, IdentityKey, Name
        }
    }
}