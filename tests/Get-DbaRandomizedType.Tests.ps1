#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaRandomizedType",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "RandomizedType",
                "RandomizedSubType",
                "Pattern",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command returns types" {
        BeforeAll {
            $allTypes = Get-DbaRandomizedType
            $zipcodeResult = Get-DbaRandomizedType -RandomizedSubType Zipcode
            $namePatternTypes = Get-DbaRandomizedType -Pattern Name
        }

        It "Should have at least 191 rows" {
            $allTypes.Count | Should -BeGreaterOrEqual 191
        }

        It "Should return correct type based on subtype" {
            $zipcodeResult.Type | Should -Be "Address"
        }

        It "Should return values based on pattern" {
            $namePatternTypes.Count | Should -BeGreaterOrEqual 22
        }
    }

    Context "Every type is backed by Bogus" {
        BeforeAll {
            # The types are a static list, so they drift apart from Bogus whenever a dbatools.library bump
            # brings a version that removed something. A type that Bogus no longer has is accepted by
            # Test-DbaDbDataMaskingConfig and Test-DbaDbDataGeneratorConfig and then generates nothing at all,
            # so we check the list against the library instead of waiting for a user to hit it.
            $faker = New-Object Bogus.Faker("en")

            # Static is not a Bogus data set. It is the marker for a composite item with a fixed value.
            $missingFromBogus = foreach ($randomizerType in (Get-DbaRandomizedType | Where-Object Type -ne Static)) {
                $dataSet = $faker.$($randomizerType.Type)
                if ($null -eq $dataSet -or -not ($dataSet | Get-Member -Name $randomizerType.SubType)) {
                    "$($randomizerType.Type)/$($randomizerType.SubType)"
                }
            }
        }

        It "Has no type or subtype that Bogus removed" {
            $missingFromBogus | Should -BeNullOrEmpty
        }
    }
}