function Measure-DbatoolsImport {
    <#
    .SYNOPSIS
        Displays the import load times of the dbatools PowerShell module

    .DESCRIPTION
        Displays the import load times of the dbatools PowerShell module

    .NOTES
        Tags: Module, Support
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Measure-DbatoolsImport

    .EXAMPLE
        PS C:\> Measure-DbatoolsImport
        Displays the import load times of the dbatools PowerShell module

    .EXAMPLE
        PS C:\> Import-Module dbatools
        PS C:\> Measure-DbatoolsImport

        Displays the import load times of the dbatools PowerShell module
    #>
    [Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::ImportTime
}