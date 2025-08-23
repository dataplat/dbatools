function Disable-DbaFilestream {
    <#
    .SYNOPSIS
        Disables SQL Server FileStream functionality at both the service and instance levels

    .DESCRIPTION
        Disables the FileStream feature completely by setting the FilestreamAccessLevel configuration to 0 (disabled) and modifying the corresponding Windows service settings. This is useful when FileStream was previously enabled but is no longer needed, during security hardening, or when troubleshooting FileStream-related issues.

        The function handles both standalone and clustered SQL Server instances, automatically detecting cluster nodes and applying changes across all nodes. Since disabling FileStream requires changes at both the SQL instance configuration level and the Windows service level, a SQL Server service restart is required for the changes to take effect.

        By default, the function will prompt for confirmation before making changes due to the high impact nature of this operation. Use -Force to bypass confirmation and automatically restart the SQL Server service, or run without -Force to make the configuration changes and restart manually later.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Defaults to localhost.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Credential
        Login to the target server using alternative credentials.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Force
        Bypasses confirmation prompts and automatically restarts the SQL Server service to apply FileStream configuration changes immediately.
        Without this parameter, the function makes configuration changes but requires you to manually restart the SQL service later for changes to take effect.
        Use with caution in production environments as it causes service downtime during the restart.

    .PARAMETER WhatIf
        Shows what would happen if the command runs. The command is not run unless Force is specified.

    .PARAMETER Confirm
        Prompts you for confirmation before running the command.

    .NOTES
        Tags: Filestream
        Author: Stuart Moore (@napalmgram) | Chrissy LeMaire (@cl)
        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Disable-DbaFilestream

    .EXAMPLE
        PS C:\> Disable-DbaFilestream -SqlInstance server1\instance2

        Prompts for confirmation. Disables filestream on the service and instance levels.

    .EXAMPLE
        PS C:\> Disable-DbaFilestream -SqlInstance server1\instance2 -Confirm:$false

        Does not prompt for confirmation. Disables filestream on the service and instance levels.

    .EXAMPLE
        PS C:\> Get-DbaFilestream -SqlInstance server1\instance2, server5\instance5, prod\hr | Where-Object InstanceAccessLevel -gt 0 | Disable-DbaFilestream -Force

        Using this pipeline you can scan a range of SQL instances and disable filestream on only those on which it's enabled.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [DbaInstance[]]$SqlInstance,
        [Parameter(ValueFromPipelineByPropertyName)]
        [PSCredential]$SqlCredential,
        [Parameter(ValueFromPipelineByPropertyName)]
        [PSCredential]$Credential,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        $FileStreamLevel = $level = 0

        $OutputLookup = @{
            0 = 'Disabled'
            1 = 'FileStream enabled for T-Sql access'
            2 = 'FileStream enabled for T-Sql and IO streaming access'
            3 = 'FileStream enabled for T-Sql, IO streaming, and remote clients'
        }

        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # Instance level
            $filestreamstate = [int]$server.Configuration.FilestreamAccessLevel.RunValue

            if ($Force -or $PSCmdlet.ShouldProcess($instance, "Changing from '$($OutputLookup[$filestreamstate])' to '$($OutputLookup[$level])' at the instance level")) {
                try {
                    $null = Set-DbaSpConfigure -SqlInstance $server -Name FilestreamAccessLevel -Value $level -EnableException
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                }


                # Server level
                if ($server.IsClustered) {
                    $nodes = Get-DbaWsfcNode -ComputerName $instance -Credential $Credential
                    foreach ($node in $nodes.Name) {
                        $result = Set-FileSystemSetting -Instance $node -Credential $Credential -FilestreamLevel $FileStreamLevel
                    }
                } else {
                    $result = Set-FileSystemSetting -Instance $instance -Credential $Credential -FilestreamLevel $FileStreamLevel
                }

                if ($Force) {
                    #$restart replaced with $null as it was identified as a unused variable
                    $null = Restart-DbaService -ComputerName $instance.ComputerName -InstanceName $server.ServiceName -Type Engine -Force
                }

                Get-DbaFilestream -SqlInstance $instance -SqlCredential $SqlCredential -Credential $Credential

                if ($filestreamstate -ne $level -and -not $Force) {
                    Write-Message -Level Warning -Message "[$instance] $result"
                }
            }
        }
    }
}