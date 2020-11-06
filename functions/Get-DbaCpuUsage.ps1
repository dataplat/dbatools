function Get-DbaCpuUsage {
    <#
    .SYNOPSIS
        Provides detailed CPU usage information about a SQL Server's process

    .DESCRIPTION
        "If there are a lot of processes running on your instance and the CPU is very high,
        then it's hard to find the exact process eating up your CPU using just the SQL Server
        tools. One way to correlate the data between what is running within SQL Server and at
        the Windows level is to use SPID and KPID values to get the exact process."

        This command automates that process.

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
        CPU threshold.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: CPU
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaCpuUsage

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
        $threadstates = [pscustomobject]@{
            0 = 'Initialized. It is recognized by the microkernel.'
            1 = 'Ready. It is prepared to run on the next available processor.'
            2 = 'Running. It is executing.'
            3 = 'Standby. It is about to run. Only one thread may be in this state at a time.'
            4 = 'Terminated. It is finished executing.'
            5 = 'Waiting. It is not ready for the processor. When ready, it will be rescheduled.'
            6 = 'Transition. The thread is waiting for resources other than the processor.'
            7 = 'Unknown. The thread state is unknown.'
        }

        $threadwaitreasons = [pscustomobject]@{
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
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $processes = Get-DbaProcess -SqlInstance $server
            $threads = Get-DbaCmObject -ComputerName $instance.ComputerName -ClassName Win32_PerfFormattedData_PerfProc_Thread -Credential $Credential | Where-Object { $_.Name -like 'sql*' -and $_.PercentProcessorTime -ge $Threshold }

            if ($server.VersionMajor -eq 8) {
                $spidcollection = $server.Query("select spid, kpid from sysprocesses")
            } else {
                $spidcollection = $server.Query("select t.os_thread_id as kpid, s.session_id as spid
            from sys.dm_exec_sessions s
            join sys.dm_exec_requests er on s.session_id = er.session_id
            join sys.dm_os_workers w on er.task_address = w.task_address
            join sys.dm_os_threads t on w.thread_address = t.thread_address")
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