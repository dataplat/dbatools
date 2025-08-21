#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaAgentJobOwner",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Job",
                "ExcludeJob",
                "Login",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $saJob = ("dbatoolsci_sa_{0}" -f $(Get-Random))
        $notSaJob = ("dbatoolsci_nonsa_{0}" -f $(Get-Random))
        $null = New-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job $saJob -OwnerLogin 'sa'
        $null = New-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job $notSaJob -OwnerLogin 'NT AUTHORITY\SYSTEM'
    }
    AfterAll {
        $null = Remove-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job $saJob, $notSaJob -Confirm:$false
    }

    Context "Command actually works" {
        It "Should return $notSaJob" {
            $results = Test-DbaAgentJobOwner -SqlInstance $TestConfig.instance2
            $results | Where-Object { $_.Job -eq $notSaJob } | Should -Not -Be Null
        }
    }

    Context "Command works for specific jobs" {
        BeforeAll {
            $results = Test-DbaAgentJobOwner -SqlInstance $TestConfig.instance2 -Job $saJob, $notSaJob
        }
        It "Should find $saJob owner matches default sa" {
            $($results | Where-Object { $_.Job -eq $saJob }).OwnerMatch | Should -Be $True
        }
        It "Should find $notSaJob owner doesn't match default sa" {
            $($results | Where-Object { $_.Job -eq $notSaJob }).OwnerMatch | Should -Be $False
        }
    }

    Context "Exclusions work" {
        It "Should exclude $notSaJob job" {
            $results = Test-DbaAgentJobOwner -SqlInstance $TestConfig.instance2 -ExcludeJob $notSaJob
            $results.job | Should -Not -Match $notSaJob
        }
    }
}