function Format-TestFailures {
    <#
    .SYNOPSIS
        Formats test failure output for display.

    .DESCRIPTION
        Provides a consistent, readable format for displaying test failure information.

    .PARAMETER Failure
        The failure object to format (accepts pipeline input).

    .NOTES
        Tags: Testing, Formatting, Display
        Author: dbatools team
    #>
    [CmdletBinding()]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingWriteHost', '',
        Justification = 'Intentional: command renders formatted output for user display.'
    )]
    param([Parameter(ValueFromPipeline)]$Failure)

    process {
        Write-Host "`nPR #$($Failure.PRNumber) - $($Failure.JobName)" -ForegroundColor Cyan
        Write-Host "  Test: $($Failure.TestName)" -ForegroundColor Yellow
        Write-Host "  File: $($Failure.TestFile)" -ForegroundColor Gray
        if ($Failure.ErrorMessage) {
            Write-Host "  Error: $($Failure.ErrorMessage.Split("`n")[0])" -ForegroundColor Red
        }
    }
}