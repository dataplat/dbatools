function ConvertTo-JsDate {
    <#
        .SYNOPSIS
            Converts Datetime input to a Java Script date format

        .DESCRIPTION
            This function acceptes date time input and converts to a Java script compatible format.
            Java Script date time format:
                New date (yyyy, MM, dd, HH, mm, ss)

            This is internal function part of ConvertTo-DbaTimeline

        .PARAMETER InputDate

            The InputDate parameter must be a valid datetime type

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
            ConvertTo-JsDate (Get-Date)

            Returned output: new Date(2018, 7, 14, 07, 40, 42)
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [datetime]
        $InputDate
    )
    [string]$out = "new Date($(Get-Date $InputDate -format "yyyy"), $($(Get-Date $InputDate -format "MM")-1), $(Get-Date $InputDate -format "dd"), $(Get-Date $InputDate -format "HH"), $(Get-Date $InputDate -format "mm"), $(Get-Date $InputDate -format "ss"))"
    return $out
}