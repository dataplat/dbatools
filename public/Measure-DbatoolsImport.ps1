function Measure-DbatoolsImport {
    <#
    .SYNOPSIS
        Measures and displays detailed timing metrics for dbatools module import operations

    .DESCRIPTION
        Returns performance data collected during the dbatools module import process, showing the duration of each import step. This function helps troubleshoot slow module loading times by identifying which components take the longest to initialize. The timing data includes loading the dbatools library, type aliases, internal commands, external commands, and other initialization steps. Only displays steps that took measurable time (greater than 00:00:00) to complete.

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
    $script:dbatools_ImportPerformance | Where-Object Duration -ne '00:00:00'
}