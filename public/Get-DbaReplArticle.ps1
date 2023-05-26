function Get-DbaReplArticle {
    <#
    .SYNOPSIS
        Gets the information about publication articles.

    .DESCRIPTION
        This function locates and enumerates articles' information.

        Can specify a database, publication or article name or publication type.

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

    .PARAMETER Type
        Limit by specific type of publication. Valid choices include: Transactional, Merge, Snapshot.

    .PARAMETER Article
        Specifies one or more article(s) to process. If unspecified, all articles will be processed.

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
        https://dbatools.io/Get-DbaReplArticle

    .EXAMPLE
        PS C:\> Get-DbaReplArticle -SqlInstance mssql1

        Retrieve information of all articles from all publications on all databases for server mssql1.

    .EXAMPLE
        PS C:\> Get-DbaReplArticle -SqlInstance mssql1 -Database pubs

        Retrieve information of all articles from all publications on 'pubs' database for server mssql1.

    .EXAMPLE
        PS C:\> Get-DbaReplArticle -SqlInstance mssql1 -Database pubs -Publication PubName

        Retrieve information of all articles from 'PubName' on 'pubs' database for server mssql1.

        #TODO: results publicationname contains all the publication names if article is in more than one ?
        ComputerName      : mssql1
        InstanceName      : MSSQLSERVER
        SqlInstance       : mssql1
        DatabaseName      : ReplDb
        PublicationName   : {Snappy, TestPub, TestPub-Trans, TestSnap…}
        Name              : ReplicateMe
        ArticleId         : 2
        Description       :
        Type              : LogBased
        VerticalPartition : False
        SourceObjectOwner : dbo
        SourceObjectName  : ReplicateMe

        ComputerName      : mssql1
        InstanceName      : MSSQLSERVER
        SqlInstance       : mssql1
        DatabaseName      : ReplDb
        PublicationName   : {Snappy, TestPub, TestPub-Trans, TestSnap…}
        Name              : ReplicateMe
        ArticleId         : 3
        Description       :
        Type              : LogBased
        VerticalPartition : False
        SourceObjectOwner : dbo
        SourceObjectName  : ReplicateMe


        PS C:\> Get-DbaReplArticle -SqlInstance sqlserver2019 -Database pubs -Publication PubName -PublicationType Transactional -Article sales

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
        [ValidateSet("Transactional", "Merge", "Snapshot")]
        [String]$Type,
        [string[]]$Article,
        [switch]$EnableException
    )
    begin {
        Add-ReplicationLibrary
    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            # Connect to the distributor of the instance
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
                $replServer = Get-DbaReplServer -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                $databases = $server.Databases | Where-Object IsAccessible -eq $true
                if ($Database) {
                    $databases = $databases | Where-Object Name -In $Database
                }
            } catch {
                Stop-Function -Message "Error occurred while getting databases from $instance" -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                foreach ($db in $databases) {
                    Write-Message -Level Verbose -Message ('Working on {0}' -f $db.Name)

                    $RMOdb = New-Object Microsoft.SqlServer.Replication.ReplicationDatabase
                    $RMOdb.ConnectionContext = $replServer.ConnectionContext
                    $RMOdb.Name = $db.Name
                    if (-not $RMOdb.LoadProperties()) {
                        Write-Message -Level Verbose -Message "Skipping $($db.name). Database is not published."
                        continue
                    }

                    #$RMOdb = Connect-ReplicationDB -Server $server -Database $db

                    $publications = @()
                    $publications += $RMOdb.TransPublications
                    $publications += $RMOdb.MergePublications

                    if ($Publication) {
                        $publications = $publications | Where-Object Name -in $Publication
                    }

                    if ($Type -eq 'Merge') {
                        $articles = $publications.MergeArticles
                    } else {
                        $articles = $publications.TransArticles
                    }

                    if ($Article) {
                        $articles = $articles | Where-Object Name -In $Article
                    }

                    foreach ($art in $articles) {
                        Add-Member -Force -InputObject $art -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                        Add-Member -Force -InputObject $art -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                        Add-Member -Force -InputObject $art -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                        Add-Member -Force -InputObject $art -MemberType NoteProperty -Name PublicationName -Value $publications.Name

                        Select-DefaultView -InputObject $art -Property ComputerName, InstanceName, SqlInstance, DatabaseName, PublicationName, Name, ArticleId, Description, Type, VerticalPartition, SourceObjectOwner, SourceObjectName #, DestinationObjectOwner, DestinationObjectName
                    }
                }
            } catch {
                Stop-Function -Message "Error occurred while getting articles from $instance" -ErrorRecord $_ -Target $instance -Continue
            }
        }
    }
}