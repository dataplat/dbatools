#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaRandomizedValue",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "DataType",
                "RandomizerType",
                "RandomizerSubType",
                "Min",
                "Max",
                "Precision",
                "CharacterString",
                "Format",
                "Separator",
                "Symbol",
                "Locale",
                "Value",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command returns values" {
        It "Should return a String type" {
            $result = Get-DbaRandomizedValue -DataType varchar

            $result.GetType().Name | Should -Be "String"
        }

        It "Should return random string of max length 255" {
            $result = Get-DbaRandomizedValue -DataType varchar

            $result.Length | Should -BeGreaterThan 1
        }

        It "Should return a random address zipcode" {
            # This used to be skipped on AppVeyor, where it failed with "[Bogus.DataSets.Name] does not contain
            # a method named 'ZipCode'". That was the module scoped cache below, not the CI.

            $result = Get-DbaRandomizedValue -RandomizerType Address -RandomizerSubType Zipcode -Format "#####"

            $result.Length | Should -Be 5
        }
    }

    Context "Resolving the type from the subtype" {
        It "Uses the type of the subtype that was passed in, not the one from the first call" {
            # The type resolved for a subtype used to be cached in the module scope, so the first subtype used
            # in a session decided the type for every later call and asked, for example, the Name data set for
            # a zip code. The order of these three calls is what makes the test meaningful.
            $resolvedFirstName = Get-DbaRandomizedValue -RandomizerSubType FirstName
            $resolvedZipCode = Get-DbaRandomizedValue -RandomizerSubType ZipCode
            $resolvedEmail = Get-DbaRandomizedValue -RandomizerSubType Email

            $resolvedFirstName | Should -Not -BeNullOrEmpty
            $resolvedZipCode | Should -Not -BeNullOrEmpty
            $resolvedEmail | Should -BeLike "*@*"
        }
    }

    Context "Every randomizer type" {
        BeforeAll {
            # A type with no branch in the command returned $null without a word, and one that needs an
            # argument the command does not pass failed with a raw .NET overload error. Both are useless to
            # whoever wrote the config. Every type has to answer with a value or with a message that says
            # what is missing.
            $typeResults = @{ }

            foreach ($randomizerType in (Get-DbaRandomizedType)) {
                $typeKey = "$($randomizerType.Type)/$($randomizerType.SubType)"

                # Stop-Function -Continue from the begin block skips the rest of this iteration, so this entry
                # is written first and only overwritten when the call comes back. Landing on it means a message
                # was given. A Stop-Function inside the switch is swallowed by the switch instead, and those
                # calls do come back, so the warning is checked as well.
                $typeResults[$typeKey] = "message"
                $typeWarning = $null

                $splatRandomValue = @{
                    RandomizerType    = $randomizerType.Type
                    RandomizerSubType = $randomizerType.SubType
                    WarningVariable   = "typeWarning"
                    WarningAction     = "SilentlyContinue"
                    ErrorAction       = "SilentlyContinue"
                }
                $typeValue = Get-DbaRandomizedValue @splatRandomValue

                if ($typeValue) {
                    $typeResults[$typeKey] = "value"
                } elseif ($typeWarning) {
                    $typeResults[$typeKey] = "message"
                } else {
                    $typeResults[$typeKey] = "silent"
                }
            }

            $silentTypes = $typeResults.Keys | Where-Object { $typeResults[$PSItem] -eq "silent" } | Sort-Object
            $valueTypes = $typeResults.Keys | Where-Object { $typeResults[$PSItem] -eq "value" }
        }

        It "Never returns nothing without saying why" {
            $silentTypes | Should -BeNullOrEmpty
        }

        It "Generates a value for the vast majority of types without further parameters" {
            # Guards against the test above passing because everything started failing with a message.
            $valueTypes.Count | Should -BeGreaterThan 170
        }
    }
}