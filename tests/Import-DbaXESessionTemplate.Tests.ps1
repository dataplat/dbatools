#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
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

    Context "Implementation regression" {
        It "uses XML node selection instead of global string replacement for event_file targets" {
            $commandText = (Get-Command $CommandName).ScriptBlock.ToString()

            $commandText | Should -Match ([regex]::Escape("SelectSingleNode(""/*[local-name()='event_sessions']/*[local-name()='event_session']"")"))
            $commandText | Should -Match ([regex]::Escape("SelectSingleNode(""*[local-name()='target' and @name='event_file']"")"))
            $commandText | Should -Match ([regex]::Escape("SelectSingleNode(""*[local-name()='parameter' and @name='filename']"")"))
            $commandText | Should -Not -Match ([regex]::Escape("Replace("))
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
}