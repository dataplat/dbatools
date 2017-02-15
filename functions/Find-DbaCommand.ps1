Function Find-DbaCommand
{
<#
.SYNOPSIS
Finds dbatools commands searching through the inline help text

.DESCRIPTION
Finds dbatools commands searching through the inline help text, building a consolidated json index and querying it because Get-Help is too slow

.PARAMETER Tag
Finds all commands tagged with this tag

.PARAMETER Author
Finds all commands tagged with this author

.PARAMETER Rebuild
Rebuilds the index

.PARAMETER Pattern
Searches help for all commands in dbatools for the specified pattern and displays all results

.PARAMETER Confirm
Confirms overwrite of index

.PARAMETER WhatIf
Displays what would happen if the command is run

.NOTES
Tags: find
Author: niphlod

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

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
Find-DbaCommand -Author chrissy

Finds every command whose author contains our beloved "chrissy"

.EXAMPLE
Find-DbaCommand -Pattern snapshot -Rebuild

Finds all commands searching the entire help for "snapshot", rebuilding the index (good for developers)
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    Param (
        [String]$Pattern,
        [String]$Tag,
        [String]$Author,
        [switch]$Rebuild
    )
    BEGIN
    {
        $tagsRex = ([regex]'(?m)^[\s]{0,15}Tags:(.*)$')
        $authorRex = ([regex]'(?m)^[\s]{0,15}Author:(.*)$')

        function Get-DbaHelp([String]$commandname) {
            $thishelp = Get-Help $commandname -Full
            $thebase = @{}
            $thebase.CommandName = $commandname
            $thebase.Name = $thishelp.name

            ## fetch the description
            $thebase.Description = $thishelp.Description.text

            ## fetch examples
            $thebase.Examples = $thishelp.Examples | Out-String -Width 120

            ## fetch help link
            $thebase.Links = ($thishelp.relatedLinks).navigationLink.uri

            ## fetch the synopsis
            $thebase.Synopsis = $thishelp.Synopsis

            ## store notes
            $as = $thishelp.alertSet | Out-String -Width 120

            ## fetch the tags
            $tags = $tagsrex.Match($as).Groups[1].Value
            if($tags) {
                $thebase.Tags = $tags.Trim().Split(',')
            }
            ## fetch the author
            $author = $authorRex.Match($as).Groups[1].Value
            if($author) {
                $thebase.Author = $author.Trim()
            }

            [pscustomobject]$thebase
        }

        function Get-DbaIndex() {
            $dbamodule = Get-Module -Name dbatools
            $allcommands = $dbamodule.ExportedCommands
            $helpcoll = New-Object System.Collections.Generic.List[System.Object]
            foreach($c in $allcommands.GetEnumerator()) {
                $x = Get-DbaHelp $c.Key
                $helpcoll.Add($x)
			}
						
			# $dest = Get-DbaConfigValue -Name 'Path.TagCache' -Fallback "$(Resolve-Path $PSScriptRoot\..)\dbatools-index.json"
			$dest = "$moduledirectory\bin\dbatools-index.json"
            if ($Pscmdlet.ShouldProcess($dest, "Recreating index"))
            {
                $helpcoll | ConvertTo-Json | Out-File $dest
            }
		}
		
		$moduledirectory = (Get-Module -Name dbatools).ModuleBase
	}
	PROCESS
    {
		# $idxfile = Get-DbaConfigValue -Name 'Path.TagCache' -Fallback "$(Resolve-Path $PSScriptRoot\..)\dbatools-index.json"
		$idxfile = "$moduledirectory\bin\dbatools-index.json"
        if(!(Test-Path $idxfile) -or $Rebuild) {
            Write-Verbose "Rebuilding index into $idxfile"
            $swrebuild = [system.diagnostics.stopwatch]::startNew()
            Get-DbaIndex
            Write-Verbose "Rebuild done in $($swrebuild.Elapsedmilliseconds)ms"

        }
        $consolidated = Get-Content $idxfile | ConvertFrom-Json
        $result = $consolidated
        if($Pattern.length -gt 0) {
            $result = $result | Where-Object { $_.psobject.properties.value -like "*$Pattern*" }
		}
		
		if ($Tag.length -gt 0)
		{
			# need to remove the spaces in tags, added for human ease. 
			# I forgot how to pretty tho, so match for now
			# less accurate, needs help
			$result = $result | Where-Object { $_.Tags -match $tag }
		}
		
        if($Author.length -gt 0) {
            $result = $result | Where-Object Author -like "*$Author*"
        }
        Select-DefaultView -InputObject $result -Property CommandName, Synopsis
    }
}
