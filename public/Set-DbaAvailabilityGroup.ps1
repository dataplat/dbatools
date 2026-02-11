function Set-DbaAvailabilityGroup {
    <#
    .SYNOPSIS
        Modifies availability group configuration settings including DTC support, backup preferences, and failover conditions

    .DESCRIPTION
        Modifies configuration properties of existing availability groups without requiring you to script out and recreate the entire AG setup. Commonly used to enable DTC support for distributed transactions, adjust automated backup preferences across replicas, configure failure condition levels for automatic failover, and set health check timeouts for monitoring. This saves time compared to using SQL Server Management Studio or T-SQL ALTER AVAILABILITY GROUP statements for routine configuration changes.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER AvailabilityGroup
        Specifies the name(s) of specific availability groups to modify. Accepts multiple AG names as an array.
        Use this to target individual AGs instead of modifying all AGs on the instance.

    .PARAMETER AllAvailabilityGroups
        Modifies configuration settings for every availability group on the target SQL Server instance.
        Use this switch when you need to apply the same configuration changes across all AGs simultaneously.

    .PARAMETER DtcSupportEnabled
        Enables or disables Distributed Transaction Coordinator (DTC) support for the availability group.
        Required when applications use distributed transactions across multiple databases in the AG. Set to $false to disable DTC support.

    .PARAMETER ClusterType
        Specifies the clustering technology used by the availability group. Only supported in SQL Server 2017 and above.
        Use 'Wsfc' for Windows Server Failover Clustering, 'External' for third-party cluster managers like Pacemaker on Linux, or 'None' for read-scale AGs without automatic failover.

    .PARAMETER AutomatedBackupPreference
        Controls which replica should be preferred for automated backup operations within the availability group.
        Use 'Secondary' to offload backups from the primary, 'SecondaryOnly' to prevent backups on primary, 'Primary' to always backup on primary, or 'None' to disable preference-based backup routing.

    .PARAMETER FailureConditionLevel
        Sets the sensitivity level for automatic failover conditions in the availability group.
        Use 'OnServerDown' for basic failover, 'OnServerUnresponsive' for SQL Service issues, 'OnCriticalServerErrors' for critical SQL errors, 'OnModerateServerErrors' for moderate SQL errors, or 'OnAnyQualifiedFailureCondition' for maximum sensitivity.

    .PARAMETER HealthCheckTimeout
        Sets the timeout in milliseconds for health check responses from sp_server_diagnostics before marking the AG as unresponsive.
        Increase this value for busy systems or slow storage to reduce false failovers. Decrease for faster failover detection in stable environments.
        Default is 30000 (30 seconds). Changes take effect immediately without restart.

    .PARAMETER BasicAvailabilityGroup
        Configures the availability group as a Basic AG with limited functionality for Standard Edition licensing.
        Basic AGs support only one database, two replicas, and no read-access to secondary replicas. Used when full AG features aren't needed or licensed.

    .PARAMETER DatabaseHealthTrigger
        Enables database-level health monitoring that can trigger automatic failovers based on individual database health status.
        When enabled, databases that become offline or experience critical errors can initiate AG failover. Useful for comprehensive monitoring beyond SQL Server instance health.

    .PARAMETER IsDistributedAvailabilityGroup
        Configures the availability group as a Distributed AG that spans multiple WSFC clusters or standalone instances.
        Used for disaster recovery scenarios across geographic locations or different domains. Requires SQL Server 2016 or later.

    .PARAMETER ClusterConnectionOption
        Specifies connection options for TDS 8.0 support in SQL Server 2025 and above.
        This allows the Windows Server Failover Cluster (WSFC) to connect to SQL Server instances using ODBC with TLS 1.3 encryption.
        The value is a string containing semicolon-delimited key-value pairs.

        Available keys:
        - Encrypt: Controls connection encryption
        - TrustServerCertificate: Whether to trust the server certificate
        - HostNameInCertificate: Expected hostname in the certificate
        - ServerCertificate: Path to server certificate

        This setting is persisted by WSFC in the registry and used continuously for cluster-to-instance communication.
        Note: PowerShell does not validate these values - invalid combinations will be rejected by SMO or the ODBC driver.

        Example: "Encrypt=Strict;TrustServerCertificate=False"

        For detailed documentation, see:
        https://learn.microsoft.com/en-us/sql/t-sql/statements/alter-availability-group-transact-sql

    .PARAMETER InputObject
        Accepts availability group objects from Get-DbaAvailabilityGroup for pipeline operations.
        Use this to pipe specific AG objects directly to the function instead of specifying SqlInstance and AG names separately.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: AG, HA
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaAvailabilityGroup

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.AvailabilityGroup

        Returns one AvailabilityGroup object per availability group that was modified. The object contains the updated configuration properties that were changed by this command. Unlike Get-DbaAvailabilityGroup, this command returns the raw SMO object without Select-DefaultView applied.

        Properties available on the returned object include:
        - Name: Name of the availability group
        - AvailabilityReplicas: Collection of replica instances in the AG
        - AutomatedBackupPreference: Current backup preference (None, Primary, Secondary, SecondaryOnly)
        - BasicAvailabilityGroup: Boolean indicating if the AG is a Basic AG (Standard Edition)
        - ClusterType: Clustering technology used (Wsfc, External, None) - SQL Server 2017+
        - DatabaseHealthTrigger: Boolean indicating if database health triggers failover
        - DtcSupportEnabled: Boolean indicating if Distributed Transaction Coordinator support is enabled
        - FailureConditionLevel: Failover sensitivity level (OnServerDown, OnServerUnresponsive, OnCriticalServerErrors, OnModerateServerErrors, OnAnyQualifiedFailureCondition)
        - HealthCheckTimeout: Health check timeout in milliseconds
        - IsDistributedAvailabilityGroup: Boolean indicating if this is a Distributed AG (SQL Server 2016+)
        - ClusterConnectionOptions: Connection options for WSFC communication (SQL Server 2025+)
        - Parent: Reference to the parent SQL Server object

        All properties from the base SMO AvailabilityGroup object are accessible using Select-Object *.

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sql2016 | Set-DbaAvailabilityGroup -DtcSupportEnabled

        Enables DTC for all availability groups on sql2016

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sql2016 -AvailabilityGroup AG1 | Set-DbaAvailabilityGroup -DtcSupportEnabled:$false

        Disables DTC support for the availability group AG1

    .EXAMPLE
        PS C:\> Set-DbaAvailabilityGroup -SqlInstance sql2016 -AvailabilityGroup AG1 -DtcSupportEnabled:$false

        Disables DTC support for the availability group AG1
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$AvailabilityGroup,
        [switch]$AllAvailabilityGroups,
        [switch]$DtcSupportEnabled,
        [ValidateSet('External', 'Wsfc', 'None')]
        [string]$ClusterType,
        [ValidateSet('None', 'Primary', 'Secondary', 'SecondaryOnly')]
        [string]$AutomatedBackupPreference,
        [ValidateSet('OnAnyQualifiedFailureCondition', 'OnCriticalServerErrors', 'OnModerateServerErrors', 'OnServerDown', 'OnServerUnresponsive')]
        [string]$FailureConditionLevel,
        [int]$HealthCheckTimeout,
        [switch]$BasicAvailabilityGroup,
        [switch]$DatabaseHealthTrigger,
        [switch]$IsDistributedAvailabilityGroup,
        [string]$ClusterConnectionOption,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if (Test-Bound -Not SqlInstance, InputObject) {
            Stop-Function -Message "You must supply either -SqlInstance or an Input Object"
            return
        }

        if ((Test-Bound -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName AvailabilityGroup, AllAvailabilityGroups)) {
            Stop-Function -Message "You must specify AllAvailabilityGroups groups or AvailabilityGroups when using the SqlInstance parameter."
            return
        }
        if ($SqlInstance) {
            $InputObject += Get-DbaAvailabilityGroup -SqlInstance $SqlInstance -SqlCredential $SqlCredential -AvailabilityGroup $AvailabilityGroup
        }
        $props = "Name", "AutomatedBackupPreference", "BasicAvailabilityGroup", "ClusterType", "DatabaseHealthTrigger", "DtcSupportEnabled", "FailureConditionLevel", "HealthCheckTimeout", "IsDistributedAvailabilityGroup"

        foreach ($ag in $InputObject) {
            try {
                if ($Pscmdlet.ShouldProcess($ag.Parent.Name, "Seting properties on $ag")) {
                    foreach ($prop in $props) {
                        if (Test-Bound -ParameterName $prop) {
                            $ag.$prop = (Get-Variable -Name $prop -ValueOnly)
                        }
                    }

                    # ClusterConnectionOption requires SQL Server 2025+ (version 17)
                    if ((Test-Bound -ParameterName ClusterConnectionOption)) {
                        if ($ag.Parent.VersionMajor -ge 17) {
                            $ag.ClusterConnectionOptions = $ClusterConnectionOption
                        } else {
                            Write-Message -Level Warning -Message "ClusterConnectionOption is only supported in SQL Server 2025 and above. Skipping this setting on $($ag.Parent.Name)."
                        }
                    }

                    $ag.Alter()
                    $ag
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
            }
        }
    }
}