#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-BulkRowsCopiedCount",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Reading the rows copied counter" {
        It "Returns the counter value below Int32.MaxValue" {
            InModuleScope "dbatools" {
                $bulkCopy = New-Object -TypeName Microsoft.Data.SqlClient.SqlBulkCopy -ArgumentList "Server=dummy"
                $rowsCopiedField = [Microsoft.Data.SqlClient.SqlBulkCopy].GetField("_rowsCopied", [Reflection.BindingFlags]"NonPublic,GetField,Instance")
                $rowsCopiedField.SetValue($bulkCopy, [long]100000)

                Get-BulkRowsCopiedCount $bulkCopy | Should -Be 100000
            }
        }

        It "Returns the counter value above Int32.MaxValue" {
            # The field is an Int64 in current Microsoft.Data.SqlClient. A cast to [int] throws above
            # [int32]::MaxValue, the catch then returned -1, and the callers took that for a wrapped
            # counter and inflated the reported total by billions of rows (#10675).
            InModuleScope "dbatools" {
                $bulkCopy = New-Object -TypeName Microsoft.Data.SqlClient.SqlBulkCopy -ArgumentList "Server=dummy"
                $rowsCopiedField = [Microsoft.Data.SqlClient.SqlBulkCopy].GetField("_rowsCopied", [Reflection.BindingFlags]"NonPublic,GetField,Instance")
                $rowsCopiedField.SetValue($bulkCopy, [long]3000000000)

                Get-BulkRowsCopiedCount $bulkCopy | Should -Be 3000000000
            }
        }

        It "Keeps the total of the callers correct above Int32.MaxValue" {
            # The pattern of Copy-DbaDbTableData, Import-DbaCsv and Import-DbaParquet: the running total
            # from the copy notifications, plus the adjustment for the rows after the last notification.
            InModuleScope "dbatools" {
                $bulkCopy = New-Object -TypeName Microsoft.Data.SqlClient.SqlBulkCopy -ArgumentList "Server=dummy"
                $rowsCopiedField = [Microsoft.Data.SqlClient.SqlBulkCopy].GetField("_rowsCopied", [Reflection.BindingFlags]"NonPublic,GetField,Instance")
                $rowsCopiedField.SetValue($bulkCopy, [long]3000000000)

                $totalRowsCopied = [long]2999995000
                $prevRowsCopied = [long]2999995000
                $finalRowCountReported = Get-BulkRowsCopiedCount $bulkCopy
                if ($finalRowCountReported -ge 0) {
                    $totalRowsCopied += (Get-AdjustedTotalRowsCopied -ReportedRowsCopied $finalRowCountReported -PreviousRowsCopied $prevRowsCopied).NewRowCountAdded
                }

                $totalRowsCopied | Should -Be 3000000000
            }
        }
    }
}
