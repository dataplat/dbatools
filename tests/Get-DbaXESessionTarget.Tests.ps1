#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaXESessionTarget",
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
                "Session",
                "Target",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Verifying command output" {
        It "returns only the system_health session" {
            $results = Get-DbaXESessionTarget -SqlInstance $TestConfig.InstanceSingle -Target "package0.event_file"
            foreach ($result in $results) {
                $result.Name -eq "package0.event_file" | Should -Be $true
            }
        }

        It "supports the pipeline" {
            $results = Get-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session "system_health" | Get-DbaXESessionTarget -Target "package0.event_file"
            $results.Count -gt 0 | Should -Be $true
        }
    }

    Context "Output validation" {
        BeforeAll {
            $result = Get-DbaXESessionTarget -SqlInstance $TestConfig.InstanceSingle -Session "system_health"
        }

        It "Returns output of the documented type" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.XEvent.Target"
        }

        It "Has the expected default display properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Session",
                "SessionStatus",
                "Name",
                "ID",
                "Field",
                "PackageName",
                "File",
                "Description",
                "ScriptName"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has working alias properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].psobject.Properties["Field"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["Field"].MemberType | Should -Be "AliasProperty"
            $result[0].psobject.Properties["File"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["File"].MemberType | Should -Be "AliasProperty"
        }
    }
}