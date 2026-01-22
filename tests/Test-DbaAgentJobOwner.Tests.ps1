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
        $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $saJob -OwnerLogin 'sa'
        $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $notSaJob -OwnerLogin 'NT AUTHORITY\SYSTEM'
    }
    AfterAll {
        $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $saJob, $notSaJob
    }

    Context "Command actually works" {
        It "Should return $notSaJob" {
            $results = Test-DbaAgentJobOwner -SqlInstance $TestConfig.InstanceSingle
            $results | Where-Object { $_.Job -eq $notSaJob } | Should -Not -Be Null
        }
    }

    Context "Command works for specific jobs" {
        BeforeAll {
            $results = Test-DbaAgentJobOwner -SqlInstance $TestConfig.InstanceSingle -Job $saJob, $notSaJob
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
            $results = Test-DbaAgentJobOwner -SqlInstance $TestConfig.InstanceSingle -ExcludeJob $notSaJob
            $results.job | Should -Not -Match $notSaJob
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Test-DbaAgentJobOwner -SqlInstance $TestConfig.InstanceSingle -Job $saJob, $notSaJob -EnableException
        }

        It "Returns PSCustomObject" {
            $result[0].PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                "Server",
                "Job",
                "JobType",
                "CurrentOwner",
                "TargetOwner",
                "OwnerMatch"
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }
}