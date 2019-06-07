function Get-DbaPfDataCollectorSetTemplate {
    <#
    .SYNOPSIS
        Parses Perf Monitor templates. Defaults to parsing templates in the dbatools template repository (\bin\perfmontemplates\).

    .DESCRIPTION
        Parses Perf Monitor XML templates. Defaults to parsing templates in the dbatools template repository (\bin\perfmontemplates\).

    .PARAMETER Path
        The path to the template directory. Defaults to the dbatools template repository (\bin\perfmontemplates\).

    .PARAMETER Pattern
        Specify a pattern for filtering. Alternatively, you can use Out-GridView -Passthru to select objects and pipe them to Import-DbaPfDataCollectorSetTemplate.

    .PARAMETER Template
        Specifies one or more of the templates provided by dbatools. Press tab to cycle through the list to the options.

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

    .LINK
        https://dbatools.io/Get-DbaPfDataCollectorSetTemplate

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollectorSetTemplate

        Returns information about all the templates in the local dbatools repository.

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollectorSetTemplate | Out-GridView -PassThru | Import-DbaPfDataCollectorSetTemplate -ComputerName sql2017 | Start-DbaPfDataCollectorSet

        Allows you to select a template, then deploys it to sql2017 and immediately starts the DataCollectorSet.

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollectorSetTemplate | Select-Object *

        Returns more information about the template, including the full path/filename.

    #>
    [CmdletBinding()]
    param (
        [string[]]$Path = "$script:PSModuleRoot\bin\perfmontemplates\collectorsets",
        [string]$Pattern,
        [string[]]$Template,
        [switch]$EnableException
    )
    begin {
        $metadata = Import-Clixml "$script:PSModuleRoot\bin\perfmontemplates\collectorsets.xml"
        # In case people really want a "like" search, which is slower
        $Pattern = $Pattern.Replace("*", ".*").Replace("..*", ".*")
    }
    process {


        foreach ($directory in $Path) {
            $files = Get-ChildItem "$directory\*.xml"

            if ($Template) {
                $files = $files | Where-Object BaseName -in $Template
            }

            foreach ($file in $files) {
                try {
                    $xml = [xml](Get-Content $file)
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $file -Continue
                }

                foreach ($dataset in $xml.DataCollectorSet) {
                    $meta = $metadata | Where-Object Name -eq $dataset.name
                    if ($Pattern) {
                        if (
                            ($dataset.Name -match $Pattern) -or
                            ($dataset.Description -match $Pattern)
                        ) {
                            [pscustomobject]@{
                                Name        = $dataset.name
                                Source      = $meta.Source
                                UserAccount = $dataset.useraccount
                                Description = $dataset.Description
                                Path        = $file
                                File        = $file.Name
                            } | Select-DefaultView -ExcludeProperty File, Path
                        }
                    } else {
                        [pscustomobject]@{
                            Name        = $dataset.name
                            Source      = $meta.Source
                            UserAccount = $dataset.useraccount
                            Description = $dataset.Description
                            Path        = $file
                            File        = $file.Name
                        } | Select-DefaultView -ExcludeProperty File, Path
                    }
                }
            }
        }
    }
}