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
        https://dbatools.io/Get-DbaHelp


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
            $null = $rtn.Add('Want to see the source code for this command? Check out [' + $doc_to_render.CommandName + '](https://github.com/dataplat/dbatools/blob/master/public/' + $doc_to_render.CommandName + '.ps1) on GitHub.')
            $null = $rtn.Add("<br>")
            $null = $rtn.Add('Want to see the Bill Of Health for this command? Check out [' + $doc_to_render.CommandName + '](https://dataplat.github.io/boh#' + $doc_to_render.CommandName + ').')
            $null = $rtn.Add('## Synopsis')
            $null = $rtn.Add($doc_to_render.Synopsis.Replace("`n", "  `n"))
            $null = $rtn.Add('')
            $null = $rtn.Add('## Description')
            if ($doc_to_render.Description) {
                $null = $rtn.Add($doc_to_render.Description.Replace("`n", "  `n"))
            }
            $null = $rtn.Add('')
            if ($doc_to_render.Outputs) {
                $null = $rtn.Add('## Outputs')
                $null = $rtn.Add($doc_to_render.Outputs.Replace("`n", "  `n"))
                $null = $rtn.Add('')
            }
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
                    foreach ($val in ($syntax.Replace("`r", '').Replace("`n", '') -split ' \[')) {
                        if ($x -eq 0) {
                            $null = $rtn.Add($val)
                        } else {
                            $xx = 0
                            foreach ($subparam in ($val -split ' -')) {
                                if ($xx -eq 0) {
                                    $null = $rtn.Add('    [' + $subparam.replace("`n", '').replace("`n", ''))
                                } else {
                                    $null = $rtn.Add('    -' + $subparam.replace("`n", '').replace("`n", ''))
                                }
                                $xx += 1
                            }
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
                    $null = $rtn.Add("$($row.Replace("`n", "  `n"))<br>")
                }
            }
            if ($inside -eq 1) {
                $inside = 0
                $null = $rtn.Add('```')
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
                    $null = $rtn.Add($el[1].Replace("`r", "").Replace("`n", "  `n") + ' <br>')
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
                    $null = $rtn.Add($el[1].Replace("`r", "").Replace("`n", "  `n") + '<br>')
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

        ## fetch outputs
        $thebase.Outputs = Get-DbaTrimmedString -Text ($thishelp.returnValues | Out-String -Width 200)

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

        if ($thebase.CommandName -eq "Select-DbaObject") {
            $thebase.Synopsis = "Wrapper around Select-Object, extends property parameter."
            $thebase.Author = "Friedrich Weinmann (@FredWeinmann)"
            $thebase.Description = "Wrapper around Select-Object, extends property parameter.

            This function allows specifying in-line transformation of the properties specified without needing to use complex hashtables.
            For example, renaming a property becomes as simple as 'Length as Size'

            Also supported:

            - Specifying a typename

            - Picking the default display properties

            - Adding to an existing object without destroying its type

            See the description of the Property parameter for an exhaustive list of legal notations for in-line transformations."
            $thebase.Examples = '    ---------------- Example 1: Renaming a property ----------------
            Get-ChildItem | Select-DbaObject Name, "Length as Size"

            Selects the properties Name and Length, renaming Length to Size in the process.

            ------------------ Example 2: Converting type ------------------

            Import-Csv .\file.csv | Select-DbaObject Name, "Length as Size to DbaSize"

            Selects the properties Name and Length, renaming Length to Size and converting it to [DbaSize] (a userfriendly representation of
            size numbers contained in the dbatools module)

            ---------- Example 3: Selecting from another object 1 ----------

            $obj = [PSCustomObject]@{ Name = "Foo" }
            Get-ChildItem | Select-DbaObject FullName, Length, "Name from obj"

            Selects the properties FullName and Length from the input and the Name property from the object stored in $obj

            ---------- Example 4: Selecting from another object 2 ----------

            $list = @()
            $list += [PSCustomObject]@{ Type = "Foo"; ID = 1 }
            $list += [PSCustomObject]@{ Type = "Bar"; ID = 2 }
            $obj | Select-DbaObject Name, "ID from list WHERE Type = Name"

            This allows you to LEFT JOIN contents of another variable. Note that it can only do simple property-matching at this point.

            It will select Name from the objects stored in $obj, and for each of those the ID Property on any object in $list that has a
            Type property of equal value as Name on the input.

            ---------------- Example 5: Naming and styling ----------------

            Get-ChildItem | Select-DbaObject Name, Length, FullName, Used, LastWriteTime, Mode -TypeName MyType -ShowExcludeProperty Mode,
            Used

            Lists all items in the current path, selects the properties specified (whether they exist or not) , then ...

            - Sets the name to "MyType"

            - Hides the properties "Mode" and "Used" from the default display set, causing them to be hidden from default view'
            $thebase.Syntax = "Select-DbaObject [-Property <DbaSelectParameter[]>] [-Alias <SelectAliasParameter[]>] [-ScriptProperty <SelectScriptPropertyParameter[]>] [-ScriptMethod <SelectScriptMethodParameter[]>] [-InputObject ] [-ExcludeProperty <string[]>] [-ExpandProperty ] -Unique [-Last ] [-First ] [-Skip ] -Wait [-ShowProperty <string[]>] [-ShowExcludeProperty <string[]>] [-TypeName ] -KeepInputObject []

            Select-DbaObject [-Property <DbaSelectParameter[]>] [-Alias <SelectAliasParameter[]>] [-ScriptProperty <SelectScriptPropertyParameter[]>] [-ScriptMethod <SelectScriptMethodParameter[]>] [-InputObject ] [-ExcludeProperty <string[]>] [-ExpandProperty ] -Unique [-SkipLast ] [-ShowProperty <string[]>] [-ShowExcludeProperty <string[]>] [-TypeName ] -KeepInputObject []

            Select-DbaObject [-InputObject ] -Unique -Wait [-Index <int[]>] [-ShowProperty <string[]>] [-ShowExcludeProperty <string[]>] [-TypeName ] -KeepInputObject []"
        }

        if ($thebase.CommandName -eq "Set-DbatoolsConfig") {
            $thebase.Name = "Set-DbatoolsConfig"
            $thebase.CommandName = "Set-DbatoolsConfig"
            $thebase.Synopsis = 'Sets configuration entries.'
            $thebase.Author = "Friedrich Weinmann (@FredWeinmann)"
            $thebase.Description = 'This function creates or changes configuration values. These can be used to provide dynamic configuration information outside the PowerShell variable system.'
            $thebase.Examples = '---------------------- Example 1: Simple ----------------------
            C:\PS> Set-DbatoolsConfig -FullName Path.DbatoolsData -Value E:\temp\dbatools

            Updates the configuration entry for Path.DbatoolsData to E:\temp\dbatools'
            $thebase.Syntax = 'Set-DbatoolsConfig -FullName <String> [-Value <Object>] [-Description <String>] [-Validation <String>] [-Handler <ScriptBlock>]
            [-Hidden] [-Default] [-Initialize] [-DisableValidation] [-DisableHandler] [-EnableException] [-SimpleExport] [-ModuleExport]
            [-PassThru] [-AllowDelete] [<CommonParameters>]

            Set-DbatoolsConfig -FullName <String> [-Description <String>] [-Validation <String>] [-Handler <ScriptBlock>] [-Hidden]
            [-Default] [-Initialize] [-DisableValidation] [-DisableHandler] [-EnableException] -PersistedValue <String> [-PersistedType
            <ConfigurationValueType>] [-SimpleExport] [-ModuleExport] [-PassThru] [-AllowDelete] [<CommonParameters>]

            Set-DbatoolsConfig -Name <String> [-Module <String>] [-Value <Object>] [-Description <String>] [-Validation <String>] [-Handler
            <ScriptBlock>] [-Hidden] [-Default] [-Initialize] [-DisableValidation] [-DisableHandler] [-EnableException] [-SimpleExport]
            [-ModuleExport] [-PassThru] [-AllowDelete] [<CommonParameters>]'
        }
        if ($OutputAs -eq "PSObject") {
            [PSCustomObject]$thebase
        } elseif ($OutputAs -eq "MDString") {
            Get-DbaDocsMD -doc_to_render $thebase
        }

    }
    end {

    }
}