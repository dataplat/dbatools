function Find-DbaCommand {
    <#
    .SYNOPSIS
        Finds dbatools commands searching through the inline help text

    .DESCRIPTION
        Finds dbatools commands searching through the inline help text, building a consolidated json index and querying it because Get-Help is too slow

    .PARAMETER Tag
        Filters results to show only commands that contain all specified tags. Tags categorize commands by SQL Server feature area like "Backup", "AG", "Job", or "Security".
        Use this when you need to find commands related to specific SQL Server functionality. Multiple tags require commands to have ALL specified tags.

    .PARAMETER Author
        Filters results to show commands created by authors whose name contains the specified text. Uses wildcard matching so partial names work.
        Useful when you want to find commands written by a specific contributor or when following up on recommendations from particular experts.

    .PARAMETER MinimumVersion
        Filters results to show only commands that require the specified minimum version of dbatools or higher.
        Use this to ensure compatibility when working with older dbatools installations or when checking what features require recent updates.

    .PARAMETER MaximumVersion
        Filters results to show only commands that work with the specified maximum version of dbatools or lower.
        Helpful when working with legacy environments where you need to avoid commands that require newer dbatools versions.

    .PARAMETER Rebuild
        Forces a complete rebuild of the dbatools command index from the current module state. This rescans all help text and updates the cached index file.
        Use this when developing new commands, after updating dbatools, or when search results seem outdated or incomplete.

    .PARAMETER Pattern
        Searches all help text properties (synopsis, description, examples, parameters) for the specified text pattern using wildcard matching.
        Use this for broad searches when you know a concept or term but aren't sure which specific commands handle it.

    .PARAMETER Confirm
        Confirms overwrite of index

    .PARAMETER WhatIf
        Displays what would happen if the command is run

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Module, Lookup
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

    .OUTPUTS
        PSCustomObject

        Returns one object per dbatools command matching the specified filters.

        Default display properties (via Select-DefaultView):
        - CommandName: The name of the dbatools command
        - Synopsis: A brief one-line description of what the command does

        Additional properties available (use Select-Object * to see all):
        - Name: The full name of the command function
        - Availability: Platform availability (Windows, Linux, macOS or Windows only)
        - Alias: Comma-separated list of command aliases
        - Description: Detailed description of the command's functionality
        - Examples: Full examples section from the command's help text
        - Links: Related documentation links
        - Syntax: Complete syntax information for the command
        - Tags: Array of tags categorizing the command by feature area (Backup, AG, Job, Security, etc.)
        - Author: Name(s) of the command author(s)
        - MinimumVersion: Minimum dbatools version required to use this command
        - MaximumVersion: Maximum dbatools version supported by this command
        - Params: Array of parameter information (name, description, aliases, required status, pipeline support, default values, accepted values)

        All properties from the full command help index are accessible. Use Select-Object * to display all available properties for further analysis.
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
        function Get-DbaIndex() {
            if ($Pscmdlet.ShouldProcess($dest, "Recreating index")) {
                $dbamodule = Get-Module -Name dbatools
                $allCommands = $dbamodule.ExportedCommands.Values | Where-Object CommandType -In 'Function', 'Cmdlet' | Where-Object Name -NotIn 'Write-Message' | Sort-Object -Property Name | Select-Object -Unique
                #Had to add Unique because Select-DbaObject was getting populated twice once written to the index file

                $helpcoll = New-Object System.Collections.Generic.List[System.Object]
                foreach ($command in $allCommands) {
                    $x = Get-DbaHelp "$command"
                    $helpcoll.Add($x)
                }
                # $dest = Get-DbatoolsConfigValue -Name 'Path.TagCache' -Fallback "$(Resolve-Path $PSScriptRoot\..)\dbatools-index.json"
                $dest = Resolve-Path "$moduleDirectory\bin\dbatools-index.json"
                $helpcoll | ConvertTo-Json -Depth 4 | Out-File $dest -Encoding Unicode
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