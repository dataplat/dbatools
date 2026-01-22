#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Find-DbaDatabase",
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
                "Property",
                "Pattern",
                "Exact",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command actually works" {
        BeforeAll {
            $results = Find-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Pattern Master
        }

        It "Should return correct properties" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Name",
                "Id",
                "Size",
                "Owner",
                "CreateDate",
                "ServiceBrokerGuid",
                "Tables",
                "StoredProcedures",
                "Views",
                "ExtendedProperties"
            )
            ($results[0].PsObject.Properties.Name | Sort-Object) | Should -Be ($expectedProps | Sort-Object)
        }

        It "Should return true if Database Master is Found" {
            ($results | Where-Object Name -match "Master") | Should -Be $true
            $results.Id | Should -Be (Get-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Database Master).Id
        }

        It "Should return true if Creation Date of Master is '4/8/2003 9:13:36 AM'" {
            $($results.CreateDate.ToFileTimeutc()[0]) -eq 126942668163900000 | Should -Be $true
        }
    }

    Context "Multiple instances" {
        BeforeAll {
            $results = Find-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Pattern Master
        }

        It "Should return true if Executed Against 2 instances: $TestConfig.InstanceMulti1 and $($TestConfig.InstanceMulti2)" {
            ($results.InstanceName | Select-Object -Unique).Count -eq 2 | Should -Be $true
        }
    }

    Context "Property filtering" {
        BeforeAll {
            $results = Find-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Property ServiceBrokerGuid -Pattern -0000-0000-000000000000
        }

        It "Should return true if Database Found via Property Filter" {
            $results.ServiceBrokerGuid | Should -BeLike "*-0000-0000-000000000000"
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Find-DbaDatabase -SqlInstance $TestConfig.instance1 -Pattern master -EnableException
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
                'Id',
                'Size',
                'Owner',
                'CreateDate',
                'ServiceBrokerGuid',
                'Tables',
                'StoredProcedures',
                'Views',
                'ExtendedProperties'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }
}