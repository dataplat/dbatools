function Get-DbaFilestream {
    <#
    .SYNOPSIS
        Returns the status of Filestream on specified SQL Server for both the Service and Instance levels.

    .DESCRIPTION
        Returns the status of Filestream on specified SQL Server for both the Service and Instance levels.

    .PARAMETER SqlInstance
        SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Defaults to localhost.

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
        Author: Stuart Moore ( @napalmgram ) | Chrissy LeMaire ( @cl )
        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaFilestream

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
            Write-Message -Level Verbose -Message "Connecting to $instance."
            $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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

        [PsCustomObject]@{
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