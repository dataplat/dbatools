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

    Context "Import Error Reported template" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $sessionName = "dbatoolsci_Error_Reported_$(Get-Random)"
            $session = Import-DbaXESessionTemplate -SqlInstance $TestConfig.InstanceSingle -Template "Error Reported" -Name $sessionName
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Get-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session $sessionName | Remove-DbaXESession -Confirm:$false -ErrorAction SilentlyContinue
        }

        It "should import the session successfully" {
            $session | Should -Not -BeNullOrEmpty
        }

        It "should create a session with the correct name" {
            $session.Name | Should -Be $sessionName
        }

        It "should have the error_reported event" {
            $session.Events.Name | Should -Contain "error_reported"
        }
    }
}