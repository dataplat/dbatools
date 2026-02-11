#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaDiskAllocation",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "NoSqlCheck",
                "SqlCredential",
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command actually works" {
        It "Should return a result" {
            $results = Test-DbaDiskAllocation -ComputerName $TestConfig.InstanceSingle
            $results | Should -Not -Be $null
        }

        It "Should return a result not using sql" {
            $results = Test-DbaDiskAllocation -NoSqlCheck -ComputerName $TestConfig.InstanceSingle
            $results | Should -Not -Be $null
        }
    }

    Context "Output validation" {
        BeforeAll {
            $outputResult = Test-DbaDiskAllocation -ComputerName $TestConfig.InstanceSingle
        }

        It "Returns output of the expected type" {
            $outputResult | Should -Not -BeNullOrEmpty
            $outputResult[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected default display properties" {
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $outputResult[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("ComputerName", "DiskName", "DiskLabel", "BlockSize", "IsSqlDisk", "IsBestPractice")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has working alias properties for backwards compatibility" {
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $outputResult[0].PSObject.Properties["Server"] | Should -Not -BeNullOrEmpty
            $outputResult[0].PSObject.Properties["Server"].MemberType | Should -Be "AliasProperty"
            $outputResult[0].PSObject.Properties["Name"] | Should -Not -BeNullOrEmpty
            $outputResult[0].PSObject.Properties["Name"].MemberType | Should -Be "AliasProperty"
            $outputResult[0].PSObject.Properties["Label"] | Should -Not -BeNullOrEmpty
            $outputResult[0].PSObject.Properties["Label"].MemberType | Should -Be "AliasProperty"
        }
    }
}