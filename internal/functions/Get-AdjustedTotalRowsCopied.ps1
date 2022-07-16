function Get-AdjustedTotalRowsCopied {
    <#
    .SYNOPSIS
        The legacy bulk copy library still uses a 4 byte integer to track the number of rows copied. That 4 byte integer is subject to overflow/wraparound
        if the number of rows copied is greater than an integer can support. The SqlRowsCopiedEventArgs.RowsCopied property is defined as an Int64
        but a 4 byte integer is used in the underlying legacy library. See https://github.com/dataplat/dbatools/issues/6927 for more details.

    .DESCRIPTION
        Determines the accurate total rows copied even if the bulkcopy.RowsCopied has experienced integer wrap.
        This internal function is used from:

        Copy-DbaDbTableData.ps1
        Import-DbaCsv.ps1
        Write-DbaDbTableData.ps1

    .PARAMETER ReportedRowsCopied
        The number of rows copied as reported by the bulk copy library (i.e. https://docs.microsoft.com/en-us/dotnet/api/system.data.sqlclient.sqlrowscopiedeventargs.rowscopied)

    .PARAMETER PreviousRowsCopied
        The previous number of rows reported by the bulk copy library.

    .NOTES
        Tags: Import
        Author: Adam Lancaster, github.com/lancasteradam

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT
    #>
    [CmdletBinding()]
    param (
        $ReportedRowsCopied,
        $PreviousRowsCopied
    )

    $newRowCountAdded = 0

    if ($ReportedRowsCopied -gt 0) {
        if ($PreviousRowsCopied -ge 0) {
            $newRowCountAdded = $ReportedRowsCopied - $PreviousRowsCopied
        } else {
            # integer wrap just changed from negative to positive
            $newRowCountAdded = [math]::Abs($PreviousRowsCopied) + $ReportedRowsCopied
        }
    } elseif ($ReportedRowsCopied -lt 0) {
        if ($PreviousRowsCopied -ge 0) {
            # integer wrap just changed from positive to negative
            $newRowCountAdded = ([int32]::MaxValue - $PreviousRowsCopied) + [math]::Abs(([int32]::MinValue - ($ReportedRowsCopied))) + 1
        } else {
            $newRowCountAdded = [math]::Abs($PreviousRowsCopied) - [math]::Abs($ReportedRowsCopied)
        }
    }

    [pscustomobject]@{
        NewRowCountAdded = $newRowCountAdded
    }
}