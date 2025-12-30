function Get-DbaCpuUsage {
    <#
    .SYNOPSIS
        Correlates SQL Server processes with Windows threads to identify which queries are consuming CPU resources

    .DESCRIPTION
        When CPU usage is high on your SQL Server, it can be difficult to pinpoint which specific SQL queries or processes are responsible using standard SQL Server tools alone. This function bridges that gap by correlating SQL Server process IDs (SPIDs) with Windows kernel process IDs (KPIDs) through system DMVs and Windows performance counters.

        The function queries both SQL Server's process information and Windows thread performance data, then matches them together to show you exactly which SQL queries are consuming CPU at the operating system level. This is particularly valuable during performance troubleshooting when you need to identify the root cause of high CPU usage.

        Results include detailed thread information such as processor time percentages, thread states, wait reasons, and the actual SQL queries being executed. You can also set a CPU threshold to focus only on processes exceeding a specific percentage.

        References: https://www.mssqltips.com/sqlservertip/2454/how-to-find-out-how-much-cpu-a-sql-server-process-is-really-using/

        Note: This command returns results from all SQL instances on the destination server but the process
        column is specific to -SqlInstance passed.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Credential
        Allows you to login to the Windows Server using alternative credentials.

    .PARAMETER Threshold
        Filters results to only show SQL Server threads with CPU usage at or above this percentage.
        Use this to focus on high-CPU consuming processes and ignore idle or low-activity threads during performance troubleshooting.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Diagnostic, Performance, CPU
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaCpuUsage

    .OUTPUTS
        Win32_PerfFormattedData_PerfProc_Thread (with added properties)

        Returns one object per Windows thread of SQL Server processes with CPU usage at or above the specified threshold.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Name: The thread identifier in format 'ProcessName_ProcessID_ThreadID'
        - ContextSwitchesPersec: Number of context switches per second for this thread
        - ElapsedTime: Time in seconds since the thread was created
        - IDProcess: Windows process ID (PID) of the SQL Server process
        - Spid: SQL Server session ID (SPID) associated with this thread
        - PercentPrivilegedTime: Percentage of time thread spent in privileged mode
        - PercentProcessorTime: Percentage of total processor time consumed by this thread
        - PercentUserTime: Percentage of time thread spent in user mode
        - PriorityBase: The base priority of the thread
        - PriorityCurrent: The current priority of the thread
        - StartAddress: Memory address where the thread code begins execution
        - ThreadStateValue: Human-readable description of the thread state (e.g., 'Running', 'Waiting')
        - ThreadWaitReasonValue: Human-readable description of the wait reason if thread is waiting
        - Process: Associated SQL Server process object from Get-DbaProcess
        - Query: The last T-SQL query executed by the process

        Additional properties available (from Win32_PerfFormattedData_PerfProc_Thread):
        - IDThread: Windows thread ID
        - ThreadState: Numeric value representing thread state (0=Initialized, 1=Ready, 2=Running, 3=Standby, 4=Terminated, 5=Waiting, 6=Transition, 7=Unknown)
        - ThreadWaitReason: Numeric value representing the reason the thread is waiting

        All properties from the Win32_PerfFormattedData_PerfProc_Thread WMI class are accessible using Select-Object *.

    .EXAMPLE
        PS C:\> Get-DbaCpuUsage -SqlInstance sql2017

        Logs into the SQL Server instance "sql2017" and also the Computer itself (via WMI) to gather information

    .EXAMPLE
        PS C:\> $usage = Get-DbaCpuUsage -SqlInstance sql2017
        PS C:\> $usage.Process

        Explores the processes (from Get-DbaProcess) associated with the usage results

    .EXAMPLE
        PS C:\> Get-DbaCpuUsage -SqlInstance sql2017 -SqlCredential sqladmin -Credential ad\sqldba

        Logs into the SQL instance using the SQL Login 'sqladmin' and then Windows instance as 'ad\sqldba'

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [PSCredential]$Credential,
        [int]$Threshold = 0,
        [switch]$EnableException
    )
    begin {
        # This can likely be enumerated but I don't know hows
        $threadstates = [PSCustomObject]@{
            0 = 'Initialized. It is recognized by the microkernel.'
            1 = 'Ready. It is prepared to run on the next available processor.'
            2 = 'Running. It is executing.'
            3 = 'Standby. It is about to run. Only one thread may be in this state at a time.'
            4 = 'Terminated. It is finished executing.'
            5 = 'Waiting. It is not ready for the processor. When ready, it will be rescheduled.'
            6 = 'Transition. The thread is waiting for resources other than the processor.'
            7 = 'Unknown. The thread state is unknown.'
        }

        $threadwaitreasons = [PSCustomObject]@{
            0  = 'Executive'
            1  = 'FreePage'
            2  = 'PageIn'
            3  = 'PoolAllocation'
            4  = 'ExecutionDelay'
            5  = 'FreePage'
            6  = 'PageIn'
            7  = 'Executive'
            8  = 'FreePage'
            9  = 'PageIn'
            10 = 'PoolAllocation'
            11 = 'ExecutionDelay'
            12 = 'FreePage'
            13 = 'PageIn'
            14 = 'EventPairHigh'
            15 = 'EventPairLow'
            16 = 'LPCReceive'
            17 = 'LPCReply'
            18 = 'VirtualMemory'
            19 = 'PageOut'
            20 = 'Unknown'
        }
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $processes = Get-DbaProcess -SqlInstance $server
            $threads = Get-DbaCmObject -ComputerName $instance.ComputerName -ClassName Win32_PerfFormattedData_PerfProc_Thread -Credential $Credential | Where-Object { $_.Name -like 'sql*' -and $_.PercentProcessorTime -ge $Threshold }

            if ($server.VersionMajor -eq 8) {
                $spidcollection = $server.Query("SELECT spid, kpid FROM sysprocesses")
            } else {
                $spidcollection = $server.Query("SELECT t.os_thread_id AS kpid, s.session_id AS spid
            FROM sys.dm_exec_sessions s
            JOIN sys.dm_exec_requests er ON s.session_id = er.session_id
            JOIN sys.dm_os_workers w ON er.task_address = w.task_address
            JOIN sys.dm_os_threads t ON w.thread_address = t.thread_address")
            }

            foreach ($thread in $threads) {
                $spid = ($spidcollection | Where-Object kpid -eq $thread.IDThread).spid
                $process = $processes | Where-Object spid -eq $spid
                $threadwaitreason = $thread.ThreadWaitReason
                $threadstate = $thread.ThreadState
                $ThreadStateValue = $threadstates.$threadstate
                $ThreadWaitReasonValue = $threadwaitreasons.$threadwaitreason

                Add-Member -Force -InputObject $thread -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                Add-Member -Force -InputObject $thread -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                Add-Member -Force -InputObject $thread -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                Add-Member -Force -InputObject $thread -MemberType NoteProperty -Name Processes -Value ($processes | Where-Object HostProcessID -eq $thread.IDProcess)
                Add-Member -Force -InputObject $thread -MemberType NoteProperty -Name ThreadStateValue -Value $ThreadStateValue
                Add-Member -Force -InputObject $thread -MemberType NoteProperty -Name ThreadWaitReasonValue -Value $ThreadWaitReasonValue
                Add-Member -Force -InputObject $thread -MemberType NoteProperty -Name Process -Value $process
                Add-Member -Force -InputObject $thread -MemberType NoteProperty -Name Query -Value $process.LastQuery
                Add-Member -Force -InputObject $thread -MemberType NoteProperty -Name Spid -Value $spid

                Select-DefaultView -InputObject $thread -Property ComputerName, InstanceName, SqlInstance, Name, ContextSwitchesPersec, ElapsedTime, IDProcess, Spid, PercentPrivilegedTime, PercentProcessorTime, PercentUserTime, PriorityBase, PriorityCurrent, StartAddress, ThreadStateValue, ThreadWaitReasonValue, Process, Query
            }
        }
    }
}