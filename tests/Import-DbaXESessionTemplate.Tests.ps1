#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Import-DbaXESessionTemplate",
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
                "Name",
                "Path",
                "Template",
                "TargetFilePath",
                "TargetFileMetadataPath",
                "StartUpState",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

# TODO: We are testing the wrong command here
Describe $CommandName -Tag IntegrationTests {
    Context "Get Template Index" {
        It "returns good results with no missing information" {
            $results = Get-DbaXESessionTemplate
            $results | Where-Object Name -eq $null | Should -BeNullOrEmpty
            $results | Where-Object TemplateName -eq $null | Should -BeNullOrEmpty
            $results | Where-Object Description -eq $null | Should -BeNullOrEmpty
            $results | Where-Object Category -eq $null | Should -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        BeforeAll {
            $xeSessionName = "dbatoolsci_output_$(Get-Random)"
            # Remove session if it exists already
            $existingSession = Get-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session $xeSessionName -ErrorAction SilentlyContinue
            if ($existingSession) {
                $existingSession | Remove-DbaXESession -ErrorAction SilentlyContinue
            }
            $outputResult = Import-DbaXESessionTemplate -SqlInstance $TestConfig.InstanceSingle -Template "Blocked Process Report" -Name $xeSessionName
        }

        AfterAll {
            $sessionToRemove = Get-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session $xeSessionName -ErrorAction SilentlyContinue
            if ($sessionToRemove) {
                $sessionToRemove | Remove-DbaXESession -ErrorAction SilentlyContinue
            }
        }

        It "Returns output of the documented type" {
            $outputResult | Should -Not -BeNullOrEmpty
            $outputResult[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.XEvent.Session"
        }

        It "Has the expected default display properties" {
            $outputResult | Should -Not -BeNullOrEmpty
            $defaultProps = $outputResult[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("ComputerName", "InstanceName", "SqlInstance", "Name", "Status", "StartTime", "AutoStart", "State", "Targets", "TargetFile", "Events", "MaxMemory", "MaxEventSize")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}