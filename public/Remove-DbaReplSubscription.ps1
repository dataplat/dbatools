function Remove-DbaReplSubscription {
    <#
    .SYNOPSIS
        Removes a subscription \for the target SQL instances.

    .DESCRIPTION
        Removes a subscription for the target SQL instances.

        https://learn.microsoft.com/en-us/sql/relational-databases/replication/delete-a-push-subscription?view=sql-server-ver16
        https://learn.microsoft.com/en-us/sql/relational-databases/replication/delete-a-pull-subscription?view=sql-server-ver16

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER PublisherSqlInstance
        The publisher SQL Server instance.

    .PARAMETER PublisherSqlCredential
        Login to the publisher instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER PublicationDatabase
        The database where the publication is located.

    .PARAMETER PublicationName
        The name of the publication.

    .PARAMETER SubscriptionDatabase
        The database where the subscription is located.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .NOTES
        Tags: Replication
        Author: Jess Pomfret (@jpomfret), jesspomfret.com

        Website: https://dbatools.io
        Copyright: (c) 2023 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaReplSubscription

    .EXAMPLE
        PS C:\> $sub = @{
                    SqlInstance          = 'mssql2'
                    SubscriptionDatabase = 'pubs'
                    PublisherSqlInstance = 'mssql1'
                    PublicationDatabase  = 'pubs'
                    PublicationName      = 'testPub'
                    }
        PS C:\> Remove-DbaReplSubscription @sub

        Removes a subscription for the testPub publication on mssql2.pubs.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter]$PublisherSqlInstance,
        [PSCredential]$PublisherSqlCredential,
        [String]$PublicationDatabase,
        [parameter(Mandatory)]
        [String]$PublicationName,
        [String]$SubscriptionDatabase,
        [Switch]$EnableException
    )
    begin {

        $pub = Get-DbaReplPublication -SqlInstance $PublisherSqlInstance -SqlCredential $PublisherSqlCredential -Name $PublicationName

        if (-not $pub) {
            Write-Warning "Didn't find a subscription to $PublicationName on $Instance.$Database"
        }

        try {
            $replServer = Get-DbaReplServer -SqlInstance $PublisherSqlInstance -SqlCredential $PublisherSqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        }

    }
    process {
        foreach ($instance in $SqlInstance) {

            try {
                if ($PSCmdlet.ShouldProcess($instance, "Removing subscription to $PublicationName from $instance.$SubscriptionDatabase")) {


                    if ($pub.Type -in ('Transactional', 'Snapshot')) {

                        #TODO: Only handles push subscriptions at the moment - need to add pull subscriptions
                        # https://learn.microsoft.com/en-us/sql/relational-databases/replication/delete-a-pull-subscription?view=sql-server-ver16
                        $transSub = New-Object Microsoft.SqlServer.Replication.TransSubscription
                        $transSub.ConnectionContext = $replServer.ConnectionContext
                        $transSub.DatabaseName = $PublicationDatabase
                        $transSub.PublicationName = $PublicationName
                        $transSub.SubscriptionDBName = $SubscriptionDatabase
                        $transSub.SubscriberName = $instance

                        if ($transSub.IsExistingObject) {
                            Write-Message -Level Verbose -Message "Removing the subscription"
                            $transSub.Remove()
                        }

                    } elseif ($pub.Type -eq 'Merge') {
                        $mergeSub = New-Object Microsoft.SqlServer.Replication.MergeSubscription
                        $mergeSub.ConnectionContext = $replServer.ConnectionContext
                        $mergeSub.DatabaseName = $PublicationDatabase
                        $mergeSub.PublicationName = $PublicationName
                        $mergeSub.SubscriptionDBName = $SubscriptionDatabase
                        $mergeSub.SubscriberName = $instance

                        if ($mergeSub.IsExistingObject) {
                            Write-Message -Level Verbose -Message "Removing the merge subscription"
                            $mergeSub.Remove()
                        } else {
                            Write-Warning "Didn't find a subscription to $PublicationName on $Instance.$SubscriptionDatabase"
                        }
                    }
                }
            } catch {
                Stop-Function -Message ("Unable to remove subscription - {0}" -f $_) -ErrorRecord $_ -Target $instance -Continue
            }
        }
    }
}



