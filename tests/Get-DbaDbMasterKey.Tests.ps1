#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbMasterKey",
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
                "Database",
                "ExcludeDatabase",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $dbname = "dbatoolsci_test_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $dbname
        $splatMasterKey = @{
            SqlInstance = $TestConfig.InstanceSingle
            Database    = $dbname
            Password    = (ConvertTo-SecureString -AsPlainText -Force -String "ThisIsAPassword!")
        }
        $null = New-DbaDbMasterKey @splatMasterKey
    }

    AfterAll {
        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname
    }

    It "Gets DbMasterKey" {
        $results = Get-DbaDbMasterKey -SqlInstance $TestConfig.InstanceSingle | Where-Object Database -eq $dbname

        $results | Should -Not -BeNullOrEmpty
        $results.Database | Should -BeExactly $dbname
        $results.isEncryptedByServer | Should -BeTrue
    }

    It "Gets DbMasterKey when using -Database" {
        $results = Get-DbaDbMasterKey -SqlInstance $TestConfig.InstanceSingle -Database $dbname

        $results | Should -Not -BeNullOrEmpty
        $results.Database | Should -BeExactly $dbname
        $results.isEncryptedByServer | Should -BeTrue
    }

    It "Gets no DbMasterKey when using -ExcludeDatabase" {
        $results = Get-DbaDbMasterKey -SqlInstance $TestConfig.InstanceSingle -ExcludeDatabase master, $dbname

        $results | Should -BeNullOrEmpty
    }
}