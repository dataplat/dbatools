function Get-DbaClusterNode {
    <#
        .SYNOPSIS
            Returns the node(s) of a SQL Cluster.

        .DESCRIPTION
            Returns the name of the current node(s) in the SQL Server cluster.

            If the -ActiveNode Parameter is passed it only returns the name of the Server currently hosting the clustered instance.

        .PARAMETER SqlInstance
            Specifies the SQL Server clustered instance to check.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER ActiveNode
            If this parameter is selected the cmdlet will only return the Active Node in the cluster.

        .PARAMETER Detailed
            Output all properties, will be deprecated in 1.0.0 release.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags:
            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Copyright (C) 2016 Chrissy LeMaire
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Get-DbaClusterNode

        .EXAMPLE
            Get-DbaClusterNode -SqlInstance sqlcluster

            Returns all nodes in the cluster and details about each node.

        .EXAMPLE
            Get-DbaClusterNode -SqlInstance sqlcluster -ActiveNode

            Returns the name of the active node in the cluster

    #>
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$ActiveNode,
        [switch]$Detailed,
        [alias('Silent')]
        [switch]$EnableException
    )

    begin {
        Test-DbaDeprecation -DeprecatedOn 1.0.0 -Parameter Detailed
        Test-DbaDeprecation -DeprecatedOn 1.0.0 -Alias Get-DbaClusterActiveNode
        $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential -MinimumVersion 10
    }

    process {
        if ($server.IsClustered -eq $false) {
            Stop-Function -Message "Not a clusterd instance." -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance -Continue
        }

        # If the -ActiveNode switch is selected only the primary node is returned.
        if ($ActiveNode) {
            try{
                    $sql = "SELECT * FROM sys.dm_os_cluster_nodes where is_current_owner = 1"
                    $datatable = $server.query($sql)

                        [PSCustomObject]@{
                            ComputerName      = $datatable.nodename
                            InstanceName      = $server.ServiceName
                            SqlInstance       = $server.DomainInstanceName
                            Status            = $datatable.Status
                            StatusDescription = $datatable.StatusDescription
                            CurrentOwner      = $datatable.is_current_owner
                        } | Select-DefaultView -Property ComputerName
            }
            catch{
                Stop-Function -Message "Unable to query sys.dm_os_cluster_nodes on $server." -ErrorRecord $_ -Target $SqlInstance -Continue
            }
        }
        #Default Execution of this function
        else {
            try{
                $sql = "SELECT * FROM sys.dm_os_cluster_nodes"
                $datatable = $server.query($sql)

                foreach($data in $datatable){
                    [PSCustomObject]@{
                        ComputerName      = $data.nodename
                        InstanceName      = $server.ServiceName
                        SqlInstance       = $server.DomainInstanceName
                        Status            = $data.Status
                        StatusDescription = $data.StatusDescription
                        CurrentOwner      = $data.is_current_owner
                    } | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, StatusDescription, CurrentOwner
                }
            }
            catch{
                Stop-Function -Message "Unable to query sys.dm_os_cluster_nodes on $server." -ErrorRecord $_ -Target $SqlInstance -Continue
            }
        }
    }
}