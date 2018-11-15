#ValidationTags#Messaging,CodeStyle#
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
        Credential object used to connect to the SQL Server as a different user

    .PARAMETER Simple
        Shows a simplified set of counters. Excludes only totals for Plancounters and BufManpagecounters

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
        PS C:\> Get-DbaMemoryUsage -ComputerName ServerA

        Returns a custom object displaying Server, counter instance, counter, number of pages, memory in KB, memory in MB

    .EXAMPLE
        PS C:\> Get-DbaMemoryUsage -ComputerName ServerA\sql987 -Simple

        Returns a custom object with Server, counter instance, counter, number of pages, memory in KB, memory in MB

    .EXAMPLE
        PS C:\> Get-DbaMemoryUsage -ComputerName ServerA\sql987 | Out-Gridview

        Returns a gridview displaying Server, counter instance, counter, number of pages, memory in KB, memory in MB

    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [Alias("Host", "cn", "Server")]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [switch]$Simple,
        [Alias('Silent')]
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
                (Get-Counter -Counter $availablecounters -ErrorAction SilentlyContinue).countersamples |
                    Where-Object { $_.Path -match $Memcounters } |
                    ForEach-Object {
                    $instance = (($_.Path.split("\")[-2]).replace("mssql`$", "")).split(':')[0]
                    if ($instance -eq 'sqlserver') { $instance = 'mssqlserver' }
                    [PSCustomObject]@{
                        ComputerName    = $env:computername
                        SqlInstance     = $instance
                        CounterInstance = (($_.Path.split("\")[-2]).replace("mssql`$", "")).split(':')[1]
                        Counter         = $_.Path.split("\")[-1]
                        Pages           = $null
                        MemKB           = $_.cookedvalue
                        MemMB           = $_.cookedvalue / 1024
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
                (Get-Counter -Counter $availablecounters -ErrorAction SilentlyContinue).countersamples |
                    Where-Object { $_.Path -match $Plancounters } |
                    ForEach-Object {
                    $instance = (($_.Path.split("\")[-2]).replace("mssql`$", "")).split(':')[0]
                    if ($instance -eq 'sqlserver') { $instance = 'mssqlserver' }
                    [PSCustomObject]@{
                        ComputerName    = $env:computername
                        SqlInstance     = $instance
                        CounterInstance = (($_.Path.split("\")[-2]).replace("mssql`$", "")).split(':')[1]
                        Counter         = $_.Path.split("\")[-1]
                        Pages           = $_.cookedvalue
                        MemKB           = $_.cookedvalue * 8192 / 1024
                        MemMB           = $_.cookedvalue * 8192 / 1048576
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
                (Get-Counter -Counter $availablecounters -ErrorAction SilentlyContinue).countersamples |
                    Where-Object { $_.Path -match $BufManpagecounters } |
                    ForEach-Object {
                    $instance = (($_.Path.split("\")[-2]).replace("mssql`$", "")).split(':')[0]
                    if ($instance -eq 'sqlserver') { $instance = 'mssqlserver' }
                    [PSCustomObject]@{
                        ComputerName    = $env:computername
                        SqlInstance     = $instance
                        CounterInstance = (($_.Path.split("\")[-2]).replace("mssql`$", "")).split(':')[1]
                        Counter         = $_.Path.split("\")[-1]
                        Pages           = $_.cookedvalue
                        MemKB           = $_.cookedvalue * 8192 / 1024.0
                        MemMB           = $_.cookedvalue * 8192 / 1048576.0
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
                (Get-Counter -Counter $availablecounters -ErrorAction SilentlyContinue).countersamples |
                    Where-Object { $_.Path -match $SSAScounters } |
                    ForEach-Object {
                    $instance = (($_.Path.split("\")[-2]).replace("mssql`$", "")).split(':')[0]
                    if ($instance -eq 'sqlserver') { $instance = 'mssqlserver' }
                    [PSCustomObject]@{
                        ComputerName    = $env:COMPUTERNAME
                        SqlInstance     = $instance
                        CounterInstance = (($_.Path.split("\")[-2]).replace("mssql`$", "")).split(':')[1]
                        Counter         = $_.Path.split("\")[-1]
                        Pages           = $null
                        MemKB           = $_.cookedvalue
                        MemMB           = $_.cookedvalue / 1024
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
                (Get-Counter -Counter $availablecounters -ErrorAction SilentlyContinue).countersamples |
                    Where-Object { $_.Path -match $SSIScounters } |
                    ForEach-Object {
                    $instance = (($_.Path.split("\")[-2]).replace("mssql`$", "")).split(':')[0]
                    if ($instance -eq 'sqlserver') { $instance = 'mssqlserver' }
                    [PSCustomObject]@{
                        ComputerName    = $env:computername
                        SqlInstance     = $instance
                        CounterInstance = (($_.Path.split("\")[-2]).replace("mssql`$", "")).split(':')[1]
                        Counter         = $_.Path.split("\")[-1]
                        Pages           = $null
                        MemKB           = $_.cookedvalue / 1024
                        MemMB           = $_.cookedvalue / 1024 / 1024
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
                    Invoke-Command2 -ComputerName $Computer -Credential $Credential -ScriptBlock $scriptblock -argumentlist $Memcounters, $Plancounters, $BufManpagecounters, $SSAScounters, $SSIScounters
                } catch {
                    Stop-Function -Continue -Message "Failure" -ErrorRecord $_ -Target $computer -Continue
                }
            } else {
                Write-Message -Level Warning -Message "Can't resolve $Computer."
                Continue
            }
        }
    }
}