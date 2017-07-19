Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
## needs some proper tests for the function here
Describe "Get-DbaAgentJobOutputFile Unit Tests" -Tag 'Unittests' {
    Context "Input Validation" {
		It 'SqlInstance parameter is empty' {
            { Get-DbaAgentJobOutputFile -SqlInstance '' -WarningAction Stop 3> $null } | Should Throw
		}
		<#
		This takes 15 seconds to timeout for not much reward
		It 'SqlInstance parameter host cannot be found' {
            Mock Connect-SqlInstance { throw System.Data.SqlClient.SqlException }
            { Get-DbaAgentJobOutputFile -SqlInstance 'ABC' -WarningAction Stop 3> $null } | Should Throw
        }
		#>
    }
}