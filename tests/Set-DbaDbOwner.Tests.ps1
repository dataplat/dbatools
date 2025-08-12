#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaDbOwner",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "InputObject",
                "TargetLogin",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $svrConnection = Connect-DbaInstance -SqlInstance $TestConfig.instance1
        $ownerLogin = "dbatoolssci_owner_$(Get-Random)"
        $ownerLoginTwo = "dbatoolssci_owner2_$(Get-Random)"
        $testDbName = "dbatoolsci_$(Get-Random)"
        $testDbNameTwo = "dbatoolsci_$(Get-Random)"

        $splatCreateOwner = @{
            SqlInstance = $TestConfig.instance1
            Login       = $ownerLogin
            Password    = ("Password1234!" | ConvertTo-SecureString -AsPlainText -Force)
        }
        $null = New-DbaLogin @splatCreateOwner

        $splatCreateOwnerTwo = @{
            SqlInstance = $TestConfig.instance1
            Login       = $ownerLoginTwo
            Password    = ("Password1234!" | ConvertTo-SecureString -AsPlainText -Force)
        }
        $null = New-DbaLogin @splatCreateOwnerTwo

        $splatCreateDb = @{
            SqlInstance = $TestConfig.instance1
            Name        = $testDbName
            Owner       = "sa"
        }
        $null = New-DbaDatabase @splatCreateDb

        $splatCreateDbTwo = @{
            SqlInstance = $TestConfig.instance1
            Name        = $testDbNameTwo
            Owner       = "sa"
        }
        $null = New-DbaDatabase @splatCreateDbTwo

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $splatRemoveDb = @{
            SqlInstance = $TestConfig.instance1
            Database    = @($testDbName, $testDbNameTwo)
            Confirm     = $false
        }
        $null = Remove-DbaDatabase @splatRemoveDb

        $splatRemoveLogin = @{
            SqlInstance = $TestConfig.instance1
            Login       = @($ownerLogin, $ownerLoginTwo)
            Confirm     = $false
        }
        $null = Remove-DbaLogin @splatRemoveLogin
    }
    Context "When setting single database owner" {
        It "Sets the database owner on a specific database" {
            $splatSetOwner = @{
                SqlInstance = $TestConfig.instance1
                Database    = $testDbName
                TargetLogin = $ownerLogin
            }
            $results = Set-DbaDbOwner @splatSetOwner
            $results.Owner | Should -Be $ownerLogin
        }

        It "Check it actually set the owner" {
            $svrConnection.Databases[$testDbName].Refresh()
            $svrConnection.Databases[$testDbName].Owner | Should -Be $ownerLogin
        }
    }

    Context "When setting multiple database owners" {
        BeforeAll {
            $splatSetMultipleOwners = @{
                SqlInstance = $TestConfig.instance1
                Database    = @($testDbName, $testDbNameTwo)
                TargetLogin = $ownerLoginTwo
            }
            $multipleResults = Set-DbaDbOwner @splatSetMultipleOwners
        }

        It "Sets the database owner on multiple databases" {
            foreach ($result in $multipleResults) {
                $result.Owner | Should -Be $ownerLoginTwo
            }
        }

        It "Set 2 database owners" {
            $multipleResults.Count | Should -Be 2
        }
    }

    Context "When excluding databases" {
        BeforeAll {
            $svrConnection.Databases[$testDbName].Refresh()
            $splatExcludeDb = @{
                SqlInstance     = $TestConfig.instance1
                ExcludeDatabase = $testDbNameTwo
                TargetLogin     = $ownerLogin
            }
            $excludeResults = Set-DbaDbOwner @splatExcludeDb
        }

        It "Excludes specified database" {
            $excludeResults.Database | Should -Not -Contain $testDbNameTwo
        }

        It "Updates at least one database" {
            @($excludeResults).Count | Should -BeGreaterOrEqual 1
        }
    }

    Context "When using input from Get-DbaDatabase" {
        BeforeAll {
            $svrConnection.Databases[$testDbNameTwo].Refresh()
            $inputDatabase = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $testDbNameTwo
            $splatInputObject = @{
                InputObject = $inputDatabase
                TargetLogin = $ownerLogin
            }
            $inputResults = Set-DbaDbOwner @splatInputObject
        }

        It "Includes specified database" {
            $inputResults.Database | Should -Be $testDbNameTwo
        }

        It "Sets the database owner on databases" {
            $inputResults.Owner | Should -Be $ownerLogin
        }
    }

    Context "When setting database owner to sa" {
        BeforeAll {
            $saResults = Set-DbaDbOwner -SqlInstance $TestConfig.instance1
        }

        It "Sets the database owner on multiple databases" {
            foreach ($result in $saResults) {
                $result.Owner | Should -Be "sa"
            }
        }

        It "Updates at least one database" {
            @($saResults).Count | Should -BeGreaterOrEqual 1
        }
    }
}
