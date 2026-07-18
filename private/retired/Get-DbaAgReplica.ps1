function Get-DbaAgReplica {
    <#
    .SYNOPSIS
        Retrieves availability group replica configuration and status information from SQL Server instances.

    .DESCRIPTION
        Retrieves detailed information about availability group replicas including their current role, connection state, synchronization status, and failover configuration. This function helps DBAs monitor replica health, verify failover readiness, and troubleshoot availability group issues without manually querying system views. Returns comprehensive replica properties like backup priority, endpoint URLs, session timeouts, and read-only routing lists for availability group management and compliance reporting.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER AvailabilityGroup
        Specifies which availability groups to query for replica information. Accepts multiple values and wildcards for pattern matching.
        Use this when you need to focus on specific availability groups instead of retrieving replicas from all AGs on the instance.

    .PARAMETER Replica
        Filters results to return only the specified replica names. Accepts multiple values for querying specific replicas across availability groups.
        Use this when troubleshooting specific replicas or when you only need information about particular secondary replicas in your environment.

    .PARAMETER InputObject
        Accepts availability group objects piped from Get-DbaAvailabilityGroup, allowing for more efficient processing in pipeline scenarios.
        Use this when chaining commands or when you already have availability group objects and want to retrieve their replica details without additional server queries.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: AG, HA
        Author: Shawn Melton (@wsmelton) | Chrissy LeMaire (@cl)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaAgReplica

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.AvailabilityReplica

        Returns one AvailabilityReplica object per replica found in the queried availability groups. The objects include added properties for context about the parent SQL Server instance and availability group.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance hosting the replica
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - AvailabilityGroup: Name of the availability group that contains this replica
        - Name: The name/display name of the availability group replica
        - Role: Current role of the replica (Primary or Secondary)
        - ConnectionState: Current connectivity state with the local server (Connected, Disconnected, etc.)
        - RollupSynchronizationState: Overall database synchronization state (NotSynchronizing, Synchronizing, Synchronized, Reverting, Initializing)
        - AvailabilityMode: Commit mode (SynchronousCommit or AsynchronousCommit)
        - BackupPriority: Backup preference priority value (0-100, where higher values are preferred for backups)
        - EndpointUrl: Database mirroring endpoint URL used for replica communication (format: TCP://hostname:port)
        - SessionTimeout: Session timeout in seconds for detecting communication failures (minimum 10 seconds recommended)
        - FailoverMode: Failover capability (Automatic or Manual)
        - ReadonlyRoutingList: Priority-ordered list of secondary replicas for routing read-only connections

        Additional properties available (from SMO AvailabilityReplica object):
        - ConnectionModeInPrimaryRole: Connection mode when this replica is primary (AllowAllConnections or AllowReadWriteConnections)
        - ConnectionModeInSecondaryRole: Connection mode when this replica is secondary (AllowNoConnections, AllowReadIntentConnectionsOnly, or AllowAllConnections)
        - ReadonlyRoutingConnectionUrl: Connection URL used by read-only routing for this replica
        - SeedingMode: Database seeding mode (Automatic or Manual) - SQL Server 2016+
        - Parent: Reference to the parent AvailabilityGroup object
        - State: The state of the SMO object (Existing, Creating, Pending, etc.)
        - Urn: Uniform resource name for programmatic identification of the replica

        All properties from the base SMO AvailabilityReplica object are accessible using Select-Object *, even though only default properties are displayed by default.

    .EXAMPLE
        PS C:\> Get-DbaAgReplica -SqlInstance sql2017a

        Returns basic information on all the availability group replicas found on sql2017a

    .EXAMPLE
        PS C:\> Get-DbaAgReplica -SqlInstance sql2017a -AvailabilityGroup SharePoint

        Shows basic information on the replicas found on availability group SharePoint on sql2017a

    .EXAMPLE
        PS C:\> Get-DbaAgReplica -SqlInstance sql2017a | Select-Object *

        Returns full object properties on all availability group replicas found on sql2017a
    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$AvailabilityGroup,
        [string[]]$Replica,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if (Test-Bound -Not SqlInstance, InputObject) {
            Stop-Function -Message "You must supply either -SqlInstance or an Input Object"
            return
        }

        if ($SqlInstance) {
            try {
                $InputObject += Get-DbaAvailabilityGroup -SqlInstance $SqlInstance -SqlCredential $SqlCredential -AvailabilityGroup $AvailabilityGroup -EnableException
            } catch {
                Stop-Function -Message "Failure on $SqlInstance to obtain the availability group $AvailabilityGroup" -ErrorRecord $_
                return
            }
        }

        $availabilityReplicas = $InputObject.AvailabilityReplicas
        if ($Replica) {
            $availabilityReplicas = $InputObject.AvailabilityReplicas | Where-Object { $_.Name -in $Replica }
        }

        $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'AvailabilityGroup', 'Name', 'Role', 'ConnectionState', 'RollupSynchronizationState', 'AvailabilityMode', 'BackupPriority', 'EndpointUrl', 'SessionTimeout', 'FailoverMode', 'ReadonlyRoutingList'

        foreach ($agreplica in $availabilityReplicas) {
            Add-Member -Force -InputObject $agreplica -MemberType NoteProperty -Name ComputerName -value $agreplica.Parent.ComputerName
            Add-Member -Force -InputObject $agreplica -MemberType NoteProperty -Name InstanceName -value $agreplica.Parent.InstanceName
            Add-Member -Force -InputObject $agreplica -MemberType NoteProperty -Name SqlInstance -value $agreplica.Parent.SqlInstance
            Add-Member -Force -InputObject $agreplica -MemberType NoteProperty -Name AvailabilityGroup -value $agreplica.Parent.Name
            Add-Member -Force -InputObject $agreplica -MemberType NoteProperty -Name Replica -value $agreplica.Name # backwards compat

            Select-DefaultView -InputObject $agreplica -Property $defaults
        }
    }
}