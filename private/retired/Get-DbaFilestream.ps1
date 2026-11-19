function Get-DbaFilestream {
    <#
    .SYNOPSIS
        Retrieves FileStream configuration status at both the SQL Server service and instance levels.

    .DESCRIPTION
        Retrieves FileStream configuration status by checking both the SQL Server service configuration and the instance-level sp_configure settings. This function helps DBAs quickly identify FileStream configuration mismatches between service and instance levels, which are common causes of FileStream functionality issues. The function returns detailed access levels, share names, and indicates whether a restart is pending to apply configuration changes.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Credential
        Login to the target Windows server using alternative credentials.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Filestream
        Author: Stuart Moore (@napalmgram) | Chrissy LeMaire (@cl)
        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaFilestream

    .OUTPUTS
        PSCustomObject

        Returns one object per instance queried, containing both service-level and instance-level FileStream configuration status.

        Default display properties (via Select-DefaultView):
        - ComputerName: The name of the computer hosting the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - InstanceAccess: Human-readable description of instance-level FileStream access (Disabled, T-SQL access enabled, or Full access enabled)
        - ServiceAccess: Human-readable description of service-level FileStream access (Disabled, FileStream enabled for T-SQL access, FileStream enabled for T-SQL and IO streaming access, or FileStream enabled for T-SQL, IO streaming, and remote clients)
        - ServiceShareName: The Windows file share name used for FileStream when service-level access is enabled

        Additional properties available (via Select-Object *):
        - InstanceAccessLevel: Numeric code for instance-level FileStream access (0-2)
        - ServiceAccessLevel: Numeric code for service-level FileStream access (0-3)
        - Credential: The Windows credentials used for service-level queries (passed from -Credential parameter)
        - SqlCredential: The SQL Server credentials used for instance-level queries (passed from -SqlCredential parameter)

    .EXAMPLE
        PS C:\> Get-DbaFilestream -SqlInstance server1\instance2

        Will return the status of Filestream configuration for the service and instance server1\instance2

    .EXAMPLE
        PS C:\> Get-DbaFilestream -SqlInstance server1\instance2 -SqlCredential sqladmin

        Prompts for the password to the SQL Login "sqladmin" then returns the status of Filestream configuration for the service and instance server1\instance2
    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [PSCredential]$Credential,
        [switch]$EnableException
    )
    begin {
        $idServiceFS = [ordered]@{
            0 = 'Disabled'
            1 = 'FileStream enabled for T-Sql access'
            2 = 'FileStream enabled for T-Sql and IO streaming access'
            3 = 'FileStream enabled for T-Sql, IO streaming, and remote clients'
        }

        $idInstanceFS = [ordered]@{
            0 = 'Disabled'
            1 = 'T-SQL access enabled'
            2 = 'Full access enabled'
        }
    }
    process {
        foreach ($instance in $SqlInstance) {
            $computer = $instance.ComputerName
            $instanceName = $instance.InstanceName

            <# Get Service-Level information #>
            if ($instance.IsLocalHost) {
                $computerName = $computer
            } else {
                $computerName = (Resolve-DbaNetworkName -ComputerName $computer -Credential $Credential).FullComputerName
            }

            Write-Message -Level Verbose -Message "Attempting to connect to $computer"
            try {
                $ognamespace = Get-DbaCmObject -EnableException -ComputerName $computerName -Namespace root\Microsoft\SQLServer -Query "SELECT NAME FROM __NAMESPACE WHERE NAME LIKE 'ComputerManagement%'"
                $namespace = $ognamespace | Where-Object {
                    (Get-DbaCmObject -EnableException -ComputerName $computerName -Namespace $("root\Microsoft\SQLServer\" + $_.Name) -ClassName FilestreamSettings).Count -gt 0
                } |
                Sort-Object Name -Descending | Select-Object -First 1

            if (-not $namespace) {
                $namespace = $ognamespace
            }

            if ($namespace.Name) {
                $serviceFS = Get-DbaCmObject -EnableException -ComputerName $computerName -Namespace $("root\Microsoft\SQLServer\" + $namespace.Name) -ClassName FilestreamSettings | Where-Object InstanceName -eq $instanceName | Select-Object -First 1
            } else {
                Write-Message -Level Warning -Message "No ComputerManagement was found on $computer. Service level information may not be collected." -Target $computer
            }
        } catch {
            Stop-Function -Message "Issue collecting service-level information on $computer for $instanceName" -Target $computer -ErrorRecord $_ -Continue
        }

        <# Get Instance-Level information #>
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        }

        try {
            $instanceFS = Get-DbaSpConfigure -SqlInstance $server -Name FilestreamAccessLevel | Select-Object ConfiguredValue, RunningValue
        } catch {
            Stop-Function -Message "Issue collection instance-level configuration on $instanceName" -Target $server -ErrorRecord $_ -Exception $_.Exception -Continue
        }

        $pendingRestart = $instanceFS.ConfiguredValue -ne $instanceFS.RunningValue

        if (($serviceFS.AccessLevel -ne 0) -and ($instanceFS.RunningValue -ne 0)) {
            if (($serviceFS.AccessLevel -eq $instanceFS.RunningValue) -and $pendingRestart) {
                Write-Message -Level Verbose -Message "A restart of the instance is pending before Filestream is configured."
            }
        }

        $runvalue = (Get-DbaSpConfigure -SqlInstance $server -Name FilestreamAccessLevel | Select-Object RunningValue).RunningValue
        $servicelevel = [int]$serviceFS.AccessLevel

        [PSCustomObject]@{
            ComputerName        = $server.ComputerName
            InstanceName        = $server.ServiceName
            SqlInstance         = $server.DomainInstanceName
            InstanceAccess      = $idInstanceFS[$runvalue]
            ServiceAccess       = $idServiceFS[$servicelevel]
            ServiceShareName    = $serviceFS.ShareName
            InstanceAccessLevel = $instanceFS.RunningValue
            ServiceAccessLevel  = $serviceFS.AccessLevel
            Credential          = $Credential
            SqlCredential       = $SqlCredential
        } | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, InstanceAccess, ServiceAccess, ServiceShareName
    }
}
}