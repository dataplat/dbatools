function Find-DbaCommand {
    <#
    .SYNOPSIS
        Finds dbatools commands searching through the inline help text

    .DESCRIPTION
        Finds dbatools commands searching through the inline help text, building a consolidated json index and querying it because Get-Help is too slow

    .PARAMETER Tag
        Finds all commands tagged with this auto-populated tag

    .PARAMETER Author
        Finds all commands tagged with this author

    .PARAMETER MinimumVersion
        Finds all commands tagged with this auto-populated minimum version

    .PARAMETER MaximumVersion
        Finds all commands tagged with this auto-populated maximum version

    .PARAMETER Rebuild
        Rebuilds the index

    .PARAMETER Pattern
        Searches help for all commands in dbatools for the specified pattern and displays all results

    .PARAMETER Confirm
        Confirms overwrite of index

    .PARAMETER WhatIf
        Displays what would happen if the command is run

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Module, Find
        Author: Simone Bizzotto (@niphlod)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Find-DbaCommand

    .EXAMPLE
        PS C:\> Find-DbaCommand "snapshot"

        For lazy typers: finds all commands searching the entire help for "snapshot"

    .EXAMPLE
        PS C:\> Find-DbaCommand -Pattern "snapshot"

        For rigorous typers: finds all commands searching the entire help for "snapshot"

    .EXAMPLE
        PS C:\> Find-DbaCommand -Tag Job

        Finds all commands tagged with "Job"

    .EXAMPLE
        PS C:\> Find-DbaCommand -Tag Job,Owner

        Finds all commands tagged with BOTH "Job" and "Owner"

    .EXAMPLE
        PS C:\> Find-DbaCommand -Author Chrissy

        Finds every command whose author contains our beloved "Chrissy"

    .EXAMPLE
        PS C:\> Find-DbaCommand -Author Chrissy -Tag AG

        Finds every command whose author contains our beloved "Chrissy" and it tagged as "AG"

    .EXAMPLE
        PS C:\> Find-DbaCommand -Pattern snapshot -Rebuild

        Finds all commands searching the entire help for "snapshot", rebuilding the index (good for developers)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [String]$Pattern,
        [String[]]$Tag,
        [String]$Author,
        [String]$MinimumVersion,
        [String]$MaximumVersion,
        [switch]$Rebuild,
        [switch]$EnableException
    )
    begin {
        function Get-DbaTrimmedString($Text) {
            return $Text.Trim() -replace '(\r\n){2,}', "`n"
        }

        $tagsRex = ([regex]'(?m)^[\s]{0,15}Tags:(.*)$')
        $authorRex = ([regex]'(?m)^[\s]{0,15}Author:(.*)$')
        $minverRex = ([regex]'(?m)^[\s]{0,15}MinimumVersion:(.*)$')
        $maxverRex = ([regex]'(?m)^[\s]{0,15}MaximumVersion:(.*)$')

        function Get-DbaHelp([String]$commandName) {
            $availability = 'Windows, Linux, macOS'
            if ($commandName -in $script:noncoresmo -or $commandName -in $script:windowsonly) {
                $availability = 'Windows only'
            }
            try {
                $thishelp = Get-Help $commandName -Full
            } catch {
                Stop-Function -Message "Issue getting help for $commandName" -Target $commandName -ErrorRecord $_ -Continue
            }

            $thebase = @{ }
            $thebase.CommandName = $commandName
            $thebase.Name = $thishelp.Name

            $thebase.Availability = $availability

            $alias = Get-Alias -Definition $commandName -ErrorAction SilentlyContinue
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
            $command = Get-Command $commandName
            $params = @()
            foreach ($p in $parameters) {
                $paramAlias = $command.parameters[$p.Name].Aliases
                $paramDescr = Get-DbaTrimmedString -Text ($p.Description | Out-String -Width 200)
                $params += , @($p.Name, $paramDescr, ($paramAlias -Join ','), ($p.Required -eq $true), $p.PipelineInput, $p.DefaultValue)
            }

            $thebase.Params = $params

            [pscustomobject]$thebase
        }

        function Get-DbaIndex() {
            if ($Pscmdlet.ShouldProcess($dest, "Recreating index")) {
                $dbamodule = Get-Module -Name dbatools
                $allCommands = $dbamodule.ExportedCommands.Values | Where-Object CommandType -In 'Function', 'Cmdlet' | Sort-Object -Property Name | Select-Object -Unique
                #Had to add Unique because Select-DbaObject was getting populated twice once written to the index file

                $helpcoll = New-Object System.Collections.Generic.List[System.Object]
                foreach ($command in $allCommands) {
                    $x = Get-DbaHelp "$command"
                    $helpcoll.Add($x)
                }
                # $dest = Get-DbatoolsConfigValue -Name 'Path.TagCache' -Fallback "$(Resolve-Path $PSScriptRoot\..)\dbatools-index.json"
                $dest = Resolve-Path "$moduleDirectory\bin\dbatools-index.json"
                $helpcoll | ConvertTo-Json -Depth 4 | Out-File $dest -Encoding UTF8
            }
        }

        $moduleDirectory = $script:PSModuleRoot
    }
    process {
        $Pattern = $Pattern.TrimEnd("s")
        $idxFile = Resolve-Path "$moduleDirectory\bin\dbatools-index.json"
        if (!(Test-Path $idxFile) -or $Rebuild) {
            Write-Message -Level Verbose -Message "Rebuilding index into $idxFile"
            $swRebuild = [system.diagnostics.stopwatch]::StartNew()
            Get-DbaIndex
            Write-Message -Level Verbose -Message "Rebuild done in $($swRebuild.ElapsedMilliseconds)ms"
        }
        $consolidated = Get-Content -Raw $idxFile | ConvertFrom-Json
        $result = $consolidated
        if ($Pattern.Length -gt 0) {
            $result = $result | Where-Object { $_.PsObject.Properties.Value -like "*$Pattern*" }
        }

        if ($Tag.Length -gt 0) {
            foreach ($t in $Tag) {
                $result = $result | Where-Object Tags -Contains $t
            }
        }

        if ($Author.Length -gt 0) {
            $result = $result | Where-Object Author -Like "*$Author*"
        }

        if ($MinimumVersion.Length -gt 0) {
            $result = $result | Where-Object MinimumVersion -GE $MinimumVersion
        }

        if ($MaximumVersion.Length -gt 0) {
            $result = $result | Where-Object MaximumVersion -LE $MaximumVersion
        }

        Select-DefaultView -InputObject $result -Property CommandName, Synopsis
    }
}