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

        .EXAMPLE
            Get-BulkRowsCopied $bulkObject

            Returns a integer containing the number of rows copied by SqlBulkCopy

        .NOTES
        Author: Jason Chester (@jasonchester)

        dbatools PowerShell module (https://dbatools.io)
        Copyright: (c) 2020 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT
    #>
    [OutputType([int])]
    param (
        [System.Data.SqlClient.SqlBulkCopy] $BulkCopy
    )
    $BindingFlags = [Reflection.BindingFlags] "NonPublic,GetField,Instance"
    $rowsCopiedField = [System.Data.SqlClient.SqlBulkCopy].GetField("_rowsCopied", $BindingFlags)
    try {
        return [int]$rowsCopiedField.GetValue($BulkCopy)
    } catch {
        return -1;
    }
}
