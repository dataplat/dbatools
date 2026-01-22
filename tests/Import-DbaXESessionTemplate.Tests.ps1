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

    Context "Output Validation" {
        BeforeAll {
            $templateName = "Blocking Process Report"
            $sessionName = "dbatoolsci_test_session_$(Get-Random)"
            $result = Import-DbaXESessionTemplate -SqlInstance $TestConfig.instance1 -Template $templateName -Name $sessionName -EnableException
        }

        AfterAll {
            if ($result) {
                Get-DbaXESession -SqlInstance $TestConfig.instance1 -Session $sessionName | Remove-DbaXESession -Confirm:$false
            }
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.XEvent.Session]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Name',
                'Status',
                'StartTime',
                'AutoStart',
                'State',
                'Targets',
                'TargetFile',
                'Events',
                'MaxMemory',
                'MaxEventSize'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Returns session with correct name" {
            $result.Name | Should -Be $sessionName
        }

        It "Has ComputerName, InstanceName, and SqlInstance properties added by dbatools" {
            $result.ComputerName | Should -Not -BeNullOrEmpty
            $result.InstanceName | Should -Not -BeNullOrEmpty
            $result.SqlInstance | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output with -StartUpState On" {
        BeforeAll {
            $templateName = "Blocking Process Report"
            $sessionName = "dbatoolsci_test_session_autostart_$(Get-Random)"
            $result = Import-DbaXESessionTemplate -SqlInstance $TestConfig.instance1 -Template $templateName -Name $sessionName -StartUpState On -EnableException
        }

        AfterAll {
            if ($result) {
                Get-DbaXESession -SqlInstance $TestConfig.instance1 -Session $sessionName | Stop-DbaXESession | Remove-DbaXESession -Confirm:$false
            }
        }

        It "Returns session with AutoStart enabled" {
            $result.AutoStart | Should -Be $true
        }

        It "Returns session with Status of Running" {
            $result.Status | Should -Be "Running"
        }

        It "Returns session with StartTime populated" {
            $result.StartTime | Should -Not -BeNullOrEmpty
        }
    }
}