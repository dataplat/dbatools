#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Find-DbaUserObject",
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
                "Pattern",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $password = 'MyV3ry$ecur3P@ssw0rd'
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        $null = New-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login UserLogin1 -SecurePassword $securePassword
        $null = New-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login UserLogin2 -SecurePassword $securePassword
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name UserDB1 -Owner UserLogin1
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name UserDB2 -Owner UserLogin2

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database UserDB1, UserDB2
        $null = Remove-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login UserLogin1, UserLogin2

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command finds user objects" {
        It "Should find user databases without pattern" {
            $results = Find-DbaUserObject -SqlInstance $TestConfig.InstanceSingle

            $results.Count | Should -BeGreaterOrEqual 2
            $results.Type | Should -Contain Database
            $results.Name | Should -Contain UserDB1
            $results.Name | Should -Contain UserDB2
            $results.Owner | Should -Contain UserLogin1
            $results.Owner | Should -Contain UserLogin2

        }

        It "Should find one user database with the pattern" {
            $results = Find-DbaUserObject -SqlInstance $TestConfig.InstanceSingle -Pattern UserLogin1

            $results | Should -HaveCount 1
            $results.Type | Should -Be Database
            $results.Name | Should -Be UserDB1
            $results.Owner | Should -Be UserLogin1
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Find-DbaUserObject -SqlInstance $TestConfig.InstanceSingle -EnableException
        }

        It "Returns PSCustomObject" {
            $result[0].PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default properties" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Type",
                "Owner",
                "Name",
                "Parent"
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in output"
            }
        }
    }
}