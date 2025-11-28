$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag "UnitTests" {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = @(
                "SqlInstance",
                "SqlCredential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $instance = $TestConfig.instance2
    }

    Context "Certificate retrieval" {
        It "Should retrieve certificate information from the instance" {
            $result = Get-DbaNetworkEncryption -SqlInstance $instance
            $result | Should -Not -BeNullOrEmpty
            $result.SqlInstance | Should -Be $instance
        }

        It "Should return certificate with expected properties" {
            $result = Get-DbaNetworkEncryption -SqlInstance $instance
            $result.Subject | Should -Not -BeNullOrEmpty
            $result.Thumbprint | Should -Not -BeNullOrEmpty
            $result.NotBefore | Should -BeOfType [DateTime]
            $result.NotAfter | Should -BeOfType [DateTime]
            $result.Expires | Should -BeOfType [DateTime]
        }

        It "Should work with pipeline input" {
            $result = $instance | Get-DbaNetworkEncryption
            $result | Should -Not -BeNullOrEmpty
            $result.SqlInstance | Should -Be $instance
        }
    }

    Context "Multiple instances" {
        It "Should retrieve certificates from multiple instances" {
            $instances = @($TestConfig.instance2, $TestConfig.instance3)
            $results = Get-DbaNetworkEncryption -SqlInstance $instances
            $results.Count | Should -Be 2
        }
    }
}
