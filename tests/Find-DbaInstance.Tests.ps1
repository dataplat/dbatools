$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    Context "Command finds appveyor instances" {
        $results = Find-DbaInstance -ComputerName $env:COMPUTERNAME
        It "finds more than one SQL instance" {
            $results.count -gt 1
        }
        It "finds the SQL2008R2SP2 instance" {
            $results.InstanceName -contains 'SQL2008R2SP2' | Should -Be $true
        }
        It "finds the SQL2016 instance" {
            $results.InstanceName -contains 'SQL2016' | Should -Be $true
        }
        It "finds the SQL2017 instance" {
            $results.InstanceName -contains 'SQL2017' | Should -Be $true
        }
    }
}