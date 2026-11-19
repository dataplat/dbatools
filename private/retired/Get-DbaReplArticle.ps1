function Get-DbaReplArticle {
    <#
    .SYNOPSIS
        Retrieves detailed information about replication articles from SQL Server publications.

    .DESCRIPTION
        Retrieves comprehensive details about articles within SQL Server replication publications, helping DBAs audit and manage replication topology. Articles define which tables, views, or stored procedures are included in a publication for data distribution to subscribers.

        This function examines all accessible databases on the specified instances and returns article properties including name, type, schema, source objects, and partitioning details. Use this when troubleshooting replication issues, documenting replication setup, or verifying which objects are being replicated across your environment.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to examine for replication articles. Only articles from publications in these databases will be returned.
        Use this when you need to focus on replication articles within specific databases rather than scanning all databases on the instance.

    .PARAMETER Publication
        Filters results to articles within specific replication publications. Only articles from these named publications will be returned.
        Use this when troubleshooting a specific publication or when you need to audit articles within particular publications rather than all publications in the database.

    .PARAMETER Schema
        Filters articles by the schema of their source objects (tables, views, or procedures). Only articles whose source objects belong to these schemas will be returned.
        Use this when you need to examine replication articles for objects within specific schemas, such as when troubleshooting schema-specific replication issues.

    .PARAMETER Name
        Filters results to articles with specific names. Only articles matching these exact names will be returned.
        Use this when you need to examine specific replication articles by name, such as when troubleshooting issues with particular replicated objects.

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
        https://dbatools.io/Get-DbaReplArticle

    .OUTPUTS
        Microsoft.SqlServer.Replication.Article

        Returns one Article object per article found across the specified publications and databases. Each object represents a single replicated object (table, view, or stored procedure) included in a replication publication.

        Default display properties (via Select-DefaultView):
        - ComputerName: The name of the computer hosting the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - DatabaseName: The database containing the publication
        - PublicationName: The name of the publication containing this article
        - Name: The name of the article as it appears in the publication
        - Type: The type of object being replicated (Table, View, or StoredProcedure)
        - VerticalPartition: Boolean indicating if the article uses vertical partitioning (column filtering)
        - SourceObjectOwner: The schema name of the source object in the publisher database
        - SourceObjectName: The object name of the source table, view, or stored procedure

        Additional properties available (use Select-Object * to access all):
        All Microsoft.SqlServer.Replication.Article object properties are accessible, including:
        - Destination object properties (DestinationObjectOwner, DestinationObjectName)
        - Filter properties for horizontal and vertical partitioning
        - Resolver and conflict handling properties
        - Subscriber-specific properties and transforms
        - Replication-specific metadata about the article

        All properties from the base SMO Article object are accessible even though only the 10 default properties are displayed without using Select-Object *.

    .EXAMPLE
        PS C:\> Get-DbaReplArticle -SqlInstance mssql1

        Retrieve information of all articles from all publications on all databases for server mssql1.

    .EXAMPLE
        PS C:\> Get-DbaReplArticle -SqlInstance mssql1 -Database pubs

        Retrieve information of all articles from all publications on 'pubs' database for server mssql1.

    .EXAMPLE
        PS C:\> Get-DbaReplArticle -SqlInstance mssql1 -Database pubs -Publication PubName

        Retrieve information of all articles from 'PubName' on 'pubs' database for server mssql1.

    .EXAMPLE
        PS C:\> Get-DbaReplArticle -SqlInstance mssql1 -Database pubs -Schema sales

        Retrieve information of articles in the 'sales' schema on 'pubs' database for server mssql1.

    .EXAMPLE
        PS C:\> Get-DbaReplArticle -SqlInstance mssql1 -Database pubs -Publication PubName -Name sales

        Retrieve information of 'sales' article from 'PubName' on 'pubs' database for server mssql1.

    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$Publication,
        [string[]]$Schema,
        [string[]]$Name,
        [switch]$EnableException
    )
    begin {
        Add-ReplicationLibrary
    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                $databases = $server.Databases | Where-Object IsAccessible -eq $true
                if ($Database) {
                    $databases = $databases | Where-Object Name -in $Database
                }
            } catch {
                Stop-Function -Message "Error occurred while getting databases from $instance" -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                foreach ($db in $databases) {
                    Write-Message -Level Verbose -Message ('Working on {0}' -f $db.Name)

                    $publications = Get-DbaReplPublication -SqlInstance $server -Database $db.Name -EnableException:$EnableException

                    if ($Publication) {
                        $publications = $publications | Where-Object Name -in $Publication
                    }

                    $articles = $publications.Articles

                    if ($Schema) {
                        $articles = $articles | Where-Object SourceObjectOwner -in $Schema
                    }
                    if ($Name) {
                        $articles = $articles | Where-Object Name -in $Name
                    }

                    foreach ($art in $articles) {
                        Add-Member -Force -InputObject $art -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                        Add-Member -Force -InputObject $art -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                        Add-Member -Force -InputObject $art -MemberType NoteProperty -Name SqlInstance -Value $server

                        Select-DefaultView -InputObject $art -Property ComputerName, InstanceName, SqlInstance, DatabaseName, PublicationName, Name, Type, VerticalPartition, SourceObjectOwner, SourceObjectName #, DestinationObjectOwner, DestinationObjectName
                    }
                }
            } catch {
                Stop-Function -Message "Error occurred while getting articles from $instance" -ErrorRecord $_ -Target $instance -Continue
            }
        }
    }
}