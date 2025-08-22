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
        Specifies one or more database(s) to process. If unspecified, all databases will be processed.

    .PARAMETER Publication
        Specifies one or more publication(s) to process. If unspecified, all publications will be processed.

    .PARAMETER Article
        Specifies one or more article(s) to process. If unspecified, all articles will be processed.

    .PARAMETER Column
        Specifies one or more column(s) to process. If unspecified, all columns will be processed.

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

                $columns = $art.ListReplicatedColumns()

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