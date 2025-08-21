function Enable-DbaFilestream {
    <#
    .SYNOPSIS
        Configures FILESTREAM feature at both instance and server levels on SQL Server

    .DESCRIPTION
        Configures SQL Server's FILESTREAM feature by setting the FilestreamAccessLevel at the instance level and enabling the Windows service component at the server level. The function supports three access levels: T-SQL only, T-SQL with I/O streaming, or T-SQL with I/O streaming and remote client access. FILESTREAM allows storing large binary data like documents, images, and videos directly on the file system while maintaining transactional consistency with the database. SQL Server requires a restart after enabling FILESTREAM, and the function will prompt for confirmation unless the -Force parameter is used.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Defaults to localhost.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Credential
        Login to the target server using alternative credentials.

    .PARAMETER FileStreamLevel
        The level to of FileStream to be enabled:
        1 or TSql - T-Sql Access Only
        2 or TSqlIoStreaming - T-Sql and Win32 access enabled
        3 or TSqlIoStreamingRemoteClient T-Sql, Win32 and Remote access enabled

    .PARAMETER ShareName
        Specifies the Windows file share name to be used for storing the FILESTREAM data.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Force
        Restart SQL Instance after changes. Use this parameter with care as it overrides whatif.

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
        https://dbatools.io/Enable-DbaFilestream

    .EXAMPLE
        PS C:\> Enable-DbaFilestream -SqlInstance server1\instance2 -FileStreamLevel TSql
        PS C:\> Enable-DbaFilestream -SqlInstance server1\instance2 -FileStreamLevel 1

        These commands are functionally equivalent, both will set Filestream level on server1\instance2 to T-Sql Only

    .EXAMPLE
        PS C:\> Get-DbaFilestream -SqlInstance server1\instance2, server5\instance5, prod\hr | Where-Object InstanceAccessLevel -eq 0 | Enable-DbaFilestream -FileStreamLevel TSqlIoStreamingRemoteClient -Force

        Using this pipeline you can scan a range of SQL instances and enable filestream on only those on which it's disabled.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [DbaInstance[]]$SqlInstance,
        [Parameter(ValueFromPipelineByPropertyName)]
        [PSCredential]$SqlCredential,
        [Parameter(ValueFromPipelineByPropertyName)]
        [PSCredential]$Credential,
        [ValidateSet("TSql", "TSqlIoStreaming", "TSqlIoStreamingRemoteClient", 1, 2, 3)]
        [string]$FileStreamLevel = 1,
        [string]$ShareName,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if ($FileStreamLevel -notin (1, 2, 3)) {
            $FileStreamLevel = switch ($FileStreamLevel) {
                "TSql" {
                    1
                }
                "TSqlIoStreaming" {
                    2
                }
                "TSqlIoStreamingRemoteClient" {
                    3
                }
            }
        }
        # = $finallevel removed as it was identified as a unused variable
        $level = [int]$FileStreamLevel
        $OutputLookup = @{
            0 = 'Disabled'
            1 = 'FileStream enabled for T-Sql access'
            2 = 'FileStream enabled for T-Sql and IO streaming access'
            3 = 'FileStream enabled for T-Sql, IO streaming, and remote clients'
        }

        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {
        if ($ShareName -and $level -lt 2) {
            Stop-Function -Message "Filestream must be at least level 2 when using ShareName"
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $filestreamstate = [int]$server.Configuration.FilestreamAccessLevel.ConfigValue

            if ($Force -or $PSCmdlet.ShouldProcess($instance, "Changing from '$($OutputLookup[$filestreamstate])' to '$($OutputLookup[$level])' at the instance level")) {
                # Server level
                if ($server.IsClustered) {
                    $nodes = Get-DbaWsfcNode -ComputerName $instance
                    foreach ($node in $nodes.Name) {
                        $result = Set-FileSystemSetting -Instance $node -Credential $Credential -ShareName $ShareName -FilestreamLevel $level
                    }
                } else {
                    $result = Set-FileSystemSetting -Instance $instance -Credential $Credential -ShareName $ShareName -FilestreamLevel $level
                }

                # Instance level
                if ($level -eq 3) {
                    $level = 2
                }

                try {
                    $null = Set-DbaSpConfigure -SqlInstance $server -Name FilestreamAccessLevel -Value $level -EnableException
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                }

                if ($Force) {
                    #$restart replaced with $null as it was identified as a unused variable
                    $null = Restart-DbaService -ComputerName $server.ComputerName -InstanceName $server.ServiceName -Type Engine -Force
                }

                Get-DbaFilestream -SqlInstance $instance -SqlCredential $SqlCredential -Credential $Credential
                if ($filestreamstate -ne $level -and -not $Force) {
                    Write-Message -Level Warning -Message "[$instance] $result"
                }
            }
        }
    }
}