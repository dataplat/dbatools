function Get-DbaMemoryUsage {
    <#
    .SYNOPSIS
        Collects memory usage statistics from all SQL Server services using Windows performance counters

    .DESCRIPTION
        Collects detailed memory usage from SQL Server Database Engine, Analysis Services (SSAS), and Integration Services (SSIS) using Windows performance counters. This helps you troubleshoot memory pressure issues and understand how memory is allocated across different SQL Server components on the same server.

        Gathers counters from Memory Manager (server memory, connection memory, lock memory), Plan Cache (procedure plans, ad-hoc plans), Buffer Manager (total pages, free pages, stolen pages), and service-specific memory usage. Each result shows the counter name, instance, page count where applicable, and memory in both KB and MB.

        SSRS does not have memory counters, only memory shrinks and memory pressure state.

        This function requires local admin role on the targeted computers.

    .PARAMETER ComputerName
        Specifies the Windows server to collect memory usage statistics from. Returns data for all SQL Server instances on the server.
        Use this when you need to monitor memory usage across multiple instances on a single server or compare memory allocation between different servers.

    .PARAMETER Credential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER MemoryCounterRegex
        Filters which SQL Server Memory Manager counters to collect using a regular expression pattern. Controls memory allocation tracking for server memory, connections, locks, cache, optimizer, and workspace usage.
        Customize this when you need specific memory counters or when working with non-English SQL Server installations where counter names are localized.
        Default pattern captures the most critical memory allocation counters that DBAs monitor for memory pressure troubleshooting.

    .PARAMETER PlanCounterRegex
        Filters which SQL Server Plan Cache counters to collect using a regular expression pattern. Tracks memory usage for cached execution plans including stored procedures, ad-hoc queries, and prepared statements.
        Use this to focus on specific plan cache types when investigating plan cache bloat or when working with non-English SQL Server installations.
        Default pattern captures all major plan cache memory consumers that affect query performance and memory allocation.

    .PARAMETER BufferCounterRegex
        Filters which SQL Server Buffer Manager counters to collect using a regular expression pattern. Monitors buffer pool memory usage including data pages, free pages, stolen pages, and buffer pool extensions.
        Modify this when troubleshooting specific buffer pool issues or working with non-English SQL Server installations where counter names are translated.
        Default pattern includes essential buffer pool metrics that indicate memory pressure and buffer pool health.

    .PARAMETER SSASCounterRegex
        Filters which SQL Server Analysis Services (SSAS) memory counters to collect using a regular expression pattern. Tracks memory consumption for SSAS instances and processing operations.
        Customize this when monitoring specific SSAS memory usage patterns or working with non-English installations where SSAS counter names are localized.
        Use when troubleshooting SSAS memory issues or when SSAS and Database Engine compete for server memory resources.

    .PARAMETER SSISCounterRegex
        Filters which SQL Server Integration Services (SSIS) memory counters to collect using a regular expression pattern. Monitors memory usage for SSIS package execution and service operations.
        Adjust this when investigating SSIS memory consumption during ETL operations or working with non-English installations where SSIS counter names are translated.
        Useful for identifying memory bottlenecks in SSIS packages or when multiple SQL Server services compete for available memory.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Management, OS, Memory
        Author: Klaas Vandenberghe (@PowerDBAKlaas)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        SSIS Counters: https://msdn.microsoft.com/en-us/library/ms137622.aspx

    .LINK
        https://dbatools.io/Get-DbaMemoryUsage

    .EXAMPLE
        PS C:\> Get-DbaMemoryUsage -ComputerName sql2017

        Returns a custom object displaying Server, counter instance, counter, number of pages, memory

    .EXAMPLE
        PS C:\> Get-DbaMemoryUsage -ComputerName sql2017\sqlexpress -SqlCredential sqladmin | Where-Object { $_.Memory.Megabyte -gt 100 }

        Logs into the sql2017\sqlexpress as sqladmin using SQL Authentication then returns results only where memory exceeds 100 MB

    .EXAMPLE
        PS C:\> $servers | Get-DbaMemoryUsage | Out-Gridview

        Gets results from an array of $servers then diplays them in a gridview.
    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [Alias("Host", "cn", "Server")]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [string]$MemoryCounterRegex = '(Total Server Memory |Target Server Memory |Connection Memory |Lock Memory |SQL Cache Memory |Optimizer Memory |Granted Workspace Memory |Cursor memory usage|Maximum Workspace)',
        [string]$PlanCounterRegex = '(cache pages|procedure plan|ad hoc sql plan|prepared SQL Plan)',
        [string]$BufferCounterRegex = '(Free pages|Reserved pages|Stolen pages|Total pages|Database pages|target pages|extension .* pages)',
        [string]$SSASCounterRegex = '(\\memory )',
        [string]$SSISCounterRegex = '(memory)',
        [switch]$EnableException
    )
    begin {
        $scriptBlock = {
            param (
                $MemoryCounterRegex,
                $PlanCounterRegex,
                $BufferCounterRegex,
                $SSASCounterRegex,
                $SSISCounterRegex
            )
            <# DO NOT use Write-Message as this is inside of a script block #>
            Write-Verbose -Message "Searching for Memory Manager Counters on $Computer"
            try {
                $availableCounters = (Get-Counter -ListSet '*sql*:Memory Manager*' -ErrorAction SilentlyContinue).paths
                (Get-Counter -Counter $availableCounters -ErrorAction SilentlyContinue).countersamples | Where-Object { $_.Path -match $MemoryCounterRegex } | ForEach-Object {
                    $instance = (($_.Path.split("\")[-2]).replace("mssql`$", "")).split(':')[0]
                    if ($instance -eq 'sqlserver') { $instance = 'mssqlserver' }
                    [PSCustomObject]@{
                        ComputerName    = $env:computername
                        SqlInstance     = $instance
                        CounterInstance = (($_.Path.split("\")[-2]).replace("mssql`$", "")).split(':')[1]
                        Counter         = $_.Path.split("\")[-1]
                        Pages           = $null
                        Memory          = $_.cookedvalue / 1024
                    }
                }
            } catch {
                <# DO NOT use Write-Message as this is inside of a script block #>
                Write-Verbose -Message "No Memory Manager Counters on $Computer"
            }
            <# DO NOT use Write-Message as this is inside of a script block #>
            Write-Verbose -Message "Searching for Plan Cache Counters on $Computer"
            try {
                $availableCounters = (Get-Counter -ListSet '*sql*:Plan Cache*' -ErrorAction SilentlyContinue).paths
                (Get-Counter -Counter $availableCounters -ErrorAction SilentlyContinue).countersamples | Where-Object { $_.Path -match $PlanCounterRegex } | ForEach-Object {
                    $instance = (($_.Path.split("\")[-2]).replace("mssql`$", "")).split(':')[0]
                    if ($instance -eq 'sqlserver') { $instance = 'mssqlserver' }
                    [PSCustomObject]@{
                        ComputerName    = $env:computername
                        SqlInstance     = $instance
                        CounterInstance = (($_.Path.split("\")[-2]).replace("mssql`$", "")).split(':')[1]
                        Counter         = $_.Path.split("\")[-1]
                        Pages           = $_.cookedvalue
                        Memory          = $_.cookedvalue * 8192 / 1048576
                    }
                }
            } catch {
                <# DO NOT use Write-Message as this is inside of a script block #>
                Write-Verbose -Message "No Plan Cache Counters on $Computer"
            }
            <# DO NOT use Write-Message as this is inside of a script block #>
            Write-Verbose -Message "Searching for Buffer Manager Counters on $Computer"
            try {
                $availableCounters = (Get-Counter -ListSet "*Buffer Manager*" -ErrorAction SilentlyContinue).paths
                (Get-Counter -Counter $availableCounters -ErrorAction SilentlyContinue).countersamples | Where-Object { $_.Path -match $BufferCounterRegex } | ForEach-Object {
                    $instance = (($_.Path.split("\")[-2]).replace("mssql`$", "")).split(':')[0]
                    if ($instance -eq 'sqlserver') { $instance = 'mssqlserver' }
                    [PSCustomObject]@{
                        ComputerName    = $env:computername
                        SqlInstance     = $instance
                        CounterInstance = (($_.Path.split("\")[-2]).replace("mssql`$", "")).split(':')[1]
                        Counter         = $_.Path.split("\")[-1]
                        Pages           = $_.cookedvalue
                        Memory          = $_.cookedvalue * 8192 / 1048576.0
                    }
                }
            } catch {
                <# DO NOT use Write-Message as this is inside of a script block #>
                Write-Verbose -Message "No Buffer Manager Counters on $Computer"
            }
            <# DO NOT use Write-Message as this is inside of a script block #>
            Write-Verbose -Message "Searching for SSAS Counters on $Computer"
            try {
                $availableCounters = (Get-Counter -ListSet "MSAS*:Memory" -ErrorAction SilentlyContinue).paths
                (Get-Counter -Counter $availableCounters -ErrorAction SilentlyContinue).countersamples | Where-Object { $_.Path -match $SSASCounterRegex } | ForEach-Object {
                    $instance = (($_.Path.split("\")[-2]).replace("mssql`$", "")).split(':')[0]
                    if ($instance -eq 'sqlserver') { $instance = 'mssqlserver' }
                    [PSCustomObject]@{
                        ComputerName    = $env:COMPUTERNAME
                        SqlInstance     = $instance
                        CounterInstance = (($_.Path.split("\")[-2]).replace("mssql`$", "")).split(':')[1]
                        Counter         = $_.Path.split("\")[-1]
                        Pages           = $null
                        Memory          = $_.cookedvalue / 1024
                    }
                }
            } catch {
                <# DO NOT use Write-Message as this is inside of a script block #>
                Write-Verbose -Message "No SSAS Counters on $Computer"
            }
            <# DO NOT use Write-Message as this is inside of a script block #>
            Write-Verbose -Message "Searching for SSIS Counters on $Computer"
            try {
                $availableCounters = (Get-Counter -ListSet "*SSIS*" -ErrorAction SilentlyContinue).paths
                (Get-Counter -Counter $availableCounters -ErrorAction SilentlyContinue).countersamples | Where-Object { $_.Path -match $SSISCounterRegex } | ForEach-Object {
                    $instance = (($_.Path.split("\")[-2]).replace("mssql`$", "")).split(':')[0]
                    if ($instance -eq 'sqlserver') { $instance = 'mssqlserver' }
                    [PSCustomObject]@{
                        ComputerName    = $env:computername
                        SqlInstance     = $instance
                        CounterInstance = (($_.Path.split("\")[-2]).replace("mssql`$", "")).split(':')[1]
                        Counter         = $_.Path.split("\")[-1]
                        Pages           = $null
                        Memory          = $_.cookedvalue / 1024 / 1024
                    }
                }
            } catch {
                <# DO NOT use Write-Message as this is inside of a script block #>
                Write-Verbose -Message "No SSIS Counters on $Computer"
            }
        }
    }
    process {
        foreach ($Computer in $ComputerName.ComputerName) {
            $reply = Resolve-DbaNetworkName -ComputerName $computer -Credential $Credential -ErrorAction SilentlyContinue
            if ($reply.FullComputerName) {
                $Computer = $reply.FullComputerName
                try {
                    foreach ($result in (Invoke-Command2 -ComputerName $Computer -Credential $Credential -ScriptBlock $scriptBlock -argumentlist $MemoryCounterRegex, $PlanCounterRegex, $BufferCounterRegex, $SSASCounterRegex, $SSISCounterRegex)) {
                        [PSCustomObject]@{
                            ComputerName    = $result.ComputerName
                            SqlInstance     = $result.SqlInstance
                            CounterInstance = $result.CounterInstance
                            Counter         = $result.Counter
                            Pages           = $result.Pages
                            Memory          = [dbasize]($result.Memory * 1024 * 1024)
                        }
                    }
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $computer -Continue
                }
            } else {
                Write-Message -Level Warning -Message "Can't resolve $Computer."
                Continue
            }
        }
    }
}