$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 10
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Find-DbaInstance).Parameters.Keys
        $knownParameters = 'ComputerName', 'DiscoveryType', 'Credential', 'SqlCredential', 'ScanType', 'IpAddress', 'DomainController', 'TCPPort', 'MinimumConfidence', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
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