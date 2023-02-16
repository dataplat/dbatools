function Get-DbaReplArticleColumn {
    <#
    .SYNOPSIS
        Gets the information about publication article columns.

    .DESCRIPTION
        This function enumerates columns information for a given articles.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies one or more database(s) to process. If unspecified, all databases will be processed.

    .PARAMETER PublicationName
        Specifies one or more publication(s) to process. If unspecified, all publications will be processed.

    .PARAMETER PublicationType
        Limit by specific type of publication. Valid choices include: Transactional, Merge, Snapshot

    .PARAMETER Article
        Specifies one or more article(s) to process. If unspecified, all articles will be processed.

    .PARAMETER Column
        Specifies one or more column(s) to process. If unspecified, all columns will be processed.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Replication
        Author: Cláudio Silva (@claudioessilva), claudioessilva.eu

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaReplArticleColumn

    .EXAMPLE
        PS C:\> Get-DbaReplArticleColumn -SqlInstance sqlserver2019 -Database pubs -Publication PubName -PublicationType Transactional -Article sales

        Retrieve information of 'sales' article from 'PubName' on 'pubs' database for server sqlserver2019.

    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [parameter(ValueFromPipeline)]
        [object[]]$Publication,
        [String]$PublicationType, # Snapshot, Transactional, Merge
        [string[]]$Article,
        [string[]]$Column,
        [switch]$EnableException
    )
    begin {
        #TODO - Still needed?
        Add-ReplicationLibrary
    }
    process {
        if (Test-FunctionInterrupt) { return }

        $articles = Get-DbaReplArticle -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -Publication $Publication -PublicationType $PublicationType -Article $Article

        foreach ($art in $articles) {
            $columns = $art.ListReplicatedColumns()

            if ($Column) {
                $columns = $columns | Where-Object { $_ -In $Column }
            }

            foreach ($col in $columns) {

                Add-Member -Force -InputObject $art -MemberType NoteProperty -Name ComputerName -Value $art.ComputerName
                Add-Member -Force -InputObject $art -MemberType NoteProperty -Name InstanceName -Value $art.InstanceName
                Add-Member -Force -InputObject $art -MemberType NoteProperty -Name SqlInstance -Value $art.SqlInstance
                Add-Member -Force -InputObject $art -MemberType NoteProperty -Name ArticleName -Value $art.Name
                Add-Member -Force -InputObject $art -MemberType NoteProperty -Name ArticleId -Value $art.ArticleId
                Add-Member -Force -InputObject $art -MemberType NoteProperty -Name Description -Value $art.Description
                Add-Member -Force -InputObject $art -MemberType NoteProperty -Name Type -Value $art.Type
                Add-Member -Force -InputObject $art -MemberType NoteProperty -Name VerticalPartition -Value $art.VerticalPartition
                Add-Member -Force -InputObject $art -MemberType NoteProperty -Name SourceObjectOwner -Value $art.SourceObjectOwner
                Add-Member -Force -InputObject $art -MemberType NoteProperty -Name SourceObjectName -Value $art.SourceObjectName
                Add-Member -Force -InputObject $art -MemberType NoteProperty -Name ColumnName -Value $col

                Select-DefaultView -InputObject $art -Property ComputerName, InstanceName, SqlInstance, ArticleName, ArticleId, Description, ColumnName #, DestinationObjectOwner, DestinationObjectName
            }
        }
    }
}