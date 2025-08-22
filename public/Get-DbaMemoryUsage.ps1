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
        The Windows Server that you are connecting to. Note that this will return all instances, but Out-GridView makes it easy to filter to specific instances.

    .PARAMETER Credential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER MemoryCounterRegex
        Regular expression that is applied to the paths of the counters returned for the counter list set '*sql*:Memory Manager*' to display relevant Memory Manager counters.

        Default: '(Total Server Memory |Target Server Memory |Connection Memory |Lock Memory |SQL Cache Memory |Optimizer Memory |Granted Workspace Memory |Cursor memory usage|Maximum Workspace)'

        The default works for English language systems and has to be adapted for other languages.

    .PARAMETER PlanCounterRegex
        Regular expression that is applied to the paths of the counters returned for the counter list set '*sql*:Plan Cache*' to display relevant Plan Cache counters.

        Default: '(cache pages|procedure plan|ad hoc sql plan|prepared SQL Plan)'

        The default works for English language systems and has to be adapted for other languages.

    .PARAMETER BufferCounterRegex
        Regular expression that is applied to the paths of the counters returned for the counter list set '*Buffer Manager*' to display relevant Buffer Manager counters.

        Default: '(Free pages|Reserved pages|Stolen pages|Total pages|Database pages|target pages|extension .* pages)'

        The default works for English language systems and has to be adapted for other languages.

    .PARAMETER SSASCounterRegex
        Regular expression that is applied to the paths of the counters returned for the counter list set 'MSAS*:Memory' to display relevant SSAS counters.

        Default: '(\\memory )'

        The default works for English language systems and has to be adapted for other languages.

    .PARAMETER SSISCounterRegex
        Regular expression that is applied to the paths of the counters returned for the counter list set '*SSIS*' to display relevant SSIS counters.

        Default: '(memory)'

        The default works for English language systems and has to be adapted for other languages.

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