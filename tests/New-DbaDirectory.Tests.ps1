#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaDirectory",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Path",
                "SqlCredential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $randomPath = "C:\temp\dbatools_test_$(Get-Random)"
            $result = New-DbaDirectory -SqlInstance $TestConfig.instance1 -Path $randomPath -EnableException
        }

        AfterAll {
            if (Test-DbaPath -SqlInstance $TestConfig.instance1 -Path $randomPath) {
                $null = Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Query "EXEC master.dbo.xp_cmdshell 'rmdir `"$randomPath`"'" -EnableException
            }
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                "Server",
                "Path",
                "Created"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Created property is a boolean" {
            $result.Created | Should -BeOfType [bool]
        }

        It "Path property matches input" {
            $result.Path | Should -Be $randomPath
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>