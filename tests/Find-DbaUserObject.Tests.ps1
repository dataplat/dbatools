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
        $null = New-DbaLogin -SqlInstance $TestConfig.instance2 -Login UserLogin1 -SecurePassword $securePassword
        $null = New-DbaLogin -SqlInstance $TestConfig.instance2 -Login UserLogin2 -SecurePassword $securePassword
        $null = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name UserDB1 -Owner UserLogin1
        $null = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name UserDB2 -Owner UserLogin2

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database UserDB1, UserDB2
        $null = Remove-DbaLogin -SqlInstance $TestConfig.instance2 -Login UserLogin1, UserLogin2

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command finds user objects" {
        It "Should find both user databases without pattern" {
            $results = Find-DbaUserObject -SqlInstance $TestConfig.instance2

            $results | Should -HaveCount 2
            $results.Type | Select-Object -Unique | Should -Be Database
            $results.Name | Should -Contain UserDB1
            $results.Name | Should -Contain UserDB2
            $results.Owner | Should -Contain UserLogin1
            $results.Owner | Should -Contain UserLogin2

        }

        It "Should find one user database with the pattern" {
            $results = Find-DbaUserObject -SqlInstance $TestConfig.instance2 -Pattern UserLogin1

            $results | Should -HaveCount 1
            $results.Type | Should -Be Database
            $results.Name | Should -Be UserDB1
            $results.Owner | Should -Be UserLogin1
        }
    }
}