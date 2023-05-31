function Remove-DbaReplArticle {
    <#
    .SYNOPSIS
        Removes an article from a publication for the database on the target SQL instances.

    .DESCRIPTION
        Removes an article from a publication for the database on the target SQL instances.

        Dropping an article from a publication does not remove the object from the publication database or the corresponding object from the subscription database.
        Use DROP <Object> to remove these objects if necessary. #TODO: add a param for this ClearUpSubObject

        Dropping an article invalidates the current snapshot; therefore a new snapshot must be created.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database on the publisher that contains the article to be removed from replication.

    .PARAMETER PublicationName
        The name of the replication publication.

    .PARAMETER Schema
        Source schema of the replicated object to remove from the publication.

    .PARAMETER Name
        The name of the article to remove.

    .PARAMETER DropObjectOnSubscriber
        If this switch is enabled, the object will be dropped from the subscriber database.

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
        Author: Jess Pomfret (@jpomfret)

        Website: https://dbatools.io
        Copyright: (c) 2022 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        https://learn.microsoft.com/en-us/sql/relational-databases/replication/publish/delete-an-article?view=sql-server-ver16

    .LINK
        https://dbatools.io/Remove-DbaReplArticle

    .EXAMPLE
        PS C:\> Remove-DbaReplArticle -SqlInstance mssql1 -Database Pubs -PublicationName PubFromPosh -Name 'publishers'

        Removes the publishers article from a publication called PubFromPosh on mssql1

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,

        [PSCredential]$SqlCredential,

        [parameter(Mandatory)]
        [String]$Database,

        [parameter(Mandatory)]
        [String]$PublicationName,

        [String]$Schema = 'dbo',

        [parameter(Mandatory)]
        [String]$Name,

        [Switch]$DropObjectOnSubscriber,

        [Switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $replServer = Get-DbaReplServer -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            Write-Message -Level Verbose -Message "Removing article $Name from publication $PublicationName on $instance"

            try {
                if ($PSCmdlet.ShouldProcess($instance, "Removing an article from $PublicationName")) {

                    $pub = Get-DbaReplPublication -SqlInstance $instance -SqlCredential $SqlCredential -Name $PublicationName

                    if ($pub.Type -in ('Transactional', 'Snapshot')) {
                        $article                    = New-Object Microsoft.SqlServer.Replication.TransArticle
                    } elseif ($pub.Type -eq 'Merge') {
                        $article                    = New-Object Microsoft.SqlServer.Replication.MergeArticle
                    } else {
                        Stop-Function -Message "Publication is not a supported type, currently only Transactional and Merge publications are supported" -ErrorRecord $_ -Target $instance -Continue
                    }

                    $article.ConnectionContext  = $replServer.ConnectionContext
                    $article.Name               = $Name
                    $article.SourceObjectOwner  = $Schema
                    $article.PublicationName    = $PublicationName
                    $article.DatabaseName       = $Database

                    #TODO: change to RMO? if it has a subscription, we need to drop it first = can't work it out with RMO
                    if ($pub.Subscriptions) {
                        Write-Message -Level Verbose -Message ("There is a subscription so remove article {0} from subscription on {1}" -f $Name, $pub.Subscriptions.SubscriberName)
                        $query = "exec sp_dropsubscription @publication = '{0}', @article= '{1}',@subscriber = '{2}'" -f $PublicationName, $Name, $pub.Subscriptions.SubscriberName
                        Invoke-DbaQuery -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database -query $query
                    }

                    if (($article.IsExistingObject)) {
                        $article.Remove()
                    } else {
                        Stop-Function -Message "Article doesn't exist in $PublicationName on $instance" -ErrorRecord $_ -Target $instance -Continue
                    }

                    if ($DropObjectOnSubscriber) {
                        #TODO: Drop object on subscriber
                    }
                }
            } catch {
                Stop-Function -Message "Unable to remove article $ArticleName from $PublicationName on $instance" -ErrorRecord $_ -Target $instance -Continue
            }
        }
    }
}



