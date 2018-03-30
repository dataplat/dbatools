function Get-DbaDistributor {
    <#
    .SYNOPSIS
        Gets the information about a replication distributor for a given SQL Server instance.

    .DESCRIPTION
        This function locates and enumerates distributor information for a given SQL Server instance.

    .PARAMETER SqlInstance
        Allows you to specify a comma separated list of servers to query.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Author: William Durkin, @sql_williamd
        Tags: Replication
        Website: https://dbatools.io
        Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDistributor

    .EXAMPLE
        Get-DbaDistributor -SqlInstance sql2008, sqlserver2012
        Retrieve distributor information for servers sql2008 and sqlserver2012.
    #>
    [CmdletBinding()]
    Param (
        [parameter(Position = 0, Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer", "SqlServers")]
        [DbaInstanceParameter[]]$SqlInstance,
        [parameter(Position = 1)]
        [PSCredential]$SqlCredential,
        [Alias('Silent')]
        [switch]$EnableException
    )
    begin {
        if ($null -eq [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.RMO")) {
            Stop-Function -Message "Replication management objects not available. Please install SQL Server Management Studio."
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Attempting to connect to $instance"

            # connect to the instance
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            Write-Message -Level Verbose -Message "Attempting to retrieve distributor information from $instance"

            # Connect to the distributor of the instance
            try {
                $sourceSqlConn = $server.ConnectionContext.SqlConnectionObject
                $distributor = New-Object Microsoft.SqlServer.Replication.ReplicationServer $sourceSqlConn
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            Add-Member -Force -InputObject $distributor -MemberType NoteProperty -Name ComputerName -Value $server.NetName
            Add-Member -Force -InputObject $distributor -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
            Add-Member -Force -InputObject $distributor -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName

            Select-DefaultView -InputObject $distributor -Property ComputerName, InstanceName, SqlInstance, IsPublisher, IsDistributor, DistributionServer, DistributionDatabase, DistributorInstalled, DistributorAvailable, HasRemotePublisher
        }
    }
}
