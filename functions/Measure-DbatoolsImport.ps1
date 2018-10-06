function Measure-DbatoolsImport {
    <#
    .SYNOPSIS
    Displays the import load times of the dbatools PowerShell module

    .DESCRIPTION
    Displays the import load times of the dbatools PowerShell module

    .NOTES
    Author: Chrissy LeMaire (@cl), netnerds.net
    Website: https://dbatools.io
    Copyright: (c) 2018 by dbatools, licensed under MIT
    License: MIT https://opensource.org/licenses/MIT

    .LINK
    https://dbatools.io/Measure-DbatoolsImport

    .EXAMPLE
    Measure-DbatoolsImport
    Displays the import load times of the dbatools PowerShell module

    .EXAMPLE
    Import-Module dbatools
    Measure-DbatoolsImport
    
    Displays the import load times of the dbatools PowerShell module
    
    #>
    [Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::ImportTime
}