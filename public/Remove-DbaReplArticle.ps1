function Remove-DbaReplArticle {
    <#
    .SYNOPSIS
        Removes an article from a publication for the database on the target SQL instances.

    .DESCRIPTION
        Removes an article from a publication for the database on the target SQL instances.

        Dropping an article from a publication does not remove the object from the publication database or the corresponding object from the subscription database.
        Use DROP <Object> to remove these objects if necessary. #TODO: add a param for this ClearUpSubObject

For snapshot or transactional publications, articles can be dropped with no special considerations prior to subscriptions being created.
If an article is dropped after one or more subscriptions is created, the subscriptions must be dropped, recreated, and synchronized.

Dropping an article from a publication involves dropping the article and creating a new snapshot for the publication.
Dropping an article invalidates the current snapshot; therefore a new snapshot must be created.


https://learn.microsoft.com/en-us/sql/relational-databases/replication/publish/add-articles-to-and-drop-articles-from-existing-publications?view=sql-server-ver16


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

    .PARAMETER Type
        The flavour of replication.

        Currently supported 'Transactional'

        Coming soon 'Snapshot', 'Merge'

    .PARAMETER LogReaderAgentCredential
        Used to provide the credentials for the Microsoft Windows account under which the Log Reader Agent runs

        Setting LogReaderAgentProcessSecurity is not required when the publication is created by a member of the sysadmin fixed server role.
        In this case, the agent will impersonate the SQL Server Agent account. For more information, see Replication Agent Security Model.

        TODO: Implement & test this

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

    .LINK
        https://dbatools.io/New-DbaReplPublication

    .EXAMPLE
        PS C:\> New-DbaReplPublication -SqlInstance mssql1 -Database Northwind -PublicationName PubFromPosh

        Creates a publication called PubFromPosh for the Northwind database on mssql1

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,

        [PSCredential]$SqlCredential,

        [parameter(Mandatory)]
        [String]$Database,

        [parameter(Mandatory)]
        [String]$PublicationName,

        [String]$Schema = 'dbo',

        [parameter(Mandatory)]
        [String]$Name,

        [String]$Filter, # some sql to horizontal filter "DiscontinuedDate IS NULL";

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

                    # based off this
                    # https://learn.microsoft.com/en-us/sql/relational-databases/replication/publish/define-an-article?view=sql-server-ver16#RMOProcedure

                    #TODO: add name field to Get-DbaReplPublication so don't have to where
                    $pub = Get-DbaReplPublication -SqlInstance $instance -SqlCredential $SqlCredential | Where-Object PublicationName -eq $PublicationName

                    if ($pub.PublicationType -eq 'Transactional') {

                        $article                    = New-Object Microsoft.SqlServer.Replication.TransArticle
                        $article.ConnectionContext  = $replServer.ConnectionContext
                        $article.Name               = $Name
                        $article.SourceObjectOwner  = $Schema
                        $article.PublicationName    = $PublicationName
                        $article.DatabaseName       = $Database

                        # think this is the default
                        #$article.Type = ArticleOptions.LogBased

                        if (($article.IsExistingObject)) {
                            $article.Remove()
                        } else {
                            Stop-Function -Message "Article doesn't exist in $PublicationName on $instance" -ErrorRecord $_ -Target $instance -Continue
                        }
                    }
                    # TODO: what if it's not transactional
                }
            } catch {
                Stop-Function -Message "Unable to remove article $ArticleName from $PublicationName on $instance" -ErrorRecord $_ -Target $instance -Continue
            }

            #TODO: What should we return anything?

        }
    }
}



