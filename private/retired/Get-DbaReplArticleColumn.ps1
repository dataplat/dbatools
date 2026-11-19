function Get-DbaReplArticleColumn {
    <#
    .SYNOPSIS
        Retrieves column-level replication configuration details for SQL Server publication articles.

    .DESCRIPTION
        Returns detailed information about which columns are included in replication articles, helping DBAs audit replication configurations and troubleshoot column-specific replication issues. This is particularly useful when working with vertical partitioning scenarios where only specific columns from source tables are replicated to subscribers, or when investigating why certain columns aren't appearing in replicated data.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Filters results to specific database(s) containing publications. Accepts wildcards for pattern matching.
        Use this when you need to focus on replication columns from particular databases rather than scanning all databases on the instance.

    .PARAMETER Publication
        Filters results to specific publication(s) within the specified databases. Accepts wildcards for pattern matching.
        Use this when auditing column replication configuration for particular publications or troubleshooting column-level issues in specific publications.

    .PARAMETER Article
        Filters results to specific article(s) within the publications. Accepts wildcards for pattern matching.
        Use this when you need to examine column replication details for particular tables or views that are published as articles.

    .PARAMETER Column
        Filters results to specific column name(s) across all matched articles. Case-sensitive exact match.
        Use this when investigating whether specific columns are included in replication or troubleshooting missing columns in subscriber databases.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: repl, Replication
        Author: Cláudio Silva (@claudioessilva), claudioessilva.eu

        Website: https://dbatools.io
        Copyright: (c) 2023 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .OUTPUTS
        PSCustomObject

        Returns one object per column for each matched article, with detailed article and column information added via NoteProperties.

        Default display properties:
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - DatabaseName: The database containing the publication
        - PublicationName: The publication name
        - ArticleName: The article name
        - ArticleId: The unique identifier for the article
        - ColumnName: The name of the column within the article

        Additional properties available:
        - Description: Description of the article
        - Type: Type of the article (Table, View, Stored Procedure, etc.)
        - VerticalPartition: Boolean indicating if vertical partitioning is enabled
        - SourceObjectOwner: Schema owner of the source table
        - SourceObjectName: Name of the source table or view

    .LINK
        https://dbatools.io/Get-DbaReplArticleColumn

    .EXAMPLE
        PS C:\> Get-DbaReplArticleColumn -SqlInstance sqlserver2019

        Retrieve information of all replicated columns in any publications on server sqlserver2019.

    .EXAMPLE
        PS C:\> Get-DbaReplArticleColumn -SqlInstance sqlserver2019 -Database pubs

        Retrieve information of all replicated columns in any publications from the pubs database on server sqlserver2019.

    .EXAMPLE
        PS C:\> Get-DbaReplArticleColumn -SqlInstance sqlserver2019 -Publication test

        Retrieve information of all replicated columns in the test publication on server sqlserver2019.

    .EXAMPLE
        PS C:\> Get-DbaReplArticleColumn -SqlInstance sqlserver2019 -Database pubs -Publication PubName -Article sales

        Retrieve information of 'sales' article from 'PubName' on 'pubs' database for server sqlserver2019.

    .EXAMPLE
        PS C:\> Get-DbaReplArticleColumn -SqlInstance sqlserver2019 -Column state

        Retrieve information for the state column in any publication from any database on server sqlserver2019.

    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [parameter(ValueFromPipeline)]
        [object[]]$Publication,
        [string[]]$Article,
        [string[]]$Column,
        [switch]$EnableException
    )
    process {
        if (Test-FunctionInterrupt) { return }

        $articles = Get-DbaReplArticle -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -Publication $Publication -Name $Article -EnableException:$EnableException

        foreach ($art in $articles) {
            try {
                # Load the article properties to ensure we have current data
                $null = $art.LoadProperties()

                # Get the source table to enumerate columns
                $server = $art.SqlInstance
                $database = $server.Databases[$art.DatabaseName]
                $table = $database.Tables[$art.SourceObjectName, $art.SourceObjectOwner]

                if ($null -eq $table) {
                    Write-Message -Level Warning -Message "Could not find source table [$($art.SourceObjectOwner)].[$($art.SourceObjectName)] for article $($art.Name)"
                    continue
                }

                # Get all columns from the table
                $allColumns = $table.Columns

                # If vertical partitioning is not enabled, all columns are replicated
                # If it is enabled, we need to check which columns are included
                if (-not $art.VerticalPartition) {
                    # All columns are replicated
                    $columns = $allColumns.Name
                } else {
                    # Only specific columns are replicated - enumerate them from the article
                    # For vertical partitioning, we need to get the columns from the article's metadata
                    # Unfortunately, RMO doesn't expose this directly in a simple way
                    # We'll use the SMO connection to query the replication metadata
                    $splatQuery = @{
                        SqlInstance = $server
                        Database    = $art.DatabaseName
                        Query       = @"
SELECT c.name as ColumnName
FROM sysarticlecolumns ac
INNER JOIN sys.columns c ON ac.colid = c.column_id
INNER JOIN sys.tables t ON c.object_id = t.object_id AND ac.artid = (
    SELECT artid FROM sysarticles WHERE name = @articleName
)
WHERE t.name = @tableName
    AND SCHEMA_NAME(t.schema_id) = @schemaName
ORDER BY c.column_id
"@
                        SqlParameter = @{
                            articleName = $art.Name
                            tableName   = $art.SourceObjectName
                            schemaName  = $art.SourceObjectOwner
                        }
                    }
                    $columnData = Invoke-DbaQuery @splatQuery
                    $columns = $columnData.ColumnName
                }

                if ($Column) {
                    $columns = $columns | Where-Object { $_ -In $Column }
                }

                foreach ($col in $columns) {
                    Add-Member -Force -InputObject $art -MemberType NoteProperty -Name ComputerName -Value $art.ComputerName
                    Add-Member -Force -InputObject $art -MemberType NoteProperty -Name InstanceName -Value $art.InstanceName
                    Add-Member -Force -InputObject $art -MemberType NoteProperty -Name SqlInstance -Value $art.SqlInstance
                    Add-Member -Force -InputObject $art -MemberType NoteProperty -Name DatabaseName -Value $art.DatabaseName
                    Add-Member -Force -InputObject $art -MemberType NoteProperty -Name PublicationName -Value $art.PublicationName
                    Add-Member -Force -InputObject $art -MemberType NoteProperty -Name ArticleName -Value $art.Name
                    Add-Member -Force -InputObject $art -MemberType NoteProperty -Name ArticleId -Value $art.ArticleId
                    Add-Member -Force -InputObject $art -MemberType NoteProperty -Name Description -Value $art.Description
                    Add-Member -Force -InputObject $art -MemberType NoteProperty -Name Type -Value $art.Type
                    Add-Member -Force -InputObject $art -MemberType NoteProperty -Name VerticalPartition -Value $art.VerticalPartition
                    Add-Member -Force -InputObject $art -MemberType NoteProperty -Name SourceObjectOwner -Value $art.SourceObjectOwner
                    Add-Member -Force -InputObject $art -MemberType NoteProperty -Name SourceObjectName -Value $art.SourceObjectName
                    Add-Member -Force -InputObject $art -MemberType NoteProperty -Name ColumnName -Value $col

                    Select-DefaultView -InputObject $art -Property ComputerName, InstanceName, SqlInstance, DatabaseName, PublicationName, ArticleName, ArticleId, ColumnName #, DestinationObjectOwner, DestinationObjectName
                }
            } catch {
                Stop-Function -Message "Error occurred while getting article columns from $instance" -ErrorRecord $_ -Target $instance -Continue
            }
        }
    }
}