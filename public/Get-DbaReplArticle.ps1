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
        Specifies one or more database(s) to process. If unspecified, all databases will be processed.

    .PARAMETER Publication
        Specifies one or more publication(s) to process. If unspecified, all publications will be processed.

   .PARAMETER Schema
        Specifies one or more schema(s) to process. If unspecified, all schemas will be processed.

    .PARAMETER Name
        Specify the name of one or more article(s) to process. If unspecified, all articles will be processed.

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