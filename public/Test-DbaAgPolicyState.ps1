function Test-DbaAgPolicyState {
    <#
    .SYNOPSIS
        Tests Availability Group health against Microsoft's Always On predefined policies.

    .DESCRIPTION
        Evaluates the health of SQL Server Availability Groups by checking them against
        Microsoft's predefined Always On policies from the Policy-Based Management framework.

        Returns one object per policy evaluated, including whether the policy check passed
        (IsHealthy), the policy name, category, facet, issue description, and details.

        Based on the Microsoft documentation at:
        https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/always-on-policies-for-operational-issues-always-on-availability

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER AvailabilityGroup
        Specifies which availability groups to evaluate. If not specified, all availability groups are evaluated.

    .PARAMETER Secondary
        Specifies secondary replica endpoints when they use non-standard ports or custom connection strings.

    .PARAMETER SecondarySqlCredential
        Specifies credentials for connecting to secondary replica instances.

    .PARAMETER InputObject
        Accepts availability group objects from Get-DbaAvailabilityGroup via pipeline input.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: AvailabilityGroup, HA, AG, Test, Policy
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2026 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaAgPolicyState

    .OUTPUTS
        PSCustomObject

        Returns one object per policy evaluated. Properties:
        - ComputerName: The computer name of the SQL Server instance (string)
        - InstanceName: The SQL Server instance name (string)
        - SqlInstance: The full SQL Server instance name (string)
        - AvailabilityGroup: Name of the availability group (string)
        - PolicyName: The name of the Always On policy being evaluated (string)
        - Category: The severity of the policy - Critical or Warning (string)
        - Facet: The object type the policy applies to (string)
        - IsHealthy: Boolean indicating whether the policy check passed (bool)
        - Issue: Description of the issue when the policy is not healthy (string)
        - Details: Additional detail about the current state (string)

    .EXAMPLE
        PS C:\> Test-DbaAgPolicyState -SqlInstance sql2019 -AvailabilityGroup TestAG

        Evaluates all predefined Always On policies for the availability group TestAG on sql2019.

    .EXAMPLE
        PS C:\> Test-DbaAgPolicyState -SqlInstance sql2019

        Evaluates all predefined Always On policies for all availability groups on sql2019.

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sql2019 | Test-DbaAgPolicyState

        Evaluates all predefined Always On policies for all availability groups on sql2019 using pipeline input.
    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$AvailabilityGroup,
        [DbaInstanceParameter[]]$Secondary,
        [PSCredential]$SecondarySqlCredential,
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
            $InputObject += Get-DbaAvailabilityGroup -SqlInstance $SqlInstance -SqlCredential $SqlCredential -AvailabilityGroup $AvailabilityGroup
        }

        foreach ($ag in $InputObject) {
            $server = $ag.Parent

            <#
            WSFC cluster service is offline
            Documentation: https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/wsfc-cluster-service-is-offline
            Policy Name: WSFC Cluster State
            Issue: WSFC cluster service is offline.
            Category: Critical
            Facet: Instance of SQL Server

            Name           : AlwaysOnAgWSFClusterHealthCondition
            Facet          : Server
            ExpressionNode : @ClusterQuorumState = Enum('Microsoft.SqlServer.Management.Smo.ClusterQuorumState', 'NormalQuorum')
            #>

            $isHealthy = $server.ClusterQuorumState -eq "NormalQuorum"
            [PSCustomObject]@{
                ComputerName      = $ag.ComputerName
                InstanceName      = $ag.InstanceName
                SqlInstance       = $ag.SqlInstance
                AvailabilityGroup = $ag.Name
                PolicyName        = "WSFC Cluster State"
                Category          = "Critical"
                Facet             = "Instance of SQL Server"
                IsHealthy         = $isHealthy
                Issue             = "WSFC cluster service is offline."
                Details           = "ClusterQuorumState is $($server.ClusterQuorumState)"
            }

            $agState = New-Object -TypeName "Microsoft.SqlServer.Management.Smo.AvailabilityGroupState" -ArgumentList $ag

            <#
            Always On Availability group is offline
            Documentation: https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/availability-group-is-offline
            Policy Name: Availability Group Online State
            Issue: Availability group is offline.
            Category: Critical
            Facet: Availability group

            Name           : AlwaysOnAgOnlineStateHealthCondition
            Facet          : IAvailabilityGroupState
            ExpressionNode : @IsOnline = True()
            #>

            [PSCustomObject]@{
                ComputerName      = $ag.ComputerName
                InstanceName      = $ag.InstanceName
                SqlInstance       = $ag.SqlInstance
                AvailabilityGroup = $ag.Name
                PolicyName        = "Availability Group Online State"
                Category          = "Critical"
                Facet             = "Availability group"
                IsHealthy         = $agState.IsOnline
                Issue             = "Availability group is offline."
                Details           = "IsOnline is $($agState.IsOnline)"
            }

            <#
            Always On availability group is not ready for automatic failover
            Documentation: https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/availability-group-is-not-ready-for-automatic-failover
            Policy Name: Availability Group Automatic Failover Readiness
            Issue: Availability group is not ready for automatic failover.
            Category: Critical
            Facet: Availability group

            Name           : AlwaysOnAgAutomaticFailoverHealthCondition
            Facet          : IAvailabilityGroupState
            ExpressionNode : (@IsAutoFailover = True() AND @NumberOfSynchronizedSecondaryReplicas > 0) OR @IsAutoFailover = False()
            #>

            $isHealthy = (-not $agState.IsAutoFailover) -or ($agState.NumberOfSynchronizedSecondaryReplicas -gt 0)
            [PSCustomObject]@{
                ComputerName      = $ag.ComputerName
                InstanceName      = $ag.InstanceName
                SqlInstance       = $ag.SqlInstance
                AvailabilityGroup = $ag.Name
                PolicyName        = "Availability Group Automatic Failover Readiness"
                Category          = "Critical"
                Facet             = "Availability group"
                IsHealthy         = $isHealthy
                Issue             = "Availability group is not ready for automatic failover."
                Details           = "IsAutoFailover is $($agState.IsAutoFailover), NumberOfSynchronizedSecondaryReplicas is $($agState.NumberOfSynchronizedSecondaryReplicas)"
            }

            <#
            Some availability replicas are disconnected
            Documentation: https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/some-availability-replicas-are-disconnected
            Policy Name: Availability Replicas Connection State
            Issue: Some availability replicas are disconnected.
            Category: Warning
            Facet: Availability group

            Name           : AlwaysOnAgReplicasConnectionHealthCondition
            Facet          : IAvailabilityGroupState
            ExpressionNode : @NumberOfDisconnectedReplicas = 0
            #>

            $isHealthy = $agState.NumberOfDisconnectedReplicas -eq 0
            [PSCustomObject]@{
                ComputerName      = $ag.ComputerName
                InstanceName      = $ag.InstanceName
                SqlInstance       = $ag.SqlInstance
                AvailabilityGroup = $ag.Name
                PolicyName        = "Availability Replicas Connection State"
                Category          = "Warning"
                Facet             = "Availability group"
                IsHealthy         = $isHealthy
                Issue             = "Some availability replicas are disconnected."
                Details           = "NumberOfDisconnectedReplicas is $($agState.NumberOfDisconnectedReplicas)"
            }

            <#
            Some availability replicas are not synchronizing data
            Documentation: https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/some-availability-replicas-are-not-synchronizing-data
            Policy Name: Availability Replicas Data Synchronization State
            Issue: Some availability replicas are not synchronizing data.
            Category: Warning
            Facet: Availability group

            Name           : AlwaysOnAgReplicasDataSynchronizationHealthCondition
            Facet          : IAvailabilityGroupState
            ExpressionNode : @NumberOfNotSynchronizingReplicas = 0
            #>

            $isHealthy = $agState.NumberOfNotSynchronizingReplicas -eq 0
            [PSCustomObject]@{
                ComputerName      = $ag.ComputerName
                InstanceName      = $ag.InstanceName
                SqlInstance       = $ag.SqlInstance
                AvailabilityGroup = $ag.Name
                PolicyName        = "Availability Replicas Data Synchronization State"
                Category          = "Warning"
                Facet             = "Availability group"
                IsHealthy         = $isHealthy
                Issue             = "Some availability replicas are not synchronizing data."
                Details           = "NumberOfNotSynchronizingReplicas is $($agState.NumberOfNotSynchronizingReplicas)"
            }

            <#
            Some availability replicas do not have a healthy role
            Documentation: https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/some-availability-replicas-do-not-have-a-healthy-role
            Policy Name: Availability Replicas Role State
            Issue: Some availability replicas do not have a healthy role.
            Category: Warning
            Facet: Availability group

            Name           : AlwaysOnAgReplicasRoleHealthCondition
            Facet          : IAvailabilityGroupState
            ExpressionNode : @NumberOfReplicasWithUnhealthyRole = 0
            #>

            $isHealthy = $agState.NumberOfReplicasWithUnhealthyRole -eq 0
            [PSCustomObject]@{
                ComputerName      = $ag.ComputerName
                InstanceName      = $ag.InstanceName
                SqlInstance       = $ag.SqlInstance
                AvailabilityGroup = $ag.Name
                PolicyName        = "Availability Replicas Role State"
                Category          = "Warning"
                Facet             = "Availability group"
                IsHealthy         = $isHealthy
                Issue             = "Some availability replicas do not have a healthy role."
                Details           = "NumberOfReplicasWithUnhealthyRole is $($agState.NumberOfReplicasWithUnhealthyRole)"
            }

            <#
            Some synchronous replicas are not synchronized
            Documentation: https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/some-synchronous-replicas-are-not-synchronized
            Policy Name: Synchronous Replicas Data Synchronization State
            Issue: Some synchronous replicas are not synchronized.
            Category: Warning
            Facet: Availability group

            Name           : AlwaysOnAgSynchronousReplicasDataSynchronizationHealthCondition
            Facet          : IAvailabilityGroupState
            ExpressionNode : @NumberOfNotSynchronizedReplicas = 0
            #>

            $isHealthy = $agState.NumberOfNotSynchronizedReplicas -eq 0
            [PSCustomObject]@{
                ComputerName      = $ag.ComputerName
                InstanceName      = $ag.InstanceName
                SqlInstance       = $ag.SqlInstance
                AvailabilityGroup = $ag.Name
                PolicyName        = "Synchronous Replicas Data Synchronization State"
                Category          = "Warning"
                Facet             = "Availability group"
                IsHealthy         = $isHealthy
                Issue             = "Some synchronous replicas are not synchronized."
                Details           = "NumberOfNotSynchronizedReplicas is $($agState.NumberOfNotSynchronizedReplicas)"
            }
        }
    }
}
