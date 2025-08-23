function Get-DbaPfDataCollectorSetTemplate {
    <#
    .SYNOPSIS
        Retrieves Windows Performance Monitor templates designed for SQL Server monitoring and troubleshooting.

    .DESCRIPTION
        Retrieves information about predefined Windows Performance Monitor (PerfMon) templates specifically created for SQL Server performance analysis. These templates include counter sets for monitoring long-running queries, PAL (Performance Analysis of Logs) configurations for different SQL Server versions, and other SQL Server-focused performance scenarios.

        The function parses XML template files and returns details like template names, descriptions, sources, and file paths. Use this to discover available monitoring templates before deploying them with Import-DbaPfDataCollectorSetTemplate, eliminating the need to manually browse template directories or guess what counters to collect for specific performance issues.

    .PARAMETER Path
        Specifies the directory path containing Performance Monitor template XML files. Defaults to the dbatools built-in template repository (\bin\perfmontemplates\collectorsets).
        Use this when you have custom template files stored in a different location or want to load templates from a network share.

    .PARAMETER Pattern
        Filters templates by matching text patterns against template names and descriptions using regex syntax. Supports wildcards (* becomes .*).
        Use this to find templates for specific scenarios like "long.*query" to locate long-running query monitoring templates.

    .PARAMETER Template
        Specifies one or more template names to retrieve by exact match. Accepts multiple values and supports tab completion to browse available templates.
        Use this when you know the specific template names you need rather than browsing all available templates.

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
                            [PSCustomObject]@{
                                Name        = $dataset.name
                                Source      = $meta.Source
                                UserAccount = $dataset.useraccount
                                Description = $dataset.Description
                                Path        = $file
                                File        = $file.Name
                            } | Select-DefaultView -ExcludeProperty File, Path
                        }
                    } else {
                        [PSCustomObject]@{
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