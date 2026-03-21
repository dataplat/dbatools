#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaInstanceProperty",
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
                "InstanceProperty",
                "ExcludeInstanceProperty",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command actually works" {
        BeforeAll {
            $results = Get-DbaInstanceProperty -SqlInstance $TestConfig.InstanceMulti2
        }

        It "Should have correct properties" {
            $ExpectedProps = "ComputerName", "InstanceName", "PropertyType", "SqlInstance"
            (($results | Get-Member -MemberType NoteProperty).name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }

        It "Should return that returns a valid build" {
            $(Get-DbaBuild -Build ($results | Where-Object Name -eq "ResourceVersionString").Value).MatchType | Should -Be "Exact"
        }

        It "Should have DisableDefaultConstraintCheck set false" {
            ($results | Where-Object Name -eq "DisableDefaultConstraintCheck").Value | Should -Be $False
        }

        It "Should get the correct DefaultFile location" {
            $defaultFiles = Get-DbaDefaultPath -SqlInstance $TestConfig.InstanceMulti2
            ($results | Where-Object Name -eq "DefaultFile").Value | Should -BeLike "$($defaultFiles.Data)*"
        }
    }

    Context "Property filters work" {
        BeforeAll {
            $resultInclude = Get-DbaInstanceProperty -SqlInstance $TestConfig.InstanceMulti2 -InstanceProperty DefaultFile
            $resultExclude = Get-DbaInstanceProperty -SqlInstance $TestConfig.InstanceMulti2 -ExcludeInstanceProperty DefaultFile
        }

        It "Should only return DefaultFile property" {
            $resultInclude.Name | Should -Contain "DefaultFile"
        }

        It "Should not contain DefaultFile property" {
            $resultExclude.Name | Should -Not -Contain ([regex]::Escape("DefaultFile"))
        }
    }

    Context "Command can handle multiple instances" {
        It "Should have results for 2 instances" {
            $(Get-DbaInstanceProperty -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 | Select-Object -Unique SqlInstance).count | Should -Be 2
        }
    }
}