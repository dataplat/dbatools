function DbaPfDataCollectionSetTemplate {
 <#
    .SYNOPSIS
    Parses Perf Monitor templates. Defaults to parsing templates in our template repository (\bin\perfmontemplates\)

    .DESCRIPTION
    Parses Perf Monitor XML templates. Defaults to parsing templates in our template repository (\bin\perfmontemplates\)

    .PARAMETER Path
    The path to the template directory. Defaults to our template repository (\bin\perfmontemplates\)
    
    .PARAMETER Pattern
    Specify a pattern for filtering. Alternatively, you can use Out-GridView -Passthru to select objects and pipe them to Import-DbaPfDataCollectionSetTemplate

    .PARAMETER Template
    From one or more of the templates we curated for you (tab through -Template to see options)
    
    .PARAMETER EnableException
    By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
    Website: https://dbatools.io
    Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
    License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

    .LINK
    https://dbatools.io/DbaPfDataCollectionSetTemplate

    .EXAMPLE
    DbaPfDataCollectionSetTemplate

    Returns information about all the templates in the local dbatools repository

    .EXAMPLE
    DbaPfDataCollectionSetTemplate | Out-GridView -PassThru | Import-DbaPfDataCollectionSetTemplate -ComputerName sql2017 | Start-DbaPfDataCollectorSet

    Allows you to select a template then deploy sit to sql2017 and immediately starts the datacollectorset

    .EXAMPLE
    DbaPfDataCollectionSetTemplate | Select *

    Returns more information about the template, including the full path/filename
#>
    [CmdletBinding()]
    param (
        [string[]]$Path = "$script:PSModuleRoot\bin\perfmontemplates",
        [string]$Pattern,
        [string[]]$Template,
        [switch]$EnableException
    )
    begin {
        $metadata = Import-Clixml "$script:PSModuleRoot\bin\perfmontemplates-metadata.xml"
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
                }
                catch {
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
                                Name                   = $dataset.name
                                Source                 = $meta.Source
                                UserAccount            = $dataset.useraccount
                                Description            = $dataset.Description
                                Path                   = $file
                                File                   = $file.Name
                            } | Select-DefaultView -ExcludeProperty File, Path
                        }
                    }
                    else {
                        [pscustomobject]@{
                            Name                    = $dataset.name
                            Source                  = $meta.Source
                            UserAccount             = $dataset.useraccount
                            Description             = $dataset.Description
                            Path                    = $file
                            File                    = $file.Name
                        } | Select-DefaultView -ExcludeProperty File, Path
                    }
                }
            }
        }
    }
}