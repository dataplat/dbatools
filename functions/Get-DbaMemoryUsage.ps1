function Get-DbaMemoryUsage {
    <#
    .SYNOPSIS
        Get amount of memory in use by *all* SQL Server components and instances

    .DESCRIPTION
        Retrieves the amount of memory per performance counter. Default output includes columns Server, counter instance, counter, number of pages, memory in KB, memory in MB
        SSAS and SSIS are included.

        SSRS does not have memory counters, only memory shrinks and memory pressure state.

        This function requires local admin role on the targeted computers.

    .PARAMETER ComputerName
        The Windows Server that you are connecting to. Note that this will return all instances, but Out-GridView makes it easy to filter to specific instances.

    .PARAMETER Credential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Memory
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
        [switch]$EnableException
    )
    begin {
        if ($Simple) {
            $Memcounters = '(Total Server Memory |Target Server Memory |Connection Memory |Lock Memory |SQL Cache Memory |Optimizer Memory |Granted Workspace Memory |Cursor memory usage|Maximum Workspace)'
            $Plancounters = 'total\)\\cache pages'
            $BufManpagecounters = 'Total pages'
            $SSAScounters = '(\\memory usage)'
            $SSIScounters = '(memory)'
        } else {
            $Memcounters = '(Total Server Memory |Target Server Memory |Connection Memory |Lock Memory |SQL Cache Memory |Optimizer Memory |Granted Workspace Memory |Cursor memory usage|Maximum Workspace)'
            $Plancounters = '(cache pages|procedure plan|ad hoc sql plan|prepared SQL Plan)'
            $BufManpagecounters = '(Free pages|Reserved pages|Stolen pages|Total pages|Database pages|target pages|extension .* pages)'
            $SSAScounters = '(\\memory )'
            $SSIScounters = '(memory)'
        }

        $scriptblock = {
            param ($Memcounters,
                $Plancounters,
                $BufManpagecounters,
                $SSAScounters,
                $SSIScounters)
            <# DO NOT use Write-Message as this is inside of a script block #>
            Write-Verbose -Message "Searching for Memory Manager Counters on $Computer"
            try {
                $availablecounters = (Get-Counter -ListSet '*sql*:Memory Manager*' -ErrorAction SilentlyContinue).paths
                (Get-Counter -Counter $availablecounters -ErrorAction SilentlyContinue).countersamples | Where-Object { $_.Path -match $Memcounters } | ForEach-Object {
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
                $availablecounters = (Get-Counter -ListSet '*sql*:Plan Cache*' -ErrorAction SilentlyContinue).paths
                (Get-Counter -Counter $availablecounters -ErrorAction SilentlyContinue).countersamples | Where-Object { $_.Path -match $Plancounters } | ForEach-Object {
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
                $availablecounters = (Get-Counter -ListSet "*Buffer Manager*" -ErrorAction SilentlyContinue).paths
                (Get-Counter -Counter $availablecounters -ErrorAction SilentlyContinue).countersamples | Where-Object { $_.Path -match $BufManpagecounters } | ForEach-Object {
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
                $availablecounters = (Get-Counter -ListSet "MSAS*:Memory" -ErrorAction SilentlyContinue).paths
                (Get-Counter -Counter $availablecounters -ErrorAction SilentlyContinue).countersamples | Where-Object { $_.Path -match $SSAScounters } | ForEach-Object {
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
                $availablecounters = (Get-Counter -ListSet "*SSIS*" -ErrorAction SilentlyContinue).paths
                (Get-Counter -Counter $availablecounters -ErrorAction SilentlyContinue).countersamples | Where-Object { $_.Path -match $SSIScounters } | ForEach-Object {
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
                    foreach ($result in (Invoke-Command2 -ComputerName $Computer -Credential $Credential -ScriptBlock $scriptblock -argumentlist $Memcounters, $Plancounters, $BufManpagecounters, $SSAScounters, $SSIScounters)) {
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