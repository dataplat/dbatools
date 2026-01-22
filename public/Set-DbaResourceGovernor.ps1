function Set-DbaResourceGovernor {
    <#
    .SYNOPSIS
        Configures SQL Server Resource Governor to control workload resource allocation and sets classifier functions.

    .DESCRIPTION
        Configures Resource Governor settings at the SQL Server instance level to control CPU, memory, and I/O resource allocation for different workloads. Resource Governor requires both being enabled on the instance and having an optional classifier function that determines which resource pool and workload group incoming sessions should use based on login properties, application name, or other criteria.

        This function handles the two-step Resource Governor setup process: enabling the feature and optionally assigning a classifier function. The classifier function must be a user-defined function in the master database that returns a workload group name or ID. Without a classifier function, all sessions use the default workload group.

        Commonly used when implementing resource management policies to prevent resource-intensive queries from impacting critical applications, or to allocate guaranteed resources to specific users or applications during peak usage periods.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Credential object used to connect to the Windows server as a different user

    .PARAMETER Enabled
        Enables Resource Governor on the SQL Server instance to activate workload resource management.
        Use this when you need to enforce resource limits and allocations for different workload groups.

    .PARAMETER Disabled
        Disables Resource Governor on the SQL Server instance, removing all resource controls and workload management.
        All sessions will use unlimited resources from the default resource pool when Resource Governor is disabled.

    .PARAMETER ClassifierFunction
        Specifies the name of a user-defined function in the master database that determines which workload group incoming sessions should use.
        The function must return a workload group name or ID based on session properties like login name or application name. Use 'NULL' to remove the current classifier function and route all sessions to the default workload group.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: ResourceGovernor
        Author: John McCall (@lowlydba), lowlydba.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaResourceGovernor

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.ResourceGovernor

        Returns the modified Resource Governor object reflecting the new enabled/disabled state and classifier function assignment. Output is piped from Get-DbaResourceGovernor which provides detailed configuration details.

        Default display properties (via Get-DbaResourceGovernor):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - ClassifierFunction: The fully qualified name of the Resource Governor classifier function (e.g., [dbo].[fn_classifier])
        - Enabled: Boolean indicating if Resource Governor is enabled on the instance
        - MaxOutstandingIOPerVolume: Maximum number of outstanding I/O operations allowed per disk volume
        - ReconfigurePending: Boolean indicating if a Resource Governor configuration change is pending and requires ALTER RESOURCE GOVERNOR RECONFIGURE
        - ResourcePools: Collection of ResourcePool objects defined on the instance
        - ExternalResourcePools: Collection of ExternalResourcePool objects for machine learning workloads (SQL Server 2016+)

        All properties from the base SMO ResourceGovernor object are accessible using Select-Object *.

    .EXAMPLE
        PS C:\> Set-DbaResourceGovernor -SqlInstance sql2016 -Enabled

        Sets Resource Governor to enabled for the instance sql2016.

    .EXAMPLE
        PS C:\> Set-DbaResourceGovernor -SqlInstance sql2012\dev1 -Disabled

        Sets Resource Governor to disabled for the instance dev1 on sq2012.

    .EXAMPLE
        PS C:\> Set-DbaResourceGovernor -SqlInstance sql2012\dev1 -ClassifierFunction 'fnRGClassifier' -Enabled

        Sets Resource Governor to enabled for the instance dev1 on sq2012 and sets the classifier function to be 'fnRGClassifier'.

    .EXAMPLE
        PS C:\> Set-DbaResourceGovernor -SqlInstance sql2012\dev1 -ClassifierFunction 'NULL' -Enabled

        Sets Resource Governor to enabled for the instance dev1 on sq2012 and sets the classifier function to be NULL.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]$SqlCredential,
        [switch]$Enabled,
        [switch]$Disabled,
        [string]$ClassifierFunction,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $resourceGovernorState = [bool]$server.ResourceGovernor.Enabled
            $resourceGovernorClassifierFunction = [string]$server.ResourceGovernor.ClassifierFunction

            # Set Enabled status
            if ($Enabled) {
                if ($PSCmdlet.ShouldProcess($instance, "Changing Resource Governor enabled from '$resourceGovernorState' to 'True' at the instance level")) {
                    try {
                        $server.ResourceGovernor.Enabled = $true
                    } catch {
                        Stop-Function -Message "Couldn't enable Resource Governor" -ErrorRecord $_ -Continue
                    }
                }
            } elseif ($Disabled) {
                if ($PSCmdlet.ShouldProcess($instance, "Changing Resource Governor enabled from '$resourceGovernorState' to 'False' at the instance level")) {
                    try {
                        $server.ResourceGovernor.Enabled = $false
                    } catch {
                        Stop-Function -Message "Couldn't disable Resource Governor" -ErrorRecord $_ -Continue
                    }
                }
            }

            # Set Classifier Function
            if ($ClassifierFunction) {
                if ($PSCmdlet.ShouldProcess($instance, "Changing Resource Governor Classifier Function from '$resourceGovernorClassifierFunction' to '$ClassifierFunction'")) {
                    if ($ClassifierFunction -eq "NULL") {
                        $server.ResourceGovernor.ClassifierFunction = $ClassifierFunction
                    } else {
                        $objClassifierFunction = Get-DbaDbUdf -SqlInstance $instance -SqlCredential $SqlCredential -Database "master" -Name $ClassifierFunction
                        if ($objClassifierFunction) {
                            $server.ResourceGovernor.ClassifierFunction = $objClassifierFunction
                        } else {
                            Stop-Function -Message "Classifier function '$ClassifierFunction' does not exist." -Category ObjectNotFound -Continue
                        }
                    }
                }
            }

            # Execute
            if ($PSCmdlet.ShouldProcess($instance, "Changing Resource Governor")) {
                $server.ResourceGovernor.Alter()
                $server.ResourceGovernor.Refresh()
            }

            Get-DbaResourceGovernor -SqlInstance $server
        }
    }
}