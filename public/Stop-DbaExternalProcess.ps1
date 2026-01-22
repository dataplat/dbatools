function Stop-DbaExternalProcess {
    <#
    .SYNOPSIS
        Terminates operating system processes spawned by SQL Server instances

    .DESCRIPTION
        Terminates external processes that were created by SQL Server, such as those spawned by xp_cmdshell, BCP operations, SSIS packages, or external script executions. This function is designed to work with the output from Get-DbaExternalProcess to resolve specific performance issues.

        The primary use case is troubleshooting hung SQL Server sessions that display External Wait Types like WAITFOR_RESULTS or EXTERNAL_SCRIPT_NETWORK_IO. When SQL Server is waiting for an external process to complete and that process becomes unresponsive, this command provides a safe way to terminate the problematic process without affecting the SQL Server service itself.

        This approach is much more targeted than killing SQL Server sessions directly, as it addresses the root cause (the stuck external process) rather than just terminating the database connection that's waiting for it.

        https://web.archive.org/web/20201027122300/http://vickyharp.com/2013/12/killing-sessions-with-external-wait-types/

    .PARAMETER ComputerName
        Specifies the Windows server hosting the SQL Server instance where external processes need to be terminated.
        Use this when troubleshooting hung sessions with external wait types on remote SQL Server hosts.

    .PARAMETER Credential
        Allows you to login to $ComputerName using alternative credentials.

    .PARAMETER ProcessId
        Specifies the Windows process ID of the external process spawned by SQL Server that needs to be terminated.
        Typically obtained from Get-DbaExternalProcess output when identifying processes causing EXTERNAL_SCRIPT_NETWORK_IO or WAITFOR_RESULTS wait types.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Diagnostic, Process
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Stop-DbaExternalProcess

    .OUTPUTS
        System.Management.Automation.PSCustomObject

        Returns one object per successfully stopped external process.

        Default display properties:
        - ComputerName: The name of the computer where the process was terminated
        - ProcessId: The Windows process ID that was stopped
        - Name: The process name/executable name of the terminated process
        - Status: The status of the operation (always "Stopped" when successful)

    .EXAMPLE
        PS C:\> Get-DbaExternalProcess -ComputerName SQL01 | Stop-DbaExternalProcess

        Kills all OS processes created by SQL Server on SQL01

    .EXAMPLE
        PS C:\> Get-DbaExternalProcess -ComputerName SQL01 | Where-Object Name -eq "cmd.exe" | Stop-DbaExternalProcess

        Kills all cmd.exe processes created by SQL Server on SQL01

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [parameter(ValueFromPipelineByPropertyname, Mandatory)]
        [DbaInstanceParameter]$ComputerName,
        [parameter(ValueFromPipelineByPropertyname)]
        [PSCredential]$Credential,
        [Alias("pid")]
        [parameter(ValueFromPipelineByPropertyname)]
        [int]$ProcessId,
        [switch]$EnableException
    )
    process {
        try {
            # gotta add ToString(), otherwise it returns null after the process is killed
            $name = (Get-DbaCmObject -ComputerName $ComputerName -Credential $Credential -ClassName win32_process | Where-Object ProcessId -eq $ProcessId).ProcessName
            $name = "$name".ToString()

            if ($Pscmdlet.ShouldProcess($ComputerName, "Killing PID $ProcessId ($name)")) {
                Invoke-Command2 -ComputerName $ComputerName -Credential $Credential -ScriptBlock {
                    Stop-Process -Id $args -Force -Confirm:$false
                } -ArgumentList $ProcessId -ErrorAction Stop

                [PSCustomObject]@{
                    ComputerName = $ComputerName
                    ProcessId    = $ProcessId
                    Name         = $name
                    Status       = "Stopped"
                }
            }
        } catch {
            Stop-Function -Message "Error killing $ProcessId on $ComputerName" -ErrorRecord $_ -Continue
        }
    }
}