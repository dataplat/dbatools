function Remove-DbaReplSubscription {
    <#
    .SYNOPSIS
        Removes a subscription for the target SQL instances.

    .DESCRIPTION
        Removes a subscription for the target SQL instances.

        https://learn.microsoft.com/en-us/sql/relational-databases/replication/delete-a-push-subscription?view=sql-server-ver16
        https://learn.microsoft.com/en-us/sql/relational-databases/replication/delete-a-pull-subscription?view=sql-server-ver16

    .PARAMETER SqlInstance
        The target publisher SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target publisher instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the publisher database that contains the replication publication.
        This is the source database where the published data originates from.

    .PARAMETER SubscriberSqlInstance
        Specifies the SQL Server instance that receives replicated data from the publisher.
        Use this to identify which subscriber instance should have its subscription removed.

    .PARAMETER SubscriberSqlCredential
        Login to the subscriber instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).
        Required when the subscriber instance uses different authentication than the publisher.
        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER PublicationName
        Specifies the exact name of the replication publication to remove the subscription from.
        Must match an existing publication name on the publisher database.

    .PARAMETER SubscriptionDatabase
        Specifies the database on the subscriber instance that receives the replicated data.
        This is the target database where the subscription will be removed from.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .OUTPUTS
        None

        This command does not return any objects to the pipeline. It performs the subscription removal operation and displays informational messages via Write-Message and Write-Warning.

    .NOTES
        Tags: repl, Replication
        Author: Jess Pomfret (@jpomfret), jesspomfret.com

        Website: https://dbatools.io
        Copyright: (c) 2023 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaReplSubscription

    .EXAMPLE
        PS C:\> $sub = @{
        >> SqlInstance           = 'mssql1'
        >> Database              = 'pubs'
        >> PublicationName       = 'testPub'
        >> SubscriberSqlInstance = 'mssql2'
        >> SubscriptionDatabase  = 'pubs'
        >> }
        PS C:\> Remove-DbaReplSubscription @sub

        Removes a subscription for the testPub publication on mssql2.pubs.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Parameter(Mandatory)]
        [String]$Database,
        [Parameter(Mandatory)]
        [String]$PublicationName,
        [Parameter(Mandatory)]
        [DbaInstanceParameter]$SubscriberSqlInstance,
        [PSCredential]$SubscriberSqlCredential,
        [Parameter(Mandatory)]
        [String]$SubscriptionDatabase,
        [Switch]$EnableException
    )
    begin {

        $pub = Get-DbaReplPublication -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Name $PublicationName -EnableException:$EnableException

        if (-not $pub) {
            Write-Warning "Didn't find a subscription to the $PublicationName publication on $SqlInstance.$Database"
        }

    }
    process {
        foreach ($instance in $SubscriberSqlInstance) {

            try {
                if ($PSCmdlet.ShouldProcess($instance, "Removing subscription to $PublicationName from $SqlInstance.$SubscriptionDatabase")) {

                    if ($pub.Type -in ('Transactional', 'Snapshot')) {

                        #TODO: Only handles push subscriptions at the moment - need to add pull subscriptions
                        # https://learn.microsoft.com/en-us/sql/relational-databases/replication/delete-a-pull-subscription?view=sql-server-ver16
                        $transSub = New-Object Microsoft.SqlServer.Replication.TransSubscription
                        $transSub.ConnectionContext = $pub.ConnectionContext
                        $transSub.DatabaseName = $Database
                        $transSub.PublicationName = $PublicationName
                        $transSub.SubscriptionDBName = $SubscriptionDatabase
                        $transSub.SubscriberName = $instance

                        if ($transSub.IsExistingObject) {
                            Write-Message -Level Verbose -Message "Removing the subscription"
                            $transSub.Remove()
                        }

                    } elseif ($pub.Type -eq 'Merge') {
                        $mergeSub = New-Object Microsoft.SqlServer.Replication.MergeSubscription
                        $mergeSub.ConnectionContext = $pub.ConnectionContext
                        $mergeSub.DatabaseName = $Database
                        $mergeSub.PublicationName = $PublicationName
                        $mergeSub.SubscriptionDBName = $SubscriptionDatabase
                        $mergeSub.SubscriberName = $instance

                        if ($mergeSub.IsExistingObject) {
                            Write-Message -Level Verbose -Message "Removing the merge subscription"
                            $mergeSub.Remove()
                        } else {
                            Write-Warning "Didn't find a subscription to $PublicationName on $($instance).$SubscriptionDatabase"
                        }
                    }
                }
            } catch {
                Stop-Function -Message ("Unable to remove subscription - {0}" -f $_) -ErrorRecord $_ -Target $instance -Continue
            }
        }
    }
}