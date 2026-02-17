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
            $results = Get-DbaXESessionTarget -SqlInstance $TestConfig.InstanceSingle -Target "package0.event_file" -OutVariable "global:dbatoolsciOutput"
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
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.XEvent.Target]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
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
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.XEvent\.Target"
        }
    }
}