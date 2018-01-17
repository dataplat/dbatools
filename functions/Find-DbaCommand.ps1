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

        .NOTES
            Tags: Find,Help,Command
            Author: Simone Bizzotto

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Find-DbaCommand

        .EXAMPLE
            Find-DbaCommand "snapshot"

            For lazy typers: finds all commands searching the entire help for "snapshot"

        .EXAMPLE
            Find-DbaCommand -Pattern "snapshot"

            For rigorous typers: finds all commands searching the entire help for "snapshot"

        .EXAMPLE
            Find-DbaCommand -Tag copy

            Finds all commands tagged with "copy"

        .EXAMPLE
            Find-DbaCommand -Tag copy,user

            Finds all commands tagged with BOTH "copy" and "user"

        .EXAMPLE
            Find-DbaCommand -Author chrissy

            Finds every command whose author contains our beloved "chrissy"

        .EXAMPLE
            Find-DbaCommand -Author chrissy -Tag copy

            Finds every command whose author contains our beloved "chrissy" and it tagged as "copy"

        .EXAMPLE
            Find-DbaCommand -Pattern snapshot -Rebuild

            Finds all commands searching the entire help for "snapshot", rebuilding the index (good for developers)
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [String]$Pattern,
        [String[]]$Tag,
        [String]$Author,
        [String]$MinimumVersion,
        [String]$MaximumVersion,
        [switch]$Rebuild
    )
    begin {
        $tagsRex = ([regex]'(?m)^[\s]{0,15}Tags:(.*)$')
        $authorRex = ([regex]'(?m)^[\s]{0,15}Author:(.*)$')
        $minverRex = ([regex]'(?m)^[\s]{0,15}MinimumVersion:(.*)$')
        $maxverRex = ([regex]'(?m)^[\s]{0,15}MaximumVersion:(.*)$')

        function Get-DbaHelp([String]$commandName) {
            $thishelp = Get-Help $commandName -Full
            $thebase = @{ }
            $thebase.CommandName = $commandName
            $thebase.Name = $thishelp.Name

            ## fetch the description
            $thebase.Description = $thishelp.Description.Text

            ## fetch examples
            $thebase.Examples = $thishelp.Examples | Out-String -Width 120

            ## fetch help link
            $thebase.Links = ($thishelp.relatedLinks).NavigationLink.Uri

            ## fetch the synopsis
            $thebase.Synopsis = $thishelp.Synopsis

            ## store notes
            $as = $thishelp.AlertSet | Out-String -Width 120

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

            [pscustomobject]$thebase
        }

        function Get-DbaIndex() {
            if ($Pscmdlet.ShouldProcess($dest, "Recreating index")) {
                $dbamodule = Get-Module -Name dbatools
                $allCommands = $dbamodule.ExportedCommands.Values | Where-Object CommandType -EQ 'Function'

                $helpcoll = New-Object System.Collections.Generic.List[System.Object]
                foreach ($command in $allCommands) {
                    $x = Get-DbaHelp "$command"
                    $helpcoll.Add($x)
                }
                # $dest = Get-DbaConfigValue -Name 'Path.TagCache' -Fallback "$(Resolve-Path $PSScriptRoot\..)\dbatools-index.json"
                $dest = "$moduleDirectory\bin\dbatools-index.json"
                $helpcoll | ConvertTo-Json | Out-File $dest -Encoding UTF8
            }
        }

        $moduleDirectory = (Get-Module -Name dbatools).ModuleBase
    }
    process {
        $Pattern = $Pattern.TrimEnd("s")
        $idxFile = "$moduleDirectory\bin\dbatools-index.json"
        if (!(Test-Path $idxFile) -or $Rebuild) {
            Write-Verbose "Rebuilding index into $idxFile"
            $swRebuild = [system.diagnostics.stopwatch]::StartNew()
            Get-DbaIndex
            Write-Verbose "Rebuild done in $($swRebuild.ElapsedMilliseconds)ms"
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
