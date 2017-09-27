$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1","")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Unit Tests" -Tag 'UnitTests' {
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