function Get-DbaPfAvailableCounter {
    <#
    .SYNOPSIS
        Retrieves all Windows performance counters available on local or remote machines for monitoring setup.

    .DESCRIPTION
        Retrieves all Windows performance counters available on specified machines by reading directly from the registry for fast enumeration. This is essential when setting up SQL Server monitoring because you need to know which specific counters are available before configuring data collectors or performance monitoring solutions. The function uses a registry-based approach that's much faster than traditional Get-Counter methods, making it practical for discovering hundreds of available counters across multiple servers. When credentials are provided, they're included in the output for easy piping to other dbatools commands like Add-DbaPfDataCollectorCounter.

        Thanks to Daniel Streefkerk for this super fast way of counters
        https://daniel.streefkerkonline.com/2016/02/18/use-powershell-to-list-all-windows-performance-counters-and-their-numeric-ids

    .PARAMETER ComputerName
        Specifies the target computers to query for available performance counters. Defaults to localhost.
        Use this when you need to discover counters on remote SQL Server instances or other servers in your environment before setting up monitoring.

    .PARAMETER Credential
        Allows you to login to servers using alternative credentials. To use:

        $scred = Get-Credential, then pass $scred object to the -Credential parameter.

    .PARAMETER Pattern
        Filters counter names using wildcard pattern matching (supports * and ? wildcards).
        Use this to find specific SQL Server counters like "*sql*" or "*buffer*" when you need to identify relevant performance metrics for monitoring setup.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Performance, DataCollector, PerfCounter
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .OUTPUTS
        PSCustomObject

        Returns one object per available Windows performance counter found on the specified computers.

        Default display properties:
        - ComputerName: The name of the computer where the counter is available
        - Name: The performance counter name

        Additional properties available (via Select-Object *):
        - Credential: The PSCredential object used for connecting to the computer; useful for piping to other dbatools commands like Add-DbaPfDataCollectorCounter

    .LINK
        https://dbatools.io/Get-DbaPfAvailableCounter

    .EXAMPLE
        PS C:\> Get-DbaPfAvailableCounter

        Gets all available counters on the local machine.

    .EXAMPLE
        PS C:\> Get-DbaPfAvailableCounter -Pattern *sql*

        Gets all counters matching sql on the local machine.

    .EXAMPLE
        PS C:\> Get-DbaPfAvailableCounter -ComputerName sql2017 -Pattern *sql*

        Gets all counters matching sql on the remote server sql2017.

    .EXAMPLE
        PS C:\> Get-DbaPfAvailableCounter -Pattern *sql*

        Gets all counters matching sql on the local machine.

    .EXAMPLE
        PS C:\> Get-DbaPfAvailableCounter -Pattern *sql* | Add-DbaPfDataCollectorCounter -CollectorSet 'Test Collector Set' -Collector DataCollector01

        Adds all counters matching "sql" to the DataCollector01 within the 'Test Collector Set' CollectorSet.

    #>
    [CmdletBinding()]
    param (
        [DbaInstance[]]$ComputerName = $env:ComputerName,
        [PSCredential]$Credential,
        [string]$Pattern,
        [switch]$EnableException
    )
    begin {
        $scriptBlock = {
            $counters = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Perflib\009' -Name 'counter' | Select-Object -ExpandProperty Counter |
            Where-Object { $_ -notmatch '[0-90000]' } | Sort-Object | Get-Unique

        foreach ($counter in $counters) {
            [PSCustomObject]@{
                ComputerName = $env:COMPUTERNAME
                Name         = $counter
                Credential   = $args
            }
        }
    }

    # In case people really want a "like" search, which is slower
    $Pattern = $Pattern.Replace("*", ".*").Replace("..*", ".*")
}
process {


    foreach ($computer in $ComputerName) {

        try {
            if ($pattern) {
                Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock $scriptBlock -ArgumentList $credential -ErrorAction Stop |
                    Where-Object Name -match $pattern | Select-DefaultView -ExcludeProperty Credential
            } else {
                Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock $scriptBlock -ArgumentList $credential -ErrorAction Stop |
                    Select-DefaultView -ExcludeProperty Credential
            }
        } catch {
            Stop-Function -Message "Failure" -ErrorRecord $_ -Target $computer -Continue
        }
    }
}
}