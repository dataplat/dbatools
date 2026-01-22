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

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaXESessionTarget -SqlInstance $TestConfig.InstanceSingle -Session "system_health" -EnableException
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.XEvent.Target]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Session',
                'SessionStatus',
                'Name',
                'ID',
                'Field',
                'PackageName',
                'File',
                'Description',
                'ScriptName'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has dbatools-added properties" {
            $addedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Session',
                'SessionStatus',
                'TargetFile',
                'RemoteTargetFile'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $addedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be added by dbatools"
            }
        }
    }
}