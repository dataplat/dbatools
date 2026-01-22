#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Read-DbaXEFile",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Path",
                "Raw",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Get the system_health session for testing
        $xeSession = Get-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session system_health

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Verifying command output" {
        It "returns some results with Raw parameter" {
            $results = $xeSession | Read-DbaXEFile -Raw
            $results | Should -Not -BeNullOrEmpty
        }

        It "returns some results without Raw parameter" {
            $results = $xeSession | Read-DbaXEFile
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = $xeSession | Read-DbaXEFile -EnableException | Select-Object -First 1
        }

        It "Returns PSCustomObject by default" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected standard properties" {
            $expectedProps = @(
                'name',
                'timestamp'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has dynamic properties from XEvent fields and actions" {
            # The result should have more properties than just name and timestamp
            $result.PSObject.Properties.Name.Count | Should -BeGreaterThan 2
        }
    }

    Context "Output with -Raw" {
        BeforeAll {
            $result = $xeSession | Read-DbaXEFile -Raw -EnableException | Select-Object -First 1
        }

        It "Returns Microsoft.SqlServer.XEvent.XELite.XEvent when -Raw specified" {
            $result | Should -BeOfType [Microsoft.SqlServer.XEvent.XELite.XEvent]
        }

        It "Has native XEvent properties" {
            $result.Name | Should -Not -BeNullOrEmpty
            $result.Timestamp | Should -Not -BeNullOrEmpty
        }
    }
}