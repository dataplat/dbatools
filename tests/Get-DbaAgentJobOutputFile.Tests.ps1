## needs some proper tests for the function here
Describe "$Name Tests" -Tag @('Command') {
    Context "Input Validation" {
        It 'SqlServer parameter is empty' {
            { Get-DbaJobOutputFile -SqlServer '' -WarningAction Stop 3> $null } | Should Throw
        }
        It 'SqlServer parameter host cannot be found' {
            Mock Connect-SqlServer { throw System.Data.SqlClient.SqlException }
            { Get-DbaJobOutputFile -SqlServer 'ABC' -WarningAction Stop 3> $null } | Should Throw
        }
    }
}