function Get-DbaHelp {
    <#
    .SYNOPSIS
        Massages inline help data to a more useful format

    .DESCRIPTION
        Takes the inline help and outputs a more usable object

    .PARAMETER Name
        The function/command to extract help from

    .PARAMETER OutputAs
        Output format (raw PSObject or MDString)

    .NOTES
    Author: Simone Bizzotto (@niphlod)

    Website: https://dbatools.io
    Copyright: (c) 2018 by dbatools, licensed under MIT
    License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Find-DbaCommand


    .EXAMPLE
        Get-DbaHelp Get-DbaDatabase

        Parses the inline help from Get-DbaDatabase and outputs the massaged object

    .EXAMPLE
        Get-DbaHelp Get-DbaDatabase -OutputAs "PSObject"

        Parses the inline help from Get-DbaDatabase and outputs the massaged object

    .EXAMPLE
        PS C:\> Get-DbaHelp Get-DbaDatabase -OutputAs "MDString" | Out-File Get-DbaDatabase.md
        PS C:\> & code Get-DbaDatabase.md

        Parses the inline help from Get-DbaDatabase as MarkDown, saves the file and opens it
        via VSCode

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory)]
        [string]$Name,

        [ValidateSet("PSObject", "MDString")]
        [string]$OutputAs = "PSObject"
    )

    begin {
        function Get-DbaTrimmedString($Text) {
            return $Text.Trim() -replace '(\r\n){2,}', "`n"
        }

        $tagsRex = ([regex]'(?m)^[\s]{0,15}Tags:(.*)$')
        $authorRex = ([regex]'(?m)^[\s]{0,15}Author:(.*)$')
        $minverRex = ([regex]'(?m)^[\s]{0,15}MinimumVersion:(.*)$')
        $maxverRex = ([regex]'(?m)^[\s]{0,15}MaximumVersion:(.*)$')
        $availability = 'Windows, Linux, macOS'

        function Get-DbaDocsMD($doc_to_render) {

            $rtn = New-Object -TypeName "System.Collections.ArrayList"
            $null = $rtn.Add("# $($doc_to_render.CommandName)" )
            if ($doc_to_render.Author -or $doc_to_render.Availability) {
                $null = $rtn.Add('|  |  |')
                $null = $rtn.Add('| - | - |')
                if ($doc_to_render.Author) {
                    $null = $rtn.Add('|  **Author**  | ' + $doc_to_render.Author.replace('|', ',') + ' |')
                }
                if ($doc_to_render.Availability) {
                    $null = $rtn.Add('| **Availability** | ' + $doc_to_render.Availability + ' |')
                }
                $null = $rtn.Add('')
            }
            $null = $rtn.Add("`n" + '&nbsp;' + "`n")
            if ($doc_to_render.Alias) {
                $null = $rtn.Add('')
                $null = $rtn.Add('*Aliases : ' + $doc_to_render.Alias + '*')
                $null = $rtn.Add('')
            }
            $null = $rtn.Add('## Synopsis')
            $null = $rtn.Add($doc_to_render.Synopsis)
            $null = $rtn.Add('')
            $null = $rtn.Add('## Description')
            $null = $rtn.Add($doc_to_render.Description)
            $null = $rtn.Add('')
            if ($doc_to_render.Syntax) {
                $null = $rtn.Add('## Syntax')
                $null = $rtn.Add('```')
                $splitted_paramsets = @()
                foreach ($val in ($doc_to_render.Syntax -split $doc_to_render.CommandName)) {
                    if ($val) {
                        $splitted_paramsets += $doc_to_render.CommandName + $val
                    }
                }
                foreach ($syntax in $splitted_paramsets) {
                    $x = 0
                    foreach ($val in ($syntax -split '[\[]+-')) {
                        if ($x -eq 0) {
                            $null = $rtn.Add($val)
                        } else {
                            $null = $rtn.Add('    [-' + $val.replace("`n", '').replace("`n", ''))
                        }
                        $x += 1
                    }
                    $null = $rtn.Add('')
                }

                $null = $rtn.Add('```')
                $null = $rtn.Add("`n" + '&nbsp;' + "`n")
            }
            $null = $rtn.Add('')
            $null = $rtn.Add('## Examples')
            $null = $rtn.Add("`n" + '&nbsp;' + "`n")
            $examples = $doc_to_render.Examples.Replace("`r`n", "`n") -replace '(\r\n){2,8}', '\n'
            $examples = $examples.replace("`r", '').split("`n")
            $inside = 0
            foreach ($row in $examples) {
                if ($row -like '*----') {
                    $null = $rtn.Add("");
                    $null = $rtn.Add('#####' + ($row -replace '-{4,}([^-]*)-{4,}', '$1').replace('EXAMPLE', 'Example: '))
                } elseif (($row -like 'PS C:\>*') -or ($row -like '>>*')) {
                    if ($inside -eq 0) { $null = $rtn.Add('```') }
                    $null = $rtn.Add(($row.Trim() -replace 'PS C:\\>\s*', "PS C:\> "))
                    $inside = 1
                } elseif ($row.Trim() -eq '' -or $row.Trim() -eq 'Description') {

                } else {
                    if ($inside -eq 1) {
                        $inside = 0
                        $null = $rtn.Add('```')
                    }
                    $null = $rtn.Add($row)
                }

            }
            if ($doc_to_render.Params) {
                $dotitle = 0
                $filteredparams = @()
                foreach ($p in $doc_to_render.Params) {
                    if ($p[3] -eq $true) {
                        $filteredparams += , $p
                    }
                }
                $dotitle = 0
                foreach ($el in $filteredparams) {
                    if ($dotitle -eq 0) {
                        $dotitle = 1
                        $null = $rtn.Add('### Required Parameters')
                    }
                    $null = $rtn.Add('##### -' + $el[0])
                    $null = $rtn.Add($el[1])
                    $null = $rtn.Add('')
                    $null = $rtn.Add('|  |  |')
                    $null = $rtn.Add('| - | - |')
                    $null = $rtn.Add('| Alias | ' + $el[2] + ' |')
                    $null = $rtn.Add('| Required | ' + $el[3] + ' |')
                    $null = $rtn.Add('| Pipeline | ' + $el[4] + ' |')
                    $null = $rtn.Add('| Default Value | ' + $el[5] + ' |')
                    if ($el[6]) {
                        $null = $rtn.Add('| Accepted Values | ' + $el[6] + ' |')
                    }
                    $null = $rtn.Add('')
                }
                $dotitle = 0
                $filteredparams = @()
                foreach ($p in $doc_to_render.Params) {
                    if ($p[3] -eq $false) {
                        $filteredparams += , $p
                    }
                }
                foreach ($el in $filteredparams) {
                    if ($dotitle -eq 0) {
                        $dotitle = 1
                        $null = $rtn.Add('### Optional Parameters')
                    }

                    $null = $rtn.Add('##### -' + $el[0])
                    $null = $rtn.Add($el[1])
                    $null = $rtn.Add('')
                    $null = $rtn.Add('|  |  |')
                    $null = $rtn.Add('| - | - |')
                    $null = $rtn.Add('| Alias | ' + $el[2] + ' |')
                    $null = $rtn.Add('| Required | ' + $el[3] + ' |')
                    $null = $rtn.Add('| Pipeline | ' + $el[4] + ' |')
                    $null = $rtn.Add('| Default Value | ' + $el[5] + ' |')
                    if ($el[6]) {
                        $null = $rtn.Add('| Accepted Values | ' + $el[6] + ' |')
                    }
                    $null = $rtn.Add('')
                }
            }

            $null = $rtn.Add('')
            $null = $rtn.Add("`n" + '&nbsp;' + "`n")
            $null = $rtn.Add('Want to see the source code for this command? Check out [' + $doc_to_render.CommandName + '](https://github.com/sqlcollaborative/dbatools/blob/master/functions/' + $doc_to_render.CommandName + '.ps1) on GitHub.')
            $null = $rtn.Add('Want to see the Bill Of Health for this command? Check out [' + $doc_to_render.CommandName + '](https://sqlcollaborative.github.io/boh#' + $doc_to_render.CommandName + ').')
            $null = $rtn.Add('')

            return $rtn
        }


    }
    process {

        if ($Name -in $script:noncoresmo -or $Name -in $script:windowsonly) {
            $availability = 'Windows only'
        }
        try {
            $thishelp = Get-Help $Name -Full
        } catch {
            Stop-Function -Message "Issue getting help for $Name" -Target $Name -ErrorRecord $_ -Continue
        }

        $thebase = @{ }
        $thebase.CommandName = $Name
        $thebase.Name = $thishelp.Name

        $thebase.Availability = $availability

        $alias = Get-Alias -Definition $Name -ErrorAction SilentlyContinue
        $thebase.Alias = $alias.Name -Join ','

        ## fetch the description
        $thebase.Description = $thishelp.Description.Text

        ## fetch examples
        $thebase.Examples = Get-DbaTrimmedString -Text ($thishelp.Examples | Out-String -Width 200)

        ## fetch help link
        $thebase.Links = ($thishelp.relatedLinks).NavigationLink.Uri

        ## fetch the synopsis
        $thebase.Synopsis = $thishelp.Synopsis

        ## fetch the syntax
        $thebase.Syntax = Get-DbaTrimmedString -Text ($thishelp.Syntax | Out-String -Width 600)

        ## store notes
        $as = $thishelp.AlertSet | Out-String -Width 600

        ## fetch the tags
        $tags = $tagsrex.Match($as).Groups[1].Value
        if ($tags) {
            $thebase.Tags = $tags.Split(',').Trim()
        }
        ## fetch the author
        $author = $authorRex.Match($as).Groups[1].Value
        if ($author) {
            $thebase.Author = $author.Trim()
        }

        ## fetch MinimumVersion
        $MinimumVersion = $minverRex.Match($as).Groups[1].Value
        if ($MinimumVersion) {
            $thebase.MinimumVersion = $MinimumVersion.Trim()
        }

        ## fetch MaximumVersion
        $MaximumVersion = $maxverRex.Match($as).Groups[1].Value
        if ($MaximumVersion) {
            $thebase.MaximumVersion = $MaximumVersion.Trim()
        }

        ## fetch Parameters
        $parameters = $thishelp.parameters.parameter
        $command = Get-Command $Name
        $params = @()
        foreach ($p in $parameters) {
            $paramAlias = $command.parameters[$p.Name].Aliases
            $validValues = $command.parameters[$p.Name].Attributes.ValidValues -Join ','
            $paramDescr = Get-DbaTrimmedString -Text ($p.Description | Out-String -Width 200)
            $params += , @($p.Name, $paramDescr, ($paramAlias -Join ','), ($p.Required -eq $true), $p.PipelineInput, $p.DefaultValue, $validValues)
        }

        $thebase.Params = $params

        if ($OutputAs -eq "PSObject") {
            [pscustomobject]$thebase
        } elseif ($OutputAs -eq "MDString") {
            Get-DbaDocsMD -doc_to_render $thebase
        }

    }
    end {

    }
}