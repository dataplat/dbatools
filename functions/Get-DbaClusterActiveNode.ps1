function Get-DbaClusterActiveNode {
    <#
        .SYNOPSIS
            Returns the active node of a SQL Cluster.

        .DESCRIPTION
            Returns the name of the current active node in the SQL Server cluster.

        .PARAMETER SqlInstance
            Specifies the SQL Server clustered instance to check.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter.

            Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER Detailed
            Returns available details of SQL Cluster nodes. In SQL Server 2008, this will return node names. In SQL Server 2012 and above, this will return:

            NodeName
            Status
            StatusDescription
            CurrentOwner

        .PARAMETER WhatIf
            If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

        .PARAMETER Confirm
            If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

        .NOTES
            Tags:
            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Copyright (C) 2016 Chrissy LeMaire
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Get-DbaClusterActiveNode

        .EXAMPLE
            Get-DbaClusterActiveNode -SqlInstance sqlcluster

            Returns a simple string with the ComputerNamePhysicalNetBIOS property.

        .EXAMPLE
            Get-DbaClusterActiveNode -SqlInstance sqlcluster -Detailed

            Returns a datatable with details about sqlcluster.

    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter]$SqlInstance,
        [object]$SqlCredential,
        [switch]$Detailed
    )

    begin {
        $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential -RegularUser
        $computername = $server.ComputerNamePhysicalNetBIOS
    }

    process {
        if ($server.IsClustered -eq $false) {
            return "Not a clustered instance."
        }

        if ($Detailed -eq $true) {
            $sql = "Select *  FROM sys.dm_os_cluster_nodes"
            $datatable = $server.ConnectionContext.ExecuteWithResults($sql).Tables
            return $datatable
        }
        else {
            # support multiple active nodes on SQL Server 2012 and above.
            if ($server.VersionMajor -ge 11) {
                $sql = "Select nodename FROM sys.dm_os_cluster_nodes where is_current_owner = 1"
                $datatable = $server.ConnectionContext.ExecuteWithResults($sql).Tables.NodeName
                return $datatable
            }
            else {
                return $computername
            }
        }
    }

    end {
        $server.ConnectionContext.Disconnect()
    }
}

