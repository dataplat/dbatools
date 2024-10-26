#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe "Copy-DbaXESessionTemplate" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Copy-DbaXESessionTemplate
            $expected = $TestConfig.CommonParameters
            $expected += @(
                "Path",
                "Destination",
                "EnableException"
            )
        }

        It "Has parameter: <_>" -ForEach $expected {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters ($($expected.Count))" {
            $hasparms = $command.Parameters.Values.Name
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasparms | Should -BeNullOrEmpty
        }
    }
}

Describe "Copy-DbaXESessionTemplate" -Tag "IntegrationTests" {
    Context "When copying XE session templates" {
        It "Successfully copies the template files" {
            $null = Copy-DbaXESessionTemplate *>1
            $source = ((Get-DbaXESessionTemplate | Where-Object Source -ne Microsoft).Path | Select-Object -First 1).Name
            Get-ChildItem "$home\Documents\SQL Server Management Studio\Templates\XEventTemplates" | Where-Object Name -eq $source | Should -Not -BeNullOrEmpty
        }
    }
}