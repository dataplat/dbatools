function Add-DbaPfDataCollectorCounter {
    <#
    .SYNOPSIS
        Adds performance counters to existing Windows Performance Monitor Data Collector Sets for SQL Server monitoring.

    .DESCRIPTION
        Adds specific performance counters to existing Data Collector Sets within Windows Performance Monitor. This allows DBAs to customize their performance monitoring by adding SQL Server-specific counters like disk queue length, processor time, or SQL Server object counters to existing collection sets. The function modifies the Data Collector Set configuration and immediately applies the changes, so you can start collecting the additional performance metrics without recreating your monitoring setup.

    .PARAMETER ComputerName
        Specifies the target computer where the Data Collector Set is located. Use this when adding counters to performance monitoring on remote SQL Server instances.
        Defaults to localhost if not specified.

    .PARAMETER Credential
        Allows you to login to $ComputerName using alternative credentials. To use:

        $cred = Get-Credential, then pass $cred object to the -Credential parameter.

    .PARAMETER CollectorSet
        Specifies the name of the Windows Performance Monitor Data Collector Set that contains the collector you want to modify.
        This is the parent container that organizes related performance data collectors for your monitoring scenario.

    .PARAMETER Collector
        Specifies the name of the individual Data Collector within the CollectorSet where the new counter will be added.
        Each collector can contain multiple performance counters and defines how the data is gathered and stored.

    .PARAMETER Counter
        Specifies the performance counter path to add to the Data Collector. Must use the full counter path format like '\Processor(_Total)\% Processor Time' or '\SQLServer:Buffer Manager\Page life expectancy'.
        Use Get-DbaPfAvailableCounter to find available SQL Server and system counters with their exact paths.

    .PARAMETER InputObject
        Accepts Data Collector objects from Get-DbaPfDataCollector via the pipeline. This allows you to target specific collectors for counter addition.
        Also accepts counter objects from Get-DbaPfAvailableCounter to add available counters directly.

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
        https://dbatools.io/Add-DbaPfDataCollectorCounter

    .OUTPUTS
        PSCustomObject

        Returns one object per counter added to the Data Collector Set.

        Default display properties (via Select-DefaultView):
        - ComputerName: The name of the computer where the Data Collector Set is configured
        - DataCollectorSet: The name of the parent Data Collector Set containing the collector
        - DataCollector: The name of the specific Data Collector within the Collector Set
        - Name: The full path of the performance counter that was added
        - FileName: The output file name where performance counter data will be stored

        Additional properties available:
        - DataCollectorSetXml: The XML configuration of the Data Collector Set (typically excluded from default view)
        - Credential: The credentials used to connect to the target computer (typically excluded from default view)
        - CounterObject: Internal flag indicating this is a counter object (typically excluded from default view)

    .EXAMPLE
        PS C:\> Add-DbaPfDataCollectorCounter -ComputerName sql2017 -CollectorSet 'System Correlation' -Collector DataCollector01  -Counter '\LogicalDisk(*)\Avg. Disk Queue Length'

        Adds the '\LogicalDisk(*)\Avg. Disk Queue Length' counter within the DataCollector01 collector within the System Correlation collector set on sql2017.

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollector | Out-GridView -PassThru | Add-DbaPfDataCollectorCounter -Counter '\LogicalDisk(*)\Avg. Disk Queue Length' -Confirm

        Allows you to select which Data Collector you'd like to add the counter '\LogicalDisk(*)\Avg. Disk Queue Length' on localhost and prompts for confirmation.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [DbaInstance[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [Alias("DataCollectorSet")]
        [string[]]$CollectorSet,
        [Alias("DataCollector")]
        [string[]]$Collector,
        [Alias("Name")]
        [parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [object[]]$Counter,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        $setscript = {
            $setname = $args[0]; $Addxml = $args[1]
            $set = New-Object -ComObject Pla.DataCollectorSet
            $set.SetXml($Addxml)
            $set.Commit($setname, $null, 0x0003) #add or modify.
            $set.Query($setname, $Null)
        }
    }
    process {
        if ($InputObject.Credential -and (Test-Bound -ParameterName Credential -Not)) {
            $Credential = $InputObject.Credential
        }

        if (($InputObject | Get-Member -MemberType NoteProperty -ErrorAction SilentlyContinue).Count -le 3 -and $InputObject.ComputerName -and $InputObject.Name) {
            # it's coming from Get-DbaPfAvailableCounter
            $ComputerName = $InputObject.ComputerName
            $Counter = $InputObject.Name
            $InputObject = $null
        }

        if (-not $InputObject -or ($InputObject -and (Test-Bound -ParameterName ComputerName))) {
            foreach ($computer in $ComputerName) {
                $InputObject += Get-DbaPfDataCollector -ComputerName $computer -Credential $Credential -CollectorSet $CollectorSet -Collector $Collector
            }
        }

        if ($InputObject) {
            if (-not $InputObject.DataCollectorObject) {
                Stop-Function -Message "InputObject is not of the right type. Please use Get-DbaPfDataCollector or Get-DbaPfAvailableCounter."
                return
            }
        }

        foreach ($object in $InputObject) {
            $computer = $InputObject.ComputerName
            $null = Test-ElevationRequirement -ComputerName $computer -Continue
            $setname = $InputObject.DataCollectorSet
            $collectorname = $InputObject.Name
            $xml = [xml]($InputObject.DataCollectorSetXml)

            foreach ($countername in $counter) {
                $node = $xml.SelectSingleNode("//Name[.='$collectorname']")
                $newitem = $xml.CreateElement('Counter')
                $null = $newitem.PsBase.InnerText = $countername
                $null = $node.ParentNode.AppendChild($newitem)
                $newitem = $xml.CreateElement('CounterDisplayName')
                $null = $newitem.PsBase.InnerText = $countername
                $null = $node.ParentNode.AppendChild($newitem)
            }
            $plainxml = $xml.OuterXml

            if ($Pscmdlet.ShouldProcess("$computer", "Adding $counters to $collectorname with the $setname collection set")) {
                try {
                    $results = Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock $setscript -ArgumentList $setname, $plainxml -ErrorAction Stop
                    Write-Message -Level Verbose -Message " $results"
                    Get-DbaPfDataCollectorCounter -ComputerName $computer -Credential $Credential -CollectorSet $setname -Collector $collectorname -Counter $counter
                } catch {
                    Stop-Function -Message "Failure importing $Countername to $computer." -ErrorRecord $_ -Target $computer -Continue
                }
            }
        }
    }
}