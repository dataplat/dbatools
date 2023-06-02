function Get-DbaReplSubscription {
    <#
    .SYNOPSIS
        Displays all subscriptions for a publication.

    .DESCRIPTION
        Displays all subscriptions for a publication

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER Database
        The database(s) to process. If unspecified, all databases will be processed.

    .PARAMETER Name
        The name of the publication.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Type
        Limit by specific type of publication. Valid choices include: Transactional, Merge, Snapshot

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Replication
        Author: Jess Pomfret (@jpomfret), jesspomfret.com

        Website: https://dbatools.io
        Copyright: (c) 2023 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaReplSubscription

    .EXAMPLE
        PS C:\> #TODO: add example

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [object[]]$Database,
        [PSCredential]$SqlCredential,
        [String]$Name,
        [Alias("PublicationType")]
        [ValidateSet("Push","Pull")]
        [object[]]$Type,
        [switch]$EnableException
    )
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($instance in $SqlInstance) {

            # Connect to Publisher
            try {
                $replServer = Get-DbaReplServer -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # Get all subscriptions
            $transSub = New-Object Microsoft.SqlServer.Replication.TransSubscription
            $transSub.ConnectionContext = $replServer.ConnectionContext
            $transSub.EnumSubscriptions()


            #TODO: finish this function
            # can we get subscriptions by passing in subscription server mssql2 ... or do we need to start at the publisher
            # get-publications --> subscriptions info is in there


        }
    }
}