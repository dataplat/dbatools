function Get-FilestreamReturnValue {
    <#
        .SYNOPSIS
            Translates the return value of the SQL WMI EnableFilestream method into a result object.

        .DESCRIPTION
            The FilestreamSettings WMI class reports the outcome of EnableFilestream through a
            numeric return value. This maps that number onto the documented meaning and says which
            of three categories it falls into, so a caller can tell a refusal from a success
            instead of having to match on message text.

            Codes that are in neither list are reported as Unknown together with the raw value.
            Guessing in either direction is what made the original version of this misleading: a
            caller that assumes success ignores a refusal, and one that assumes failure invents an
            error the provider never reported.

        .PARAMETER Value
            The ReturnValue the EnableFilestream method produced.

        .NOTES
            Author: the dbatools team + Claude
    #>
    [CmdletBinding()]
    param (
        [object]$Value
    )

    if ($null -eq $Value) {
        return [PSCustomObject]@{
            ReturnValue = $null
            Category    = "Unknown"
            Message     = "The EnableFilestream method returned no value"
        }
    }

    # The provider signals success with 0 or one of these two codes. Everything named in the
    # switch below is a documented refusal.
    $successCodes = 2147021885, 2147945411, 0

    # An assignment inside a switch clause produces no output, so $message collects only the
    # strings while the category rides along as a side effect. The default is Failure because
    # every literal clause below is a documented failure.
    $category = "Failure"

    $message = switch ($Value) {
        2147217396 {
            "Filestream not supported on instance"
        }
        2147217386 {
            "Filestream cannot change share"
        }
        2147024713 {
            "Duplicate sharename"
        }
        2147024891 {
            "Access denied"
        }
        2147023681 {
            "Invalid sharename"
        }
        2147024690 {
            "Sharename too long"
        }
        2147019889 {
            "Primary node not enabled "
        }
        2147019848 {
            "Sharename node mismatch"
        }
        214721740 {
            "General error"
        }
        { $PSItem -in $successCodes } {
            $category = "Success"
            "The requested operation is successful. Changes will not be effective until the service is restarted."
        }
        default {
            $category = "Unknown"
            "The EnableFilestream method returned an unrecognized value: $Value"
        }
    }

    [PSCustomObject]@{
        ReturnValue = $Value
        Category    = $category
        Message     = $message
    }
}
