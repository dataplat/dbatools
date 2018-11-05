function Enable-DbaFileStream {
    <#
    .SYNOPSIS
        Enables FileStream on specified SQL Server instances

    .DESCRIPTION
        Connects to the specified SQL Server instances, and Enables the FileStream feature to the required value

        To perform the action, the SQL Server instance must be restarted. By default we will prompt for confirmation for this action, this can be overridden with the -Force switch

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Defaults to localhost.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

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
    	Restart SQL Instance after changes.

    .PARAMETER WhatIf
    	Shows what would happen if the command runs. The command is not run.

	.PARAMETER Confirm
	    Prompts you for confirmation before running the command.

    .NOTES
        Tags: Filestream
        Author: Stuart Moore ( @napalmgram )
        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .EXAMPLE
        Enable-DbaFileStream -SqlInstance server1\instance2 -FileStreamLevel TSql
        Enable-DbaFileStream -SqlInstance server1\instance2 -FileStreamLevel 1

        These commands are functionally equivalent, both will set Filestream level on server1\instance2 to T-Sql Only

    .EXAMPLE
        Get-DbaFileStream -SqlInstance server1\instance2, server5\instance5 , prod\hr | Where-Object {$_.FileSteamStateID -gt 0} | Enable-DbaFileStream -FileStreamLevel 0 -Force

        Using this pipeline you can scan a range of SQL instances and disable filestream on only those on which it's enabled

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [PSCredential]$Credential,
        [Parameter(Mandatory)]
        [ValidateSet("TSql", "TSqlIoStreaming", "TSqlIoStreamingRemoteClient", 1, 2, 3)]
        [string]$FileStreamLevel,
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
        $level = $finallevel = [int]$FileStreamLevel
        $OutputLookup = @{
            0 = 'Disabled'
            1 = 'FileStream enabled for T-Sql access'
            2 = 'FileStream enabled for T-Sql and IO streaming access'
            3 = 'FileStream enabled for T-Sql, IO streaming, and remote clients'
        }
    }
    process {
        if ($ShareName -and $level -lt 2) {
            Stop-Function -Message "Filestream must be at least level 2 when using ShareName"
            return
        }
        
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure connecting to $computer" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            
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
            $filestreamstate = [int]$server.Configuration.FilestreamAccessLevel.ConfigValue
            
            if ($filestreamstate -ne $level) {
                if ($Force -or $PSCmdlet.ShouldProcess($instance, "Changing from '$($OutputLookup[$filestreamstate])' to '$($OutputLookup[$level])' at the instance level")) {
                    $null = Set-DbaSpConfigure -SqlInstance $server -Name FilestreamAccessLevel -Value $level
                }
                
                if ($Force) {
                    $restart = Restart-DbaService -ComputerName $server.ComputerName -InstanceName $server.InstanceName -Type Engine
                }
            } else {
                Write-Message -Level Verbose -Message "Skipping restart as old and new FileStream values are the same"
            }
            
            Get-DbaFilestream -SqlInstance $instance -SqlCredential $SqlCredential -Credential $Credential
            if ($filestreamstate -ne $level -and -not $Force) {
                Write-Message -Level Warning -Message "[$instance] $result"
            }
        }
    }
}
