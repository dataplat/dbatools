#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Restart-DbaService",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Type",
                "InputObject",
                "Timeout",
                "Credential",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command actually works" {
        BeforeAll {
            $instanceName = (Connect-DbaInstance -SqlInstance $TestConfig.InstanceRestart).ServiceName
        }

        It "restarts some services" {
            $services = Restart-DbaService -ComputerName $TestConfig.InstanceRestart -InstanceName $instanceName -Type Agent
            $services | Should -Not -BeNullOrEmpty
            foreach ($service in $services) {
                $service.State | Should -Be "Running"
                $service.Status | Should -Be "Successful"
            }
        }

        It "restarts some services through pipeline" {
            $services = Get-DbaService -ComputerName $TestConfig.InstanceRestart -InstanceName $instanceName -Type Agent, Engine | Restart-DbaService
            $services | Should -Not -BeNullOrEmpty
            foreach ($service in $services) {
                $service.State | Should -Be "Running"
                $service.Status | Should -Be "Successful"
            }
        }
    }

    Context "Output validation" {
        BeforeAll {
            $restartAvailable = $false
            try {
                $connRestart = Connect-DbaInstance -SqlInstance $TestConfig.InstanceRestart -ErrorAction Stop
                $restartInstanceName = $connRestart.ServiceName
                $restartAvailable = $true
            } catch {
                $restartAvailable = $false
            }
            if ($restartAvailable) {
                $result = Restart-DbaService -ComputerName $TestConfig.InstanceRestart -InstanceName $restartInstanceName -Type Agent
            }
        }

        It "Returns output of the expected type" {
            if (-not $restartAvailable) { Set-ItResult -Skipped -Because "InstanceRestart is not available" }
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].psobject.TypeNames | Should -Contain "dbatools.DbaSqlService"
        }

        It "Has the expected default display properties" {
            if (-not $restartAvailable) { Set-ItResult -Skipped -Because "InstanceRestart is not available" }
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "ServiceName",
                "InstanceName",
                "ServiceType",
                "State",
                "Status",
                "Message"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}