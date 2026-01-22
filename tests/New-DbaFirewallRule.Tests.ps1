#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaFirewallRule",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Credential",
                "Type",
                "RuleType",
                "Configuration",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Output Validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Remove-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle
            $result = New-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle -EnableException
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Remove-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns PSCustomObject" {
            $result[0].PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "DisplayName",
                "Type",
                "Successful",
                "Status",
                "Protocol",
                "LocalPort",
                "Program"
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has additional properties available" {
            $result[0].PSObject.Properties.Name | Should -Contain "Name"
            $result[0].PSObject.Properties.Name | Should -Contain "RuleConfig"
            $result[0].PSObject.Properties.Name | Should -Contain "Details"
        }

        It "Details property contains expected sub-properties" {
            $details = $result[0].Details
            $details.PSObject.Properties.Name | Should -Contain "Successful"
            $details.PSObject.Properties.Name | Should -Contain "CimInstance"
        }
    }

    Context "RuleType Program (default - executable-based rules)" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Remove-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle

            # Create firewall rules with default RuleType (Program)
            $resultsNew = New-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle
            $resultsGet = Get-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle
            $resultsRemoveBrowser = $resultsGet | Where-Object Type -eq "Browser" | Remove-DbaFirewallRule
            $resultsRemove = Remove-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle -Type AllInstance

            $instanceName = ([DbaInstanceParameter]$TestConfig.InstanceSingle).InstanceName

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Remove-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "creates at least two firewall rules" {
            $resultsNew.Count | Should -BeGreaterOrEqual 2
        }

        It "creates first firewall rule for SQL Server instance" {
            $resultsNew[0].Successful | Should -Be $true
            $resultsNew[0].Type | Should -Be "Engine"
            $resultsNew[0].DisplayName | Should -Be "SQL Server instance $instanceName"
            $resultsNew[0].Status | Should -Be "The rule was successfully created."
        }

        It "creates second firewall rule for SQL Server Browser" {
            $resultsNew[1].Successful | Should -Be $true
            $resultsNew[1].Type | Should -Be "Browser"
            $resultsNew[1].DisplayName | Should -Be "SQL Server Browser"
            $resultsNew[1].Status | Should -Be "The rule was successfully created."
        }

        It "returns at least two firewall rules" {
            $resultsGet.Count | Should -BeGreaterOrEqual 2
        }

        It "returns firewall rule for SQL Server instance with Program" {
            $resultInstance = $resultsGet | Where-Object Type -eq "Engine"
            $resultInstance.Protocol | Should -Be "TCP"
            $resultInstance.Program | Should -BeLike "*sqlservr.exe"
        }

        It "returns firewall rule for SQL Server Browser with Program" {
            $resultBrowser = $resultsGet | Where-Object Type -eq "Browser"
            # Browser in Program mode should have Protocol = Any and Program path
            if ($resultBrowser.Program) {
                $resultBrowser.Program | Should -BeLike "*sqlbrowser.exe"
                $resultBrowser.Protocol | Should -Be "Any"
            } else {
                # Fallback to port-based if Program couldn't be determined
                $resultBrowser.Protocol | Should -Be "UDP"
                $resultBrowser.LocalPort | Should -Be "1434"
            }
        }

        It "removes firewall rule for Browser" {
            $resultsRemoveBrowser.Type | Should -Be "Browser"
            $resultsRemoveBrowser.IsRemoved | Should -Be $true
            $resultsRemoveBrowser.Status | Should -Be "The rule was successfully removed."
        }

        It "removes other firewall rules" {
            $resultsRemove.Type | Should -Contain "Engine"
            $resultsRemove.IsRemoved | Should -Contain $true
            $resultsRemove.Status | Should -Contain "The rule was successfully removed."
        }
    }

    Context "RuleType Port (traditional port-based rules)" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Remove-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle

            # Create firewall rules with RuleType Port
            $resultsNewPort = New-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle -RuleType Port
            $resultsGetPort = Get-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle
            $resultsRemovePort = Remove-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle -Type AllInstance

            $instanceName = ([DbaInstanceParameter]$TestConfig.InstanceSingle).InstanceName

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Remove-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "creates at least two firewall rules" {
            $resultsNewPort.Count | Should -BeGreaterOrEqual 2
        }

        It "creates first firewall rule for SQL Server instance" {
            $resultsNewPort[0].Successful | Should -Be $true
            $resultsNewPort[0].Type | Should -Be "Engine"
            $resultsNewPort[0].DisplayName | Should -Be "SQL Server instance $instanceName"
            $resultsNewPort[0].Status | Should -Be "The rule was successfully created."
        }

        It "creates second firewall rule for SQL Server Browser" {
            $resultsNewPort[1].Successful | Should -Be $true
            $resultsNewPort[1].Type | Should -Be "Browser"
            $resultsNewPort[1].DisplayName | Should -Be "SQL Server Browser"
            $resultsNewPort[1].Status | Should -Be "The rule was successfully created."
        }

        It "returns firewall rule for SQL Server instance with LocalPort" {
            $resultInstance = $resultsGetPort | Where-Object Type -eq "Engine"
            $resultInstance.Protocol | Should -Be "TCP"
            $resultInstance.LocalPort | Should -Not -BeNullOrEmpty
        }

        It "returns firewall rule for SQL Server Browser with port 1434" {
            $resultBrowser = $resultsGetPort | Where-Object Type -eq "Browser"
            $resultBrowser.Protocol | Should -Be "UDP"
            $resultBrowser.LocalPort | Should -Be "1434"
        }

        It "removes firewall rules" {
            $resultsRemovePort.Type | Should -Contain "Engine"
            $resultsRemovePort.IsRemoved | Should -Contain $true
            $resultsRemovePort.Status | Should -Contain "The rule was successfully removed."
        }
    }
}