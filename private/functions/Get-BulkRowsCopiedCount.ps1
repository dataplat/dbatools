function Get-BulkRowsCopiedCount {
    <#
        .SYNOPSIS
            Gets the number of rows returned by a sql bulk copy

        .DESCRIPTION
            Uses reflection to return the _rowsCopied private field value from a SqlBulkCopy object
            see http://stackoverflow.com/questions/1188384/sqlbulkcopy-row-count-when-complete

        .PARAMETER BulkCopy
            The Bulk copy object to retrieve the rows copied field from

            This is internal function is used by
            - Copy-DbaDbTableData
            - Copy-DbaDbViewData
            - Import-DbaCsv
            - Import-DbaParquet

        .EXAMPLE
            Get-BulkRowsCopied $bulkObject

            Returns a integer containing the number of rows copied by SqlBulkCopy

        .NOTES
        Author: Jason Chester (@jasonchester)

        dbatools PowerShell module (https://dbatools.io)
        Copyright: (c) 2020 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT
    #>
    [OutputType([long])]
    param (
        [Microsoft.Data.SqlClient.SqlBulkCopy] $BulkCopy
    )
    $BindingFlags = [Reflection.BindingFlags] "NonPublic,GetField,Instance"
    $rowsCopiedField = [Microsoft.Data.SqlClient.SqlBulkCopy].GetField("_rowsCopied", $BindingFlags)
    try {
        # The field is an Int64 in current Microsoft.Data.SqlClient (an Int32 in the legacy library),
        # so it must not be narrowed to [int]: above [int32]::MaxValue rows that cast throws, and the
        # -1 then taken for the row count inflates the reported total by billions of rows (see #10675).
        return [long]$rowsCopiedField.GetValue($BulkCopy)
    } catch {
        return -1;
    }
}
