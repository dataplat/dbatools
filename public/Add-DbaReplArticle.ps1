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

    .PARAMETER Schema
        The schema name that contains the object to add as an article.
        Default is dbo.

    .PARAMETER Name
        The name of the object to add as an article.

    .PARAMETER Filter
        Horizontal filter for replication, implemented as a where clause, but don't include the word WHERE>
        E.g. City = 'Seattle'

    .PARAMETER CreationScriptOptions
        Options for the creation script.
        Use New-DbaReplCreationScriptOptions to create this object.

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
        Copyright: (c) 2022 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        https://learn.microsoft.com/en-us/sql/relational-databases/replication/publish/define-an-article?view=sql-server-ver16#RMOProcedure

    .LINK
        https://dbatools.io/Add-DbaReplArticle

    .EXAMPLE
        PS C:\> Add-DbaReplArticle -SqlInstance mssql1 -Database Northwind -PublicationName PubFromPosh -Name TableToRepl

        Adds the TableToRepl table to the PubFromPosh publication from mssql1.Northwind


    .EXAMPLE
        PS C:\> Add-DbaReplArticle -SqlInstance mssql1 -Database Pubs -PublicationName TestPub -Name publishers -Filter "city = 'seattle'"

        Adds the publishers table to the TestPub publication from mssql1.Pubs with a horizontal filter of only rows where city = 'seattle.

    .EXAMPLE
        PS C:\> $cso = New-DbaReplCreationScriptOptions -Options NonClusteredIndexes, Statistics
        PS C:\> $article = @{
                    SqlInstance           = 'mssql1'
                    Database              = 'pubs'
                    PublicationName       = 'testPub'
                    Name                  = 'stores'
                    CreationScriptOptions = $cso
                }
                Add-DbaReplArticle @article -EnableException

        Adds the stores table to the testPub publication from mssql1.pubs with the NonClusteredIndexes and Statistics options set
        includes default options.
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

        [String]$Filter,

        #TODO: Build a New-DbaReplArticleOptions function
        [Microsoft.SqlServer.Replication.CreationScriptOptions]$CreationScriptOptions,

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

                    $pub = Get-DbaReplPublication -SqlInstance $instance -SqlCredential $SqlCredential -Name $PublicationName

                    $articleOptions = New-Object Microsoft.SqlServer.Replication.ArticleOptions

                    if ($pub.Type -in ('Transactional', 'Snapshot')) {
                        $article = New-Object Microsoft.SqlServer.Replication.TransArticle
                        $article.Type = $ArticleOptions::LogBased
                    } elseif ($pub.Type -eq 'Merge') {
                        $article = New-Object Microsoft.SqlServer.Replication.MergeArticle
                        $article.Type = $ArticleOptions::TableBased
                    }

                    $article.ConnectionContext  = $replServer.ConnectionContext
                    $article.Name               = $Name
                    $article.DatabaseName       = $Database
                    $article.SourceObjectName   = $Name
                    $article.SourceObjectOwner  = $Schema
                    $article.PublicationName    = $PublicationName

                    if ($CreationScriptOptions) {
                        $article.SchemaOption = $CreationScriptOptions
                    }

                    if ($Filter) {
                        if ($Filter -like 'WHERE*') {
                            Stop-Function -Message "Filter should not include the word 'WHERE'" -ErrorRecord $_ -Target $instance -Continue
                        }
                        $article.FilterClause = $Filter
                    }

                    if (-not ($article.IsExistingObject)) {
                        $article.Create()
                    } else {
                        Stop-Function -Message "Article already exists in $PublicationName on $instance" -ErrorRecord $_ -Target $instance -Continue
                    }

                    # need to refresh subscriptions so they know about new articles
                    $pub.RefreshSubscriptions()
                }
            } catch {
                Stop-Function -Message "Unable to add article $Name to $PublicationName on $instance" -ErrorRecord $_ -Target $instance -Continue
            }
            #TODO: What should we return
            Get-DbaReplArticle -SqlInstance $instance -SqlCredential $SqlCredential -Publication $PublicationName -Article $Name
        }
    }
}



