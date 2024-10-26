#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe "Copy-DbaCustomError" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Copy-DbaCustomError
            $expected = $TestConfig.CommonParameters
            $expected += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "CustomError",
                "ExcludeCustomError",
                "Force",
                "EnableException",
                "Confirm",
                "WhatIf"
            )
        }

        It "Has parameter: <_>" -ForEach $expected {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters ($($expected.Count))" {
            $hasparms = $command.Parameters.Values.Name
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasparms | Should -BeNullOrEmpty
        }
    }
}

Describe "Copy-DbaCustomError" -Tag "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2 -Database master
        $server.Query("EXEC sp_addmessage @msgnum = 60000, @severity = 16,@msgtext = N'The item named %s already exists in %s.',@lang = 'us_english';")
        $server.Query("EXEC sp_addmessage @msgnum = 60000, @severity = 16, @msgtext = N'L''élément nommé %1! existe déjà dans %2!',@lang = 'French';")
    }
    AfterAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2 -Database master
        $server.Query("EXEC sp_dropmessage @msgnum = 60000, @lang = 'all';")
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance3 -Database master
        $server.Query("EXEC sp_dropmessage @msgnum = 60000, @lang = 'all';")
    }

    Context "When copying custom errors" {
        It "Copies the sample custom error" {
            $results = Copy-DbaCustomError -Source $TestConfig.instance2 -Destination $TestConfig.instance3 -CustomError 60000
            $results.Name | Should -Be "60000:'us_english'", "60000:'Français'"
            $results.Status | Should -Be 'Successful', 'Successful'
        }

        It "Doesn't overwrite existing custom errors" {
            $results = Copy-DbaCustomError -Source $TestConfig.instance2 -Destination $TestConfig.instance3 -CustomError 60000
            $results.Name | Should -Be "60000:'us_english'", "60000:'Français'"
            $results.Status | Should -Be 'Skipped', 'Skipped'
        }

       It "Verifies the newly copied custom error exists" {
            $results = Get-DbaCustomError -SqlInstance $TestConfig.instance2
            $results.ID | Should -Contain 60000
        }
    }
}