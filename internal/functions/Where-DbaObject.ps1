function global:Where-DbaObject {
    <#
        .SYNOPSIS
            A slightly more efficient filter function than Where-Object.

        .DESCRIPTION
            A slightly more efficient filter function than Where-Object.
            In case multiple filters are set, any one hit will work.

        .PARAMETER InputObject
            The object to process.

        .PARAMETER PropertyName
            Whether a property should be tested, rather than the input object itself.

        .PARAMETER Equals
            Tests for equality.

        .PARAMETER NotEquals
            Tests for inequality.

        .PARAMETER Like
            Tests for similarity.

        .PARAMETER NotLike
            Tests for non-similarity.

        .PARAMETER In
            Tests, whether the input is contained in a specified list.

        .PARAMETER NotIn
            Tests, whether the input is not contained in a specified list.

        .PARAMETER Match
            Tests for regex match.

        .PARAMETER NotMatch
            Tests for regex non-match.

        .EXAMPLE
            dir | Where-DbaObject Length -gt 1024

            Scans the current folder and filters out all files smaller then 1024 bytes

        .EXAMPLE
            "foo","bar" | Where-DbaObject -match "o"

            Filters out all strings that don't contain the letter "o"
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline, Mandatory)]
        [object]
        $InputObject,

        [Parameter(Position = 0)]
        [Alias('Property')]
        [string]
        $PropertyName,

        [Alias('Eq')]
        [object]
        $Equals,

        [Alias('Ne')]
        [object]
        $NotEquals,

        [object]
        $Like,

        [object]
        $NotLike,

        [object]
        $In,

        [object]
        $NotIn,

        [object]
        $Match,

        [object]
        $NotMatch
    )

    begin {
        $TestEquals = Test-Bound -ParameterName Equals
        $TestNotEquals = Test-Bound -ParameterName NotEquals
        $TestLike = Test-Bound -ParameterName Like
        $TestNotLike = Test-Bound -ParameterName NotLike
        $TestIn = Test-Bound -ParameterName In
        $TestNotIn = Test-Bound -ParameterName NotIn
        $TestMatch = Test-Bound -ParameterName Match
        $TestNotMatch = Test-Bound -ParameterName NotMatch

        $TestObject = -not ($TestEquals -or $TestNotEquals -or $TestLike -or $TestNotLike -or $TestIn -or $TestNotIn -or $TestMatch -or $TestNotMatch)

        $TestProperty = Test-Bound -ParameterName PropertyName
    }
    process {
        foreach ($item in $InputObject) {
            #region Test Property
            if ($TestProperty) {
                if ($TestObject -and $item.$PropertyName) { return $item }

                if ($TestEquals -and ($item.$PropertyName -eq $Equals)) { return $item }
                if ($TestNotEquals -and ($item.$PropertyName -ne $NotEquals)) { return $item }
                if ($TestLike -and ($item.$PropertyName -like $Like)) { return $item }
                if ($TestNotLike -and ($item.$PropertyName -notlike $NotLike)) { return $item }
                if ($TestIn -and ($item.$PropertyName -In $In)) { return $item }
                if ($TestNotIn -and ($item.$PropertyName -NotIn $NotIn)) { return $item }
                if ($TestMatch -and ($item.$PropertyName -Match $Match)) { return $item }
                if ($TestNotMatch -and ($item.$PropertyName -NotMatch $NotMatch)) { return $item }
            }
            #endregion Test Property
            #region Test Object
            else {
                if ($TestObject -and $item) { return $item }

                if ($TestEquals -and ($item -eq $Equals)) { return $item }
                if ($TestNotEquals -and ($item -ne $NotEquals)) { return $item }
                if ($TestLike -and ($item -like $Like)) { return $item }
                if ($TestNotLike -and ($item -notlike $NotLike)) { return $item }
                if ($TestIn -and ($item -In $In)) { return $item }
                if ($TestNotIn -and ($item -NotIn $NotIn)) { return $item }
                if ($TestMatch -and ($item -Match $Match)) { return $item }
                if ($TestNotMatch -and ($item -NotMatch $NotMatch)) { return $item }
            }
            #endregion Test Object
        }
    }
    end {

    }
}

(Get-Item Function:\Where-DbaObject).Visibility = "Private"