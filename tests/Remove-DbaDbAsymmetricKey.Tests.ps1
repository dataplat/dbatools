#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbAsymmetricKey",
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
                "Database",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $database = "RemAsy"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $database

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $database -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Remove a certificate" {
        BeforeAll {
            $keyname = "test1"
            $tPassword = ConvertTo-SecureString "ThisIsThePassword1" -AsPlainText -Force
            New-DbaDbMasterKey -SqlInstance $TestConfig.InstanceSingle -Database $database -SecurePassword $tPassword
            $key = New-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Name $keyname -Database $database
            $results = Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Name $keyname -Database $database -WarningVariable warnvar
        }

        It "Should create new key in $database called $keyname" {
            $warnvar | Should -BeNullOrEmpty
            $results.database | Should -Be $database
            $results.name | Should -Be $keyname
            $results.KeyLength | Should -Be "2048"
        }

        It "Should Remove a certificate" {
            $removeResults = Remove-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Name $keyname -Database $database
            $getResults = Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Name $keyname -Database $database
            $getResults | Should -HaveCount 0
            $removeResults.Status | Should -Be "Success"
        }
    }
    Context "Remove a specific certificate" {
        BeforeAll {
            $keyname = "test1"
            $keyname2 = "test2"
            $key = New-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Name $keyname -Database $database
            $key2 = New-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Name $keyname2 -Database $database
            $results = Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Database $database -WarningVariable warnvar
        }

        AfterAll {
            Remove-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Name $keyname2 -Database $database -ErrorAction SilentlyContinue
        }

        It "Should created new keys in $database" {
            $warnvar | Should -BeNullOrEmpty
            $results | Should -HaveCount 2
        }

        It "Should Remove a specific certificate" {
            $removeResults = Remove-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Name $keyname -Database $database
            $getResults = Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Database $database
            $getResults | Should -HaveCount 1
            $getResults[0].Name | Should -Be $keyname2
            $removeResults.Status | Should -Be "Success"
            $removeResults.Name | Should -Be $keyname
        }
    }
}