function Add-DbaReplArticle {
    <#
    .SYNOPSIS
        Adds a table or other database object as an article to an existing replication publication.

    .DESCRIPTION
        Adds a database object (typically a table) as an article to an existing SQL Server replication publication. Articles define which tables and data get replicated to subscribers. This function supports both transactional and merge replication publications, allowing you to expand replication topology without using SQL Server Management Studio. You can apply horizontal filters to replicate only specific rows, and customize schema options like indexes and statistics that get created on subscriber databases.

    .PARAMETER SqlInstance
        The SQL Server instance(s) for the publication.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the database containing both the publication and the object you want to add as an article.
        This must be the same database where your replication publication was created.

    .PARAMETER Publication
        Specifies the name of the existing replication publication to add the article to.
        The publication must already exist and be configured for the type of replication you want (transactional, snapshot, or merge).

    .PARAMETER Schema
        Specifies the schema name of the object you want to add as an article.
        Use this when your table or object exists in a schema other than dbo. Defaults to dbo if not specified.

    .PARAMETER Name
        Specifies the name of the database object (typically a table) to add as an article to the publication.
        This object will be replicated to all subscribers of the publication.

    .PARAMETER Filter
        Applies a WHERE clause condition to filter which rows get replicated from the article (horizontal filtering).
        Use this when you only want to replicate specific rows, such as "City = 'Seattle'" or "Status = 'Active'". Do not include the word 'WHERE' in your filter expression.

    .PARAMETER CreationScriptOptions
        Controls which schema elements get created on the subscriber database when the article is replicated.
        Use this to specify whether indexes, constraints, triggers, and other objects should be created on subscribers. Create this object using New-DbaReplCreationScriptOptions.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .NOTES
        Tags: repl, Replication
        Author: Jess Pomfret (@jpomfret), jesspomfret.com

        Website: https://dbatools.io
        Copyright: (c) 2023 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        https://learn.microsoft.com/en-us/sql/relational-databases/replication/publish/define-an-article?view=sql-server-ver16#RMOProcedure

    .LINK
        https://dbatools.io/Add-DbaReplArticle

    .EXAMPLE
        PS C:\> Add-DbaReplArticle -SqlInstance mssql1 -Database Northwind -Publication PubFromPosh -Name TableToRepl

        Adds the TableToRepl table to the PubFromPosh publication from mssql1.Northwind

    .EXAMPLE
        PS C:\> $article = @{
        >> SqlInstance           = "mssql1"
        >> Database              = "pubs"
        >> Publication           = "testPub"
        >> Name                  = "publishers"
        >> Filter                = "city = 'seattle'"
        >> }
        PS C:\> Add-DbaReplArticle @article -EnableException

        Adds the publishers table to the TestPub publication from mssql1.Pubs with a horizontal filter of only rows where city = 'seattle.

    .EXAMPLE
        PS C:\> $cso = New-DbaReplCreationScriptOptions -Options NonClusteredIndexes, Statistics
        PS C:\> $article = @{
        >> SqlInstance           = 'mssql1'
        >> Database              = 'pubs'
        >> Publication           = 'testPub'
        >> Name                  = 'stores'
        >> CreationScriptOptions = $cso
        >> }
        PS C:\> Add-DbaReplArticle @article -EnableException

        Adds the stores table to the testPub publication from mssql1.pubs with the NonClusteredIndexes and Statistics options set
        includes default options.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory)]
        [string]$Database,
        [Parameter(Mandatory)]
        [string]$Publication,
        [string]$Schema = 'dbo',
        [Parameter(Mandatory)]
        [string]$Name,
        [string]$Filter,
        [PSObject]$CreationScriptOptions,
        [switch]$EnableException
    )
    process {

        # Check that $CreationScriptOptions is a valid object
        if ($CreationScriptOptions -and ($CreationScriptOptions -isnot [Microsoft.SqlServer.Replication.CreationScriptOptions])) {
            Stop-Function -Message "CreationScriptOptions should be the right type. Use New-DbaReplCreationScriptOptions to create the object" -Target $instance -Continue
        }

        if ($Filter -like 'WHERE*') {
            Stop-Function -Message "Filter should not include the word 'WHERE'" -Target $instance -Continue
        }

        foreach ($instance in $SqlInstance) {
            try {
                $replServer = Get-DbaReplServer -SqlInstance $instance -SqlCredential $SqlCredential -EnableException:$EnableException
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            Write-Message -Level Verbose -Message "Adding article $Name to publication $Publication on $instance"

            try {
                if ($PSCmdlet.ShouldProcess($instance, "Get the publication details for $Publication")) {

                    $pub = Get-DbaReplPublication -SqlInstance $instance -SqlCredential $SqlCredential -Name $Publication -EnableException:$EnableException
                    if (-not $pub) {
                        Stop-Function -Message "Publication $Publication does not exist on $instance" -Target $instance -Continue
                    }
                }
            } catch {
                Stop-Function -Message "Unable to get publication $Publication on $instance" -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                if ($PSCmdlet.ShouldProcess($instance, "Create an article object for $Publication which is a $($pub.Type) publication")) {

                    $articleOptions = New-Object Microsoft.SqlServer.Replication.ArticleOptions

                    if ($pub.Type -in ('Transactional', 'Snapshot')) {
                        $article = New-Object Microsoft.SqlServer.Replication.TransArticle
                        $article.Type = $ArticleOptions::LogBased
                    } elseif ($pub.Type -eq 'Merge') {
                        $article = New-Object Microsoft.SqlServer.Replication.MergeArticle
                        $article.Type = $ArticleOptions::TableBased
                    }

                    $article.ConnectionContext = $replServer.ConnectionContext
                    $article.Name = $Name
                    $article.DatabaseName = $Database
                    $article.SourceObjectName = $Name
                    $article.SourceObjectOwner = $Schema
                    $article.PublicationName = $Publication
                }
            } catch {
                Stop-Function -Message "Unable to create article object for $Name to add to $Publication on $instance" -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                if ($CreationScriptOptions) {
                    if ($PSCmdlet.ShouldProcess($instance, "Add creation options for article: $Name")) {
                        $article.SchemaOption = $CreationScriptOptions
                    }
                }

                if ($Filter) {
                    if ($PSCmdlet.ShouldProcess($instance, "Add filter for article: $Name")) {
                        $article.FilterClause = $Filter
                    }
                }

                if ($PSCmdlet.ShouldProcess($instance, "Create article: $Name")) {
                    if (-not ($article.IsExistingObject)) {
                        $article.Create()
                    } else {
                        Stop-Function -Message "Article already exists in $Publication on $instance" -Target $instance -Continue
                    }

                    if ($pub.Type -in ('Transactional', 'Snapshot')) {
                        $pub.RefreshSubscriptions()
                    }
                }
            } catch {
                Stop-Function -Message "Unable to add article $Name to $Publication on $instance" -ErrorRecord $_ -Target $instance -Continue
            }
            Get-DbaReplArticle -SqlInstance $instance -SqlCredential $SqlCredential -Publication $Publication -Name $Name -EnableException:$EnableException
        }
    }
}