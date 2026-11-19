function Get-DbaReplDistributor {
    <#
    .SYNOPSIS
        Retrieves replication distributor configuration and status information from SQL Server instances.

    .DESCRIPTION
        Connects to SQL Server instances and retrieves detailed information about their replication distributor configuration, including distributor status, distribution database details, and publisher relationships. This is essential for DBAs managing replication topologies who need to quickly identify which servers act as distributors, where the distribution database is located, and whether remote publishers are configured. The function returns comprehensive distributor properties that help with replication troubleshooting, topology documentation, and configuration audits.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances to check for replication distributor configuration.
        Use this to identify which servers in your environment are configured as distributors, where the distribution database is located, and whether they support remote publishers.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        Microsoft.SqlServer.Replication.ReplicationServer

        Returns one ReplicationServer object per SQL Server instance with replication configuration and status information.

        Default display properties:
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - IsPublisher: Boolean indicating if the instance is configured as a replication publisher
        - IsDistributor: Boolean indicating if the instance is configured as a replication distributor
        - DistributionServer: The name of the server hosting the distribution database (null if not a distributor)
        - DistributionDatabase: The name of the distribution database (null if not a distributor)
        - DistributorInstalled: Boolean indicating if distributor components are installed on the instance
        - DistributorAvailable: Boolean indicating if the distributor is currently available and functional
        - HasRemotePublisher: Boolean indicating if the distributor has remote publishers configured

        Additional properties available from the ReplicationServer object:
        - ReplicationDatabases: Collection of databases enabled for replication (not necessarily actively replicated)
        - DistributionDatabaseAvailable: Boolean indicating if the distribution database is accessible
        - HardwareBoundary: Indicates hardware boundary for replication
        - PublisherList: Collection of publishers using this distributor

        Use Select-Object * to access all available properties from the ReplicationServer object.

    .NOTES
        Tags: Replication
        Author: William Durkin (@sql_williamd)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaReplDistributor

    .EXAMPLE
        PS C:\> Get-DbaReplDistributor -SqlInstance sql2008, sqlserver2012

        Retrieve distributor information for servers sql2008 and sqlserver2012.

    .EXAMPLE
        PS C:\> Connect-DbaInstance -SqlInstance mssql1 | Get-DbaReplDistributor

        Pipe a SQL Server instance to Get-DbaReplDistributor to retrieve distributor information.
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Attempting to retrieve distributor information from $instance"

            # Connect to the distributor of the instance
            try {
                $distributor = Get-DbaReplServer -SqlInstance $instance -SqlCredential $SqlCredential -EnableException:$EnableException
            } catch {
                Stop-Function -Message "Error occurred getting information about $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            Write-Message -Level Verbose -Message "Getting publisher for $server"

            Select-DefaultView -InputObject $distributor -Property ComputerName, InstanceName, SqlInstance, IsPublisher, IsDistributor, DistributionServer, DistributionDatabase, DistributorInstalled, DistributorAvailable, HasRemotePublisher
        }
    }
}