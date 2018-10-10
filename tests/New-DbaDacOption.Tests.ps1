$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Unit Tests" -Tag "UnitTests" {
    It "Returns dacpac options" {
        New-DbaDacOption | Should -Not -BeNullOrEmpty
    }
    It "Returns bacpac options" {
        New-DbaDacOption -Type Bacpac | Should -Not -BeNullOrEmpty
    }
}
