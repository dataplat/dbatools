function Get-DbaReplServer {
    <#
    .SYNOPSIS
        Retrieves replication configuration and server role information from SQL Server instances

    .DESCRIPTION
        Returns a ReplicationServer object that shows whether each SQL Server instance is configured as a distributor, publisher, or both in the replication topology. This helps DBAs quickly identify server roles and distribution database configurations when troubleshooting replication issues or documenting replication environments. The function reveals which databases are enabled for replication, though these may not necessarily be actively replicated.

        Note: The ReplicationDatabases property gets the databases enabled for replication in the connected instance of Microsoft SQL Server/.
        Not necessarily the databases that are actually replicated.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Replication
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaReplServer

    .EXAMPLE
        PS C:\> Get-DbaReplServer -SqlInstance sql2016

        Gets the replication server object for sql2016 using Windows authentication

    .EXAMPLE
        PS C:\> Get-DbaReplServer -SqlInstance sql2016 -SqlCredential repadmin

        Gets the replication server object for sql2016 using SQL authentication

    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
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
                $replServer = New-Object Microsoft.SqlServer.Replication.ReplicationServer
                $replServer.ConnectionContext = $Server.ConnectionContext
                $replServer | Add-Member -Type NoteProperty -Name ComputerName -Value $server.ComputerName -Force
                $replServer | Add-Member -Type NoteProperty -Name InstanceName -Value $server.ServiceName -Force
                $replServer | Add-Member -Type NoteProperty -Name SqlInstance -Value $server.DomainInstanceName -Force

                Select-DefaultView -InputObject $replServer -Property ComputerName, InstanceName, SqlInstance, IsDistributor, IsPublisher, DistributionServer, DistributionDatabase
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
        }
    }
}