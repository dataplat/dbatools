function Get-DbatoolsError {
    <#
    .SYNOPSIS
        Retrieves detailed error information from failed dbatools commands for troubleshooting

    .DESCRIPTION
        Retrieves detailed error information specifically from dbatools command failures, filtering the PowerShell error collection to show only dbatools-related errors. This provides comprehensive diagnostic details including exception messages, stack traces, and invocation information that help troubleshoot SQL Server connection issues, permission problems, or command syntax errors. By default, it returns only the most recent dbatools error, but can retrieve all historical dbatools errors for pattern analysis or support requests.

    .PARAMETER First
        Works like `Select-Object -First 1`

    .PARAMETER Last
        Works like `Select-Object -Last 1`

    .PARAMETER Skip
        Works like `Select-Object -Skip 1`

    .PARAMETER All
        Returns detailed information for all dbatools-related errors

    .NOTES
        Tags: Module, Support
        Author: Chrissy LeMaire (@cl)

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbatoolsError

    .EXAMPLE
        PS C:\> Get-DbatoolsError

        Returns detailed error information for the most recent dbatools error

    .EXAMPLE
        PS C:\> Get-DbatoolsError -All

        Returns detailed error information for all dbatools-related errors

    .EXAMPLE
        PS C:\> Get-DbatoolsError -Last 1

        Returns the oldest dbatools-related error in the pipeline
    #>
    [CmdletBinding()]
    param (
        [int]$First,
        [int]$Last,
        [int]$Skip,
        [switch]$All
    )
    process {
        if (Test-Bound -Not First, Last, Skip, All) {
            $First = 1
        }

        if ($All) {
            $First = $global:error.Count
        }

        $global:error | Where-Object FullyQualifiedErrorId -match dbatools | Select-Object -First $First -Last $Last -Skip $Skip -Property CategoryInfo, ErrorDetails, Exception, FullyQualifiedErrorId, InvocationInfo, PipelineIterationInfo, PSMessageDetails, ScriptStackTrace, TargetObject
    }
}