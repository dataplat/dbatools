#nullable enable

namespace Dataplat.Dbatools.Commands;

// Hop script constants (the verbatim retired PS bodies) - split out per the repo 400-line file limit.
public sealed partial class ImportDbaPfDataCollectorSetTemplateCommand
{

    // PS: the begin-block module-root resolution (source-carried RB-IMP-51 fallback).
    private const string ModuleRootScript = """
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    $moduleRoot = $script:PSModuleRoot
    if (-not $moduleRoot) {
        $moduleRoot = (Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1).ModuleBase
    }
    $moduleRoot
}
""";

    // PS: the ENTIRE process body VERBATIM (both loops, the template resolution and
    // += Path growth, the replace pipeline, ShouldProcess routing via $__realCmdlet,
    // the $instance shadowing, the counter cloning) plus the begin-block scriptblocks
    // it invokes; the trailing sentinel carries the mutated fn-scope state back.
    private const string ProcessScript = """
param($ComputerName, $Credential, $DisplayName, $SchedulesEnabled, $RootPath, $Segment, $SegmentMaxDuration, $SegmentMaxSize, $Subdirectory, $SubdirectoryFormat, $SubdirectoryFormatPattern, $Task, $TaskRunAsSelf, $TaskArguments, $TaskUserTextArguments, $StopOnCompletion, $Path, $Template, $Instance, $__moduleRoot, $__state, $__pathBound, $__templateBound, $__displayNameBound, $__rootPathBound, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($ComputerName, $Credential, $DisplayName, $SchedulesEnabled, $RootPath, $Segment, $SegmentMaxDuration, $SegmentMaxSize, $Subdirectory, $SubdirectoryFormat, $SubdirectoryFormatPattern, $Task, $TaskRunAsSelf, $TaskArguments, $TaskUserTextArguments, $StopOnCompletion, $Path, $Template, $Instance, $__moduleRoot, $__state, $__pathBound, $__templateBound, $__displayNameBound, $__rootPathBound, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
    $moduleRoot = $__moduleRoot

    $setscript = {
        $setname = $args[0]; $templatexml = $args[1]
        $collectorset = New-Object -ComObject Pla.DataCollectorSet
        $collectorset.SetXml($templatexml)
        $null = $collectorset.Commit($setname, $null, 0x0003) #add or modify.
        $null = $collectorset.Query($setname, $Null)
    }

    $instancescript = {
        $services = Get-Service -DisplayName *sql* | Select-Object -ExpandProperty DisplayName
        [regex]::matches($services, '(?<=\().+?(?=\))').Value | Where-Object { $PSItem -ne 'MSSQLSERVER' } | Select-Object -Unique
    }

    # restore fn-scope locals mutated by earlier records
    if ($null -ne $__state) {
        $Name = $__state.Name
        $RootName = $__state.RootName
        $output = $__state.output
        $instance = $__state.instance
        $xml = $__state.xml
        $plainxml = $__state.plainxml
        $contents = $__state.contents
        $instances = $__state.instances
        $datacollector = $__state.datacollector
        $sqlcounters = $__state.sqlcounters
        $newcollection = $__state.newcollection
        $templatepath = $__state.templatepath
    }



    if ((-not $__pathBound) -and (-not $__templateBound)) {
        Stop-Function -Message "You must specify Path or Template" -FunctionName Import-DbaPfDataCollectorSetTemplate
    }

    if (($Path.Count -gt 1 -or $Template.Count -gt 1) -and ($__templateBound)) {
        Stop-Function -Message "Name cannot be specified with multiple files or templates because the Session will already exist" -FunctionName Import-DbaPfDataCollectorSetTemplate
    }

    foreach ($computer in $ComputerName) {
        $null = Test-ElevationRequirement -ComputerName $computer -Continue

        foreach ($file in $template) {
            $templatepath = "$moduleRoot\bin\perfmontemplates\collectorsets\$file.xml"
            if ((Test-Path $templatepath)) {
                $Path += $templatepath
            } else {
                Stop-Function -Message "Invalid template ($templatepath does not exist)" -Continue -FunctionName Import-DbaPfDataCollectorSetTemplate
            }
        }

        foreach ($file in $Path) {

            if ((-not $__displayNameBound)) {
                Set-Variable -Name DisplayName -Value (Get-ChildItem -Path $file).BaseName
            }

            $Name = $DisplayName

            Write-Message -Level Verbose -Message "Processing $file for $computer"

            if ((-not $__rootPathBound)) {
                Set-Variable -Name RootName -Value "%systemdrive%\PerfLogs\Admin\$Name"
            }

            # Perform replace
            $temp = ([System.IO.Path]::GetTempPath()).TrimEnd("").TrimEnd("\")
            $tempfile = "$temp\import-dbatools-perftemplate.xml"

            try {
                # Get content
                $contents = Get-Content $file -ErrorAction Stop

                # Replace content
                $replacements = 'RootPath', 'DisplayName', 'SchedulesEnabled', 'Segment', 'SegmentMaxDuration', 'SegmentMaxSize', 'SubdirectoryFormat', 'SubdirectoryFormatPattern', 'Task', 'TaskRunAsSelf', 'TaskArguments', 'TaskUserTextArguments', 'StopOnCompletion', 'DisplayNameUnresolved'

                foreach ($replacement in $replacements) {
                    $phrase = "<$replacement></$replacement>"
                    $value = (Get-Variable -Name $replacement -ErrorAction SilentlyContinue).Value
                    if ($value -eq $false) {
                        $value = "0"
                    }
                    if ($value -eq $true) {
                        $value = "1"
                    }
                    $replacephrase = "<$replacement>$value</$replacement>"
                    $contents = $contents.Replace($phrase, $replacephrase)
                }

                # Set content
                $null = Set-Content -Path $tempfile -Value $contents -Encoding Unicode
                $xml = [xml](Get-Content $tempfile -ErrorAction Stop)
                $plainxml = Get-Content $tempfile -ErrorAction Stop -Raw
                $file = $tempfile
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $file -Continue -FunctionName Import-DbaPfDataCollectorSetTemplate
            }
            if (-not $xml.DataCollectorSet) {
                Stop-Function -Message "$file is not a valid Performance Monitor template document" -Continue -FunctionName Import-DbaPfDataCollectorSetTemplate
            }

            try {
                Write-Message -Level Verbose -Message "Importing $file as $name "

                if ($instance) {
                    $instances = $instance
                } else {
                    $instances = Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock $instancescript -ErrorAction Stop -Raw
                }

                $scriptBlock = {
                    try {
                        $results = Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock $setscript -ArgumentList $Name, $plainxml -ErrorAction Stop
                        Write-Message -Level Verbose -Message " $results"
                    } catch {
                        Stop-Function -Message "Failure starting $setname on $computer" -ErrorRecord $_ -Target $computer -Continue -FunctionName Import-DbaPfDataCollectorSetTemplate
                    }
                }

                if ((Get-DbaPfDataCollectorSet -ComputerName $computer -CollectorSet $Name)) {
                    if ($__realCmdlet.ShouldProcess($computer, "CollectorSet $Name already exists. Modify?")) {
                        Invoke-Command -Scriptblock $scriptBlock
                        $output = Get-DbaPfDataCollectorSet -ComputerName $computer -CollectorSet $Name
                    }
                } else {
                    if ($__realCmdlet.ShouldProcess($computer, "Importing collector set $Name")) {
                        Invoke-Command -Scriptblock $scriptBlock
                        $output = Get-DbaPfDataCollectorSet -ComputerName $computer -CollectorSet $Name
                    }
                }

                $newcollection = @()
                foreach ($instance in $instances) {
                    $datacollector = Get-DbaPfDataCollectorSet -ComputerName $computer -CollectorSet $Name | Get-DbaPfDataCollector
                    $sqlcounters = $datacollector | Get-DbaPfDataCollectorCounter | Where-Object { $_.Name -match 'sql.*\:' -and $_.Name -notmatch 'sqlclient' } | Select-Object -ExpandProperty Name

                    foreach ($counter in $sqlcounters) {
                        $split = $counter.Split(":")
                        $firstpart = switch ($split[0]) {
                            'SQLServer' { 'MSSQL' }
                            '\SQLServer' { '\MSSQL' }
                            default { $split[0] }
                        }
                        $secondpart = $split[-1]
                        $finalcounter = "$firstpart`$$instance`:$secondpart"
                        $newcollection += $finalcounter
                    }
                }

                if ($newcollection.Count) {
                    if ($__realCmdlet.ShouldProcess($computer, "Adding $($newcollection.Count) additional counters")) {
                        $null = Add-DbaPfDataCollectorCounter -InputObject $datacollector -Counter $newcollection
                    }
                }

                Remove-Item $tempfile -ErrorAction SilentlyContinue
                $output
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $store -Continue -FunctionName Import-DbaPfDataCollectorSetTemplate
            }
        }
    }

    @{ __w1107State = @{ Path = $Path; DisplayName = $DisplayName; Name = $Name; RootName = $RootName; output = $output; instance = $instance; xml = $xml; plainxml = $plainxml; contents = $contents; instances = $instances; datacollector = $datacollector; sqlcounters = $sqlcounters; newcollection = $newcollection; templatepath = $templatepath } }
} $ComputerName $Credential $DisplayName $SchedulesEnabled $RootPath $Segment $SegmentMaxDuration $SegmentMaxSize $Subdirectory $SubdirectoryFormat $SubdirectoryFormatPattern $Task $TaskRunAsSelf $TaskArguments $TaskUserTextArguments $StopOnCompletion $Path $Template $Instance $__moduleRoot $__state $__pathBound $__templateBound $__displayNameBound $__rootPathBound $EnableException $__realCmdlet $__boundVerbose $__boundDebug 3>&1 2>&1
""";
}
