function Stop-DbaPfDataCollectorSet {
    <#
        .SYNOPSIS
            Starts Performance Monitor Data Collector Set

        .DESCRIPTION
            Starts Performance Monitor Data Collector Set

        .PARAMETER ComputerName
            The target computer. Defaults to localhost.

        .PARAMETER Credential
            Allows you to login to $ComputerName using alternative credentials.

        .PARAMETER CollectorSet
            The Collector Set name
    
        .PARAMETER NoWait
            Stop the collector and immediately return the results
    
        .PARAMETER InputObject
            Enables piped results from Get-DbaPfDataCollectorSet

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    
        .NOTES
            Tags: PerfMon
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0
    
        .LINK
            https://dbatools.io/Stop-DbaPfDataCollectorSet

        .EXAMPLE
            Stop-DbaPfDataCollectorSet
    
            Attempts to start all ready Collectors on localhost

        .EXAMPLE
            Stop-DbaPfDataCollectorSet -ComputerName sql2017
    
            Attempts to start all ready Collectors on localhost
    
        .EXAMPLE
            Stop-DbaPfDataCollectorSet -ComputerName sql2017, sql2016 -Credential (Get-Credential) -CollectorSet 'System Correlation'
    
            Starts the 'System Correlation' Collector on sql2017 and sql2016 using alternative credentials
    
        .EXAMPLE
            Get-DbaPfDataCollectorSet -CollectorSet 'System Correlation' | Stop-DbaPfDataCollectorSet
    
            Starts 'System Correlation' Collector
    #>
    [CmdletBinding()]
    param (
        [DbaInstance[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [Alias("DataCollectorSet")]
        [string[]]$CollectorSet,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$NoWait,
        [switch]$EnableException
    )
    begin {
        $sets = @()
        $wait = $NoWait -eq $false
        
        $setscript = {
            $setname = $args[0]; $wait = $args[1]
            $collectorset = New-Object -ComObject Pla.DataCollectorSet
            $collectorset.Query($setname, $null)
            $null = $collectorset.Stop($wait)
        }
    }
    process {
        if (-not $InputObject -or ($InputObject -and (Test-Bound -ParameterName ComputerName))) {
            foreach ($computer in $ComputerName) {
                $InputObject += Get-DbaPfDataCollectorSet -ComputerName $computer -Credential $Credential -CollectorSet $CollectorSet
            }
        }
        
        if ($InputObject) {
            if (-not $InputObject.DataCollectorSetObject) {
                Stop-Function -Message "InputObject is not of the right type. Please use Get-DbaPfDataCollectorSet"
                return
            }
        }
        
        # Check to see if its running first
        foreach ($set in $InputObject) {
            $setname = $set.Name
            $computer = $set.ComputerName
            $status = $set.State
            
            Write-Message -Level Verbose -Message "$setname on $ComputerName is $status"
            if ($status -ne "Running") {
                Stop-Function -Message "$setname on $computer is already stopped" -Continue
            }
            Write-Message -Level Verbose -Message "Connecting to $computer using Invoke-Command"
            try {
                Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock $setscript -ArgumentList $setname, $wait -ErrorAction Stop -Raw
            }
            catch {
                Stop-Function -Message "Failure stopping $setname on $computer" -ErrorRecord $_ -Target $computer -Continue
            }
            
            Get-DbaPfDataCollectorSet -ComputerName $computer -Credential $Credential -CollectorSet $setname
        }
    }
}