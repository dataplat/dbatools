function Convert-DbaTimelineStatusColor {
    <#
        .SYNOPSIS
            Converts literal string status to a html color

        .DESCRIPTION
            This function acceptes Agent Job status as literal string input and covnerts to html color.
            This is internal function, part of ConvertTo-DbaTimeline

        .PARAMETER Status

            The Status input parameter must be a valid SQL Agent Job status as literal string as defined in MS Books:
                Status of the job execution:
                    Failed
                    Succeeded
                    Retry
                    Canceled
                    In Progress

        .NOTES
            Tags: Internal
            Author: Marcin Gminski (@marcingminski)

            Dependency: None
            Requirements: None

            Website: https://dbatools.io
            Copyright: (c) 2018 by dbatools, licensed under MIT
-           License: MIT https://opensource.org/licenses/MIT

        .LINK
            --internal function, not exposed to end user

        .EXAMPLE
            Convert-DbaTimelineStatusColor ("Succeeded")

            Returned string: #36B300
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $Status
    )
    $out = switch ($Status) {
        "Failed" { "#FF3D3D" }
        "Succeeded" { "#36B300" }
        "Retry" { "#FFFF00" }
        "Canceled" { "#C2C2C2" }
        "In Progress" { "#00CCFF" }
        default { "#FF00CC" }
    }
    return $out
}