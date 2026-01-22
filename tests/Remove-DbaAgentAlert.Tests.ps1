#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaAgentAlert",
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
                "Alert",
                "ExcludeAlert",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeEach {

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $alertName = "dbatoolsci_test_$(Get-Random)"
        $alertName2 = "dbatoolsci_test_$(Get-Random)"

        $null = Invoke-DbaQuery -SqlInstance $server -Query "EXEC msdb.dbo.sp_add_alert @name=N'$alertName', @event_description_keyword=N'$alertName', @severity=25"
        $null = Invoke-DbaQuery -SqlInstance $server -Query "EXEC msdb.dbo.sp_add_alert @name=N'$alertName2', @event_description_keyword=N'$alertName2', @severity=25"
    }

    Context "commands work as expected" {

        It "removes a SQL Agent alert" {
            (Get-DbaAgentAlert -SqlInstance $server -Alert $alertName ) | Should -Not -BeNullOrEmpty
            Remove-DbaAgentAlert -SqlInstance $server -Alert $alertName
            (Get-DbaAgentAlert -SqlInstance $server -Alert $alertName ) | Should -BeNullOrEmpty
        }

        It "supports piping SQL Agent alert" {
            (Get-DbaAgentAlert -SqlInstance $server -Alert $alertName ) | Should -Not -BeNullOrEmpty
            Get-DbaAgentAlert -SqlInstance $server -Alert $alertName | Remove-DbaAgentAlert
            (Get-DbaAgentAlert -SqlInstance $server -Alert $alertName ) | Should -BeNullOrEmpty
        }

        It "removes all SQL Agent alerts but excluded" {
            (Get-DbaAgentAlert -SqlInstance $server -Alert $alertName2 ) | Should -Not -BeNullOrEmpty
            (Get-DbaAgentAlert -SqlInstance $server -ExcludeAlert $alertName2 ) | Should -Not -BeNullOrEmpty
            Remove-DbaAgentAlert -SqlInstance $server -ExcludeAlert $alertName2
            (Get-DbaAgentAlert -SqlInstance $server -ExcludeAlert $alertName2 ) | Should -BeNullOrEmpty
            (Get-DbaAgentAlert -SqlInstance $server -Alert $alertName2 ) | Should -Not -BeNullOrEmpty
        }

        It "removes all SQL Agent alerts" {
            (Get-DbaAgentAlert -SqlInstance $server ) | Should -Not -BeNullOrEmpty
            Remove-DbaAgentAlert -SqlInstance $server
            (Get-DbaAgentAlert -SqlInstance $server ) | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $alertName = "dbatoolsci_test_$(Get-Random)"
            $null = Invoke-DbaQuery -SqlInstance $server -Query "EXEC msdb.dbo.sp_add_alert @name=N'$alertName', @event_description_keyword=N'$alertName', @severity=25"
            $result = Remove-DbaAgentAlert -SqlInstance $server -Alert $alertName -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Name',
                'Status',
                'IsRemoved'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Returns IsRemoved as boolean" {
            $result.IsRemoved | Should -BeOfType [bool]
        }

        It "Returns Status as string" {
            $result.Status | Should -BeOfType [string]
        }
    }
}