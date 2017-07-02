## needs some proper tests for the function here
Describe "Get-DbaAgentJobOutputFile Unit Tests" -Tag 'Unittests' {
    Context "Input Validation" {
        It 'SqlServer parameter is empty' {
            { Get-DbaAgentJobOutputFile -SqlInstance '' -WarningAction Stop 3> $null } | Should Throw
        }
        It 'SqlServer parameter host cannot be found' {
            Mock Connect-SqlInstance { throw System.Data.SqlClient.SqlException }
            { Get-DbaAgentJobOutputFile -SqlInstance 'ABC' -WarningAction Stop 3> $null } | Should Throw
        }
    }
}