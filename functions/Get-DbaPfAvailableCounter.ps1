function Get-DbaPfAvailableCounter {
 <#
    .SYNOPSIS
    
    Gathers list of all available counters on local or remote machines

    .DESCRIPTION
    
    Gathers list of all available counters on local or remote machines. Note, if you pass a credential object, it will be included in the output for easy reuse in your next piped command.
    
    Thanks to Daniel Streefkerk for this super fast way of counters 
    https://daniel.streefkerkonline.com/2016/02/18/use-powershell-to-list-all-windows-performance-counters-and-their-numeric-ids
    
    .PARAMETER ComputerName
        The target computer. Defaults to localhost.

    .PARAMETER Credential
        Allows you to login to $ComputerName using alternative credentials.
    
    .PARAMETER Pattern
    Specify a pattern for filtering

    .PARAMETER EnableException
    By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
    Website: https://dbatools.io
    Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
    License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

    .LINK
    https://dbatools.io/Get-DbaPfAvailableCounter

    .EXAMPLE
    Get-DbaPfAvailableCounter

    Gets all available counters on the local machine
    
    .EXAMPLE
    Get-DbaPfAvailableCounter -Pattern *sql*

    Gets all counters matching sql on the local machine
    
    .EXAMPLE
    Get-DbaPfAvailableCounter -ComputerName sql2017 -Pattern *sql*

    Gets all counters matching sql on the remote server sql2017
    
    .EXAMPLE
    Get-DbaPfAvailableCounter -Pattern *sql*

    Gets all counters matching sql on the local machine
    
    .EXAMPLE    
    Get-DbaPfAvailableCounter -Pattern *sql* | Add-DbaPfDataCollectorCounter -CollectorSet 'Test Collector Set' -Collector DataCollector01
    
    Adds all counters matching "sql" to the DataCollector01 within the Test Collector Set collector set
#>
    [CmdletBinding()]
    param (
        [DbaInstance[]]$ComputerName = $env:ComputerName,
        [PSCredential]$Credential,
        [string]$Pattern,
        [switch]$EnableException
    )
    begin {
        $scriptblock = {
            $counters = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Perflib\009' -Name 'counter' | Select-Object -ExpandProperty Counter |
            Where-Object { $_ -notmatch '[0-90000]' } | Sort-Object | Get-Unique
            # why different output? Speed/needs mostly.
            if ($args) {
                foreach ($counter in $counters) {
                    [pscustomobject]@{
                        ComputerName      = $env:COMPUTERNAME
                        Name              = $counter
                        Credential        = $args
                    }
                }
            }
            else {
                foreach ($counter in $counters) {
                    [pscustomobject]@{
                        ComputerName       = $env:COMPUTERNAME
                        Name               = $counter
                    }
                }
            }
        }
        
        # In case ppl really wanted a like, which is slower
        $Pattern = $Pattern.Replace("*",".*").Replace("..*", ".*")
    }
    process {
        foreach ($computer in $ComputerName) {
            Write-Message -Level Verbose -Message "Connecting to $computer using Invoke-Command"
            
            try {
                if ($pattern) {
                    Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock $scriptblock -ArgumentList $credential -ErrorAction Stop |
                    Where-Object Name -match $pattern
                }
                else {
                    Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock $scriptblock -ArgumentList $credential -ErrorAction Stop
                }
            }
            catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $computer -Continue
            }
        }
    }
}