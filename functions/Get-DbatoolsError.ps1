function Get-DbatoolsError {
    <#
    .SYNOPSIS
        Returns detailed error information

    .DESCRIPTION
        Returns detailed error information

        By default, it only returns the most recent error

    .PARAMETER First
        Works like `Select-Object -First 1`

    .PARAMETER Last
        Works like `Select-Object -Last 1`

    .PARAMETER Skip
        Works like `Select-Object -Skip 1`

    .PARAMETER All
        Returns detailed information for all errors

    .NOTES
        Tags: Module, Support
        Author: Chrissy LeMaire (@cl)

        Website: https://dbatools.io
        Copyright: (c) 2019 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbatoolsError

    .EXAMPLE
        PS C:\> Get-DbatoolsError

        Returns detailed error information for the most recent error


    .EXAMPLE
        PS C:\> Get-DbatoolsError -All

        Returns detailed error information for all errors


    .EXAMPLE
        PS C:\> Get-DbatoolsError -Last 1

        Returns the oldest error in the pipeline
    #>
    [CmdletBinding()]
    param (
        [int]$First,
        [int]$Last,
        [int]$Skip,
        [switch]$All
    )
    process {
        if (Test-Bound -not First, Last, Skip, All) {
            $First = 1
        }

        $global:error | Where-Object ScriptStackTrace -match dbatools | Select-Object -First $First -Last $Last -Skip $Skip -Property CategoryInfo, ErrorDetails, Exception, FullyQualifiedErrorId, InvocationInfo, PipelineIterationInfo, PSMessageDetails, ScriptStackTrace, TargetObject

    }
}