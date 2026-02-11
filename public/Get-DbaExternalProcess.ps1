function Get-DbaExternalProcess {
    <#
    .SYNOPSIS
        Retrieves operating system processes spawned by SQL Server instances

    .DESCRIPTION
        Identifies and returns all child processes created by SQL Server, such as those spawned by xp_cmdshell, BCP operations, SSIS packages, or other external utilities.

        This is particularly useful when troubleshooting sessions with External Wait Types, where SQL Server is waiting for an external process to complete. When sessions appear hung with wait types like WAITFOR_RESULTS or EXTERNAL_SCRIPT_NETWORK_IO, this command helps identify the specific external processes that may be causing the delay.

        The function queries WMI to find the SQL Server process (sqlservr.exe) and then locates all processes where SQL Server is the parent process, providing details about memory usage and resource consumption.

        https://web.archive.org/web/20201027122300/http://vickyharp.com/2013/12/killing-sessions-with-external-wait-types/

    .PARAMETER ComputerName
        Specifies the SQL Server host computer(s) to check for external processes spawned by SQL Server.
        Use this when troubleshooting hung sessions or investigating resource usage from processes like xp_cmdshell, BCP, or SSIS operations.
        Accepts multiple computer names and SQL Server instance names with automatic computer resolution.

    .PARAMETER Credential
        Allows you to login to $ComputerName using alternative credentials.

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
        https://dbatools.io/Get-DbaExternalProcess

    .OUTPUTS
        PSCustomObject

        Returns one object per external process spawned by SQL Server on each target computer. For servers with no child processes spawned by SQL Server, nothing is returned.

        Default display properties (via Select-DefaultView):
        - ComputerName: The name of the computer where the SQL Server process resides
        - ProcessId: The operating system process ID of the child process (unsigned integer)
        - Name: The executable name of the child process (e.g., cmd.exe, bcp.exe, DTExec.exe)
        - HandleCount: The number of open handles held by the child process (unsigned integer)
        - WorkingSetSize: Memory currently in use by the child process in bytes (unsigned long)
        - VirtualSize: Total virtual address space reserved by the child process in bytes (unsigned long)
        - CimObject: The underlying WMI process object providing full access to all Win32_Process properties

        Additional properties available:
        - Credential: The credential object used for the WMI connection

    .EXAMPLE
        PS C:\> Get-DbaExternalProcess -ComputerName SERVER01, SERVER02

        Gets OS processes created by SQL Server on SERVER01 and SERVER02

    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline, Mandatory)]
        [DbaInstanceParameter[]]$ComputerName,
        [PSCredential]$Credential,
        [switch]$EnableException
    )
    process {
        foreach ($computer in $ComputerName) {
            try {
                $sqlpid = (Get-DbaCmObject -ComputerName $computer -Credential $Credential -ClassName win32_process | Where-Object ProcessName -eq "sqlservr.exe").ProcessId
                $processes = Get-DbaCmObject -ComputerName $computer -Credential $Credential -ClassName win32_process | Where-Object ParentProcessId -in $sqlpid

                foreach ($process in $processes) {
                    [PSCustomObject]@{
                        ComputerName   = $computer
                        Credential     = $Credential
                        ProcessId      = $process.ProcessId
                        Name           = $process.Name
                        HandleCount    = $process.HandleCount
                        WorkingSetSize = $process.WorkingSetSize
                        VirtualSize    = $process.VirtualSize
                        CimObject      = $process
                    } | Select-DefaultView -Property ComputerName, ProcessId, Name, HandleCount, WorkingSetSize, VirtualSize, CimObject
                }
            } catch {
                Stop-Function -Message "Failure for $computer" -ErrorRecord $_ -Continue
            }
        }
    }
}