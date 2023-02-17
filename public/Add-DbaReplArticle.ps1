function Add-DbaReplArticle {
    <#
    .SYNOPSIS
        Adds an article to a publication for the database on the target SQL instances.

    .DESCRIPTION
        Adds an article to a publication for the database on the target SQL instances.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database on the publisher that contains the article to be replicated.

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

        https://learn.microsoft.com/en-us/sql/relational-databases/replication/publish/define-an-article?view=sql-server-ver16#RMOProcedure

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
            Write-Message -Level Verbose -Message "Adding article $Name to publication $PublicationName on $instance"

            try {
                if ($PSCmdlet.ShouldProcess($instance, "Adding an article to $PublicationName")) {

                    $pub = Get-DbaReplPublication -SqlInstance $instance -SqlCredential $SqlCredential -Name -eq $PublicationName

                    $articleOptions = New-Object Microsoft.SqlServer.Replication.ArticleOptions

                    if ($pub.PublicationType -eq 'Transactional') {
                        $article = New-Object Microsoft.SqlServer.Replication.TransArticle
                        $article.Type = $ArticleOptions::LogBased
                    } elseif ($pub.PublicationType -eq 'Merge') {
                        $article = New-Object Microsoft.SqlServer.Replication.MergeArticle
                        $article.Type = $ArticleOptions::TableBased
                    } else {
                        Stop-Function -Message "Publication is not a supported type, currently only Transactional and Merge publications are supported" -ErrorRecord $_ -Target $instance -Continue
                    }

                    $article.ConnectionContext  = $replServer.ConnectionContext
                    $article.Name               = $Name
                    $article.DatabaseName       = $Database
                    $article.SourceObjectName   = $Name
                    $article.SourceObjectOwner  = $Schema
                    $article.PublicationName    = $PublicationName

                    if ($articleFilter) {
                        article.FilterClause = $Filter  #TODO: This doesn't seem to be working
                    }

                    if (-not ($article.IsExistingObject)) {
                        $article.Create()
                    } else {
                        Stop-Function -Message "Article already exists in $PublicationName on $instance" -ErrorRecord $_ -Target $instance -Continue
                    }
                }
            } catch {
                Stop-Function -Message "Unable to add article $ArticleName to $PublicationName on $instance" -ErrorRecord $_ -Target $instance -Continue
            }
            #TODO: What should we return
            Get-DbaReplArticle -SqlInstance $instance -SqlCredential $SqlCredential -Publication $PublicationName -Article $Name
        }
    }
}



