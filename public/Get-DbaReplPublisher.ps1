function Get-DbaReplPublisher {
    <#
    .SYNOPSIS
        Retrieves SQL Server replication publisher configuration and status from distribution servers.

    .DESCRIPTION
        Retrieves detailed information about SQL Server replication publishers configured on distribution servers. This function connects to instances acting as distributors and returns publisher details including status, working directory, distribution database, and publication counts. Use this to audit replication topology, troubleshoot publisher connectivity issues, or verify publisher configurations across your replication environment.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: repl, Replication
        Author: Mikey Bronowski (@MikeyBronowski), bronowski.it

        Website: https://dbatools.io
        Copyright: (c) 2022 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaReplPublisher

    .OUTPUTS
        Microsoft.SqlServer.Replication.DistributionPublisher

        Returns one DistributionPublisher object for each Publisher configured on the distribution server instance. If no publishers are configured, nothing is returned.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Status: The current status of the Publisher (e.g., Healthy, Unhealthy)
        - WorkingDirectory: Directory path where publication data and schema files are stored
        - DistributionDatabase: The name of the distribution database used for this Publisher
        - DistributionPublications: Number of transactional publications at the Publisher
        - PublisherType: The type of Publisher (e.g., MSSQLSERVER for SQL Server, or third-party identifier)
        - Name: The instance name of the Publisher

        Additional properties available (from SMO DistributionPublisher object):
        - PublisherSecurity: Security context for replication agents connecting to the Publisher
        - RegisteredSubscribers: Collection of Subscribers registered for this Publisher's publications
        - TransPublications: Collection of transactional publications at the Publisher
        - ThirdParty: Boolean indicating if this is a non-SQL Server Publisher
        - TrustedDistributorConnection: Boolean indicating if the distributor connection is trusted
        - HeterogeneousLogReaderAgentExists: Boolean indicating if a Log Reader Agent job exists
        - ConnectionContext: The connection context to the SQL Server instance
        - IsExistingObject: Boolean indicating if the object exists on the server

        All properties from the base SMO DistributionPublisher object are accessible using Select-Object * even though only default properties are displayed by default.

    .EXAMPLE
        PS C:\> Get-DbaReplPublisher -SqlInstance mssql1

        Gets publisher for the mssql1 instance.

    .EXAMPLE
        PS C:\> Connect-DbaInstance -SqlInstance mssql1 |  Get-DbaReplPublisher

        Pipes a SQL Server object to get publisher information for the mssql1 instance.
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
                $replServer = Get-DbaReplServer -SqlInstance $server -EnableException:$EnableException
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $server -Continue
            }
            Write-Message -Level Verbose -Message "Getting publisher for $server"

            try {
                $publisher = $replServer.DistributionPublishers
            } catch {
                Stop-Function -Message "Unable to get publisher for" -ErrorRecord $_ -Target $server -Continue
            }

            # fails if there isn't any
            if ($publisher) {
                $publisher | Add-Member -Type NoteProperty -Name ComputerName -Value $server.ComputerName -Force
                $publisher | Add-Member -Type NoteProperty -Name InstanceName -Value $server.ServiceName -Force
                $publisher | Add-Member -Type NoteProperty -Name SqlInstance -Value $server.DomainInstanceName -Force
            }

            Select-DefaultView -InputObject $publisher -Property ComputerName, InstanceName, SqlInstance, Status, WorkingDirectory, DistributionDatabase, DistributionPublications, PublisherType, Name

        }
    }
}