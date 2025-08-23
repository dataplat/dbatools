function Remove-DbaPfDataCollectorCounter {
    <#
    .SYNOPSIS
        Removes specific performance counters from Windows Performance Monitor Data Collector Sets.

    .DESCRIPTION
        Removes performance counters from existing Data Collector Sets in Windows Performance Monitor. This allows you to clean up monitoring configurations by removing counters that are no longer needed, reducing resource consumption and focusing on relevant metrics. Commonly used when fine-tuning SQL Server performance monitoring setups or removing counters that were added for troubleshooting specific issues.

    .PARAMETER ComputerName
        Specifies the target computer(s) where the Performance Monitor Data Collector Set is configured. Accepts multiple computer names for bulk operations.
        Use this when you need to remove counters from collector sets on remote SQL Server machines or when managing performance monitoring across multiple servers.

    .PARAMETER Credential
        Allows you to login to the target computer using alternative credentials. To use:

        $cred = Get-Credential, then pass $cred object to the -Credential parameter.

    .PARAMETER CollectorSet
        Specifies the name of the Performance Monitor Data Collector Set containing the counters to be removed. Supports wildcards for pattern matching across multiple sets.
        Use this when you know the specific collector set name where your performance counters are configured, such as 'System Correlation' or custom SQL Server monitoring sets.

    .PARAMETER Collector
        Specifies the name of the individual data collector within the collector set that contains the performance counters to remove. Supports multiple collector names.
        Use this to target specific data collectors when your collector set contains multiple collectors, allowing you to remove counters from only the collectors you specify.

    .PARAMETER Counter
        Specifies the exact performance counter name(s) to remove from the data collector. Must use the full counter path format like '\Processor(_Total)\% Processor Time' or '\SQLServer:Buffer Manager\Buffer cache hit ratio'.
        Use this when you need to remove specific SQL Server or system performance counters that are no longer needed for monitoring, such as counters added for troubleshooting that are now consuming unnecessary resources.

    .PARAMETER InputObject
        Accepts performance counter objects from Get-DbaPfDataCollectorCounter via the pipeline, allowing you to remove counters discovered through previous queries.
        Use this when you want to first review existing counters with Get-DbaPfDataCollectorCounter and then selectively remove specific ones through pipeline operations.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: PerfMon
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaPfDataCollectorCounter

    .EXAMPLE
        PS C:\> Remove-DbaPfDataCollectorCounter -ComputerName sql2017 -CollectorSet 'System Correlation' -Collector DataCollector01  -Counter '\LogicalDisk(*)\Avg. Disk Queue Length'

        Prompts for confirmation then removes the '\LogicalDisk(*)\Avg. Disk Queue Length' counter within the DataCollector01 collector within the System Correlation collector set on sql2017.

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollectorCounter | Out-GridView -PassThru | Remove-DbaPfDataCollectorCounter -Confirm:$false

        Allows you to select which counters you'd like on localhost and does not prompt for confirmation.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [DbaInstance[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [Alias("DataCollectorSet")]
        [string[]]$CollectorSet,
        [Alias("DataCollector")]
        [string[]]$Collector,
        [parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias("Name")]
        [object[]]$Counter,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        $setscript = {
            $setname = $args[0]; $removexml = $args[1]
            $CollectorSet = New-Object -ComObject Pla.DataCollectorSet
            $CollectorSet.SetXml($removexml)
            $CollectorSet.Commit($setname, $null, 0x0003) #add or modify.
            $CollectorSet.Query($setname, $Null)
        }
    }
    process {


        if ($InputObject.Credential -and (Test-Bound -ParameterName Credential -Not)) {
            $Credential = $InputObject.Credential
        }

        if (-not $InputObject -or ($InputObject -and (Test-Bound -ParameterName ComputerName))) {
            foreach ($computer in $ComputerName) {
                $InputObject += Get-DbaPfDataCollectorCounter -ComputerName $computer -Credential $Credential -CollectorSet $CollectorSet -Collector $Collector -Counter $Counter
            }
        }

        if ($InputObject) {
            if (-not $InputObject.CounterObject) {
                Stop-Function -Message "InputObject is not of the right type. Please use Get-DbaPfDataCollectorCounter."
                return
            }
        }

        foreach ($object in $InputObject) {
            $computer = $InputObject.ComputerName
            $null = Test-ElevationRequirement -ComputerName $computer -Continue
            $setname = $InputObject.DataCollectorSet
            $collectorname = $InputObject.DataCollector

            $xml = [xml]($InputObject.DataCollectorSetXml)

            foreach ($countername in $counter) {
                $node = $xml.SelectSingleNode("//Name[.='$collectorname']").SelectSingleNode("//Counter[.='$countername']")
                $null = $node.ParentNode.RemoveChild($node)
                $node = $xml.SelectSingleNode("//Name[.='$collectorname']").SelectSingleNode("//CounterDisplayName[.='$countername']")
                $null = $node.ParentNode.RemoveChild($node)
            }

            $plainxml = $xml.OuterXml

            if ($Pscmdlet.ShouldProcess("$computer", "Remove $countername from $collectorname with the $setname collection set")) {
                try {
                    $results = Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock $setscript -ArgumentList $setname, $plainxml -ErrorAction Stop -Raw
                    Write-Message -Level Verbose -Message " $results"
                    [PSCustomObject]@{
                        ComputerName     = $computer
                        DataCollectorSet = $setname
                        DataCollector    = $collectorname
                        Name             = $counterName
                        Status           = "Removed"
                    }
                } catch {
                    Stop-Function -Message "Failure importing $Countername to $computer." -ErrorRecord $_ -Target $computer -Continue
                }
            }
        }
    }
}