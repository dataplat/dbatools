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
            $results = Test-DbaAgentJobOwner -SqlInstance $TestConfig.InstanceSingle -Job $saJob, $notSaJob -OutVariable "global:dbatoolsciOutput"
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

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "Server",
                "Job",
                "JobType",
                "CurrentOwner",
                "TargetOwner",
                "OwnerMatch"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "Server",
                "Job",
                "JobType",
                "CurrentOwner",
                "TargetOwner",
                "OwnerMatch"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}