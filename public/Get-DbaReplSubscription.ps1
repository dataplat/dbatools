function Get-DbaReplSubscription {
    <#
    .SYNOPSIS
        Retrieves SQL Server replication subscription details for publications across instances.

    .DESCRIPTION
        Retrieves detailed information about replication subscriptions, showing which subscriber instances are receiving data from publications. This is essential for monitoring replication topology, troubleshooting subscription issues, and auditing data distribution across your SQL Server environment. You can filter results by database, publication name, subscriber instance, subscription database, or subscription type (Push/Pull) to focus on specific replication relationships.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process. If unspecified, all databases will be processed.

    .PARAMETER PublicationName
        The name of the publication.

    .PARAMETER SubscriberName
        The subscriber SQL Server instance name.

    .PARAMETER SubscriptionDatabase
        The name of the subscription database.

    .PARAMETER Type
        Limit by specific type of publication. Valid choices include: Transactional, Merge, Snapshot

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: repl, Replication
        Author: Jess Pomfret (@jpomfret), jesspomfret.com

        Website: https://dbatools.io
        Copyright: (c) 2023 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaReplSubscription

    .EXAMPLE
        PS C:\> Get-DbaReplSubscription -SqlInstance mssql1

        Return all subscriptions for all publications on server mssql1.

    .EXAMPLE
        PS C:\> Get-DbaReplSubscription -SqlInstance mssql1 -Database TestDB

        Return all subscriptions for all publications on server mssql1 for only the TestDB database.

    .EXAMPLE
        PS C:\> Get-DbaReplSubscription -SqlInstance mssql1 -PublicationName Mergey

        Return all subscriptions for the publication Mergey on server mssql1.

    .EXAMPLE
        PS C:\> Get-DbaReplSubscription -SqlInstance mssql1 -Type Push

        Return all subscriptions for all transactional publications on server mssql1.

    .EXAMPLE
        PS C:\> Get-DbaReplSubscription -SqlInstance mssql1 -SubscriberName mssql2

        Return all subscriptions for all publications on server mssql1 where the subscriber is mssql2.

    .EXAMPLE
        PS C:\> Get-DbaReplSubscription -SqlInstance mssql1 -SubscriptionDatabase TestDB

        Return all subscriptions for all publications on server mssql1 where the subscription database is TestDB.

    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Object[]]$Database,
        [String[]]$PublicationName,
        [DbaInstanceParameter[]]$SubscriberName,
        [Object[]]$SubscriptionDatabase,
        [Alias("PublicationType")]
        [ValidateSet("Push", "Pull")]
        [Object[]]$Type,
        [Switch]$EnableException
    )
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                $publications = Get-DbaReplPublication -SqlInstance $server -EnableException:$EnableException

                if ($Database) {
                    $publications = $publications | Where-Object DatabaseName -in $Database
                }

                if ($PublicationName) {
                    $publications = $publications | Where-Object Name -in $PublicationName
                }

            } catch {
                Stop-Function -Message "Error occurred while getting publications from $instance" -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                foreach ($subs in $publications.Subscriptions) {
                    Write-Message -Level Verbose -Message ('Get subscriptions for {0}' -f $sub.PublicationName)

                    if ($SubscriberName) {
                        $subs = $subs | Where-Object SubscriberName -eq $SubscriberName
                    }

                    if ($SubscriptionDatabase) {
                        $subs = $subs | Where-Object SubscriptionDBName -eq $SubscriptionDatabase
                    }

                    if ($Type) {
                        $subs = $subs | Where-Object SubscriptionType -eq $Type
                    }

                    foreach ($sub in $subs) {
                        Add-Member -Force -InputObject $sub -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                        Add-Member -Force -InputObject $sub -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                        Add-Member -Force -InputObject $sub -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName

                        Select-DefaultView -InputObject $sub -Property ComputerName, InstanceName, SqlInstance, DatabaseName, PublicationName, Name, SubscriberName, SubscriptionDBName, SubscriptionType
                    }
                }
            } catch {
                Stop-Function -Message "Error occurred while getting subscriptions from $instance" -ErrorRecord $_ -Target $instance -Continue
            }
        }
    }
}