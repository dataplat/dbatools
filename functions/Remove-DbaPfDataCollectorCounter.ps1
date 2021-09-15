function Remove-DbaPfDataCollectorCounter {
    <#
    .SYNOPSIS
        Removes a Performance Data Collector Counter.

    .DESCRIPTION
        Removes a Performance Data Collector Counter.

    .PARAMETER ComputerName
        The target computer. Defaults to localhost.

    .PARAMETER Credential
        Allows you to login to the target computer using alternative credentials. To use:

        $cred = Get-Credential, then pass $cred object to the -Credential parameter.

    .PARAMETER CollectorSet
        The name of the Collector Set to search.

    .PARAMETER Collector
        The name of the Collector to remove.

    .PARAMETER Counter
        The name of the Counter - in the form of '\Processor(_Total)\% Processor Time'.

    .PARAMETER InputObject
        Accepts the object output by Get-DbaPfDataCollectorSet via the pipeline.

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
                    [pscustomobject]@{
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