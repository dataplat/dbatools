function Get-DbatoolsError {
    <#
    .SYNOPSIS
        Retrieves detailed error information from failed dbatools commands for troubleshooting

    .DESCRIPTION
        Retrieves detailed error information specifically from dbatools command failures, filtering the PowerShell error collection to show only dbatools-related errors. This provides comprehensive diagnostic details including exception messages, stack traces, and invocation information that help troubleshoot SQL Server connection issues, permission problems, or command syntax errors. By default, it returns only the most recent dbatools error, but can retrieve all historical dbatools errors for pattern analysis or support requests.

    .PARAMETER First
        Specifies the number of most recent dbatools errors to return. Defaults to 1 if no parameters are specified.
        Use this when you need to examine the latest few errors after a batch operation or troubleshooting session.

    .PARAMETER Last
        Specifies the number of oldest dbatools errors to return from the error history.
        Use this when you need to see the earliest errors that occurred during a session or to trace the root cause of cascading failures.

    .PARAMETER Skip
        Specifies the number of most recent dbatools errors to skip before returning results.
        Use this when you want to ignore the latest error and examine previous errors, or when paging through error history.

    .PARAMETER All
        Returns detailed information for all dbatools-related errors in the current PowerShell session.
        Use this when creating support tickets, analyzing error patterns, or performing comprehensive troubleshooting of multiple failed commands.

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