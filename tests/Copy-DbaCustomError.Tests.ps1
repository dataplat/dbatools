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
        $server.Query("IF EXISTS (SELECT 1 FROM sys.messages WHERE message_id = 60000) EXEC sp_dropmessage @msgnum = 60000, @lang = 'all'")
        $server.Query("EXEC sp_addmessage @msgnum = 60000, @severity = 16, @msgtext = N'The item named %s already exists in %s.', @lang = 'us_english'")
        $server.Query("EXEC sp_addmessage @msgnum = 60000, @severity = 16, @msgtext = N'L''élément nommé %1! existe déjà dans %2!', @lang = 'French'")
    }

    AfterAll {
        $serversToClean = @($TestConfig.instance2, $TestConfig.instance3)
        foreach ($serverInstance in $serversToClean) {
            $cleanupServer = Connect-DbaInstance -SqlInstance $serverInstance -Database master
            $cleanupServer.Query("IF EXISTS (SELECT 1 FROM sys.messages WHERE message_id = 60000) EXEC sp_dropmessage @msgnum = 60000, @lang = 'all'")
        }
    }

    Context "When copying custom errors" {
        BeforeEach {
            # Clean destination before each test
            $destServer = Connect-DbaInstance -SqlInstance $TestConfig.instance3 -Database master
            $destServer.Query("IF EXISTS (SELECT 1 FROM sys.messages WHERE message_id = 60000) EXEC sp_dropmessage @msgnum = 60000, @lang = 'all'")
        }

        It "Should successfully copy custom error messages" {
            $results = Copy-DbaCustomError -Source $TestConfig.instance2 -Destination $TestConfig.instance3 -CustomError 60000
            $results.Name[0] | Should -Be "60000:'us_english'"
            $results.Name[1] | Should -Match "60000\:'Fran"
            $results.Status | Should -Be @("Successful", "Successful")
        }

        It "Should skip existing custom errors" {
            Copy-DbaCustomError -Source $TestConfig.instance2 -Destination $TestConfig.instance3 -CustomError 60000
            $results = Copy-DbaCustomError -Source $TestConfig.instance2 -Destination $TestConfig.instance3 -CustomError 60000
            $results.Name[0] | Should -Be "60000:'us_english'"
            $results.Name[1] | Should -Match "60000\:'Fran"
            $results.Status | Should -Be @("Skipped", "Skipped")
        }

        It "Should verify custom error exists" {
            $results = Get-DbaCustomError -SqlInstance $TestConfig.instance2
            $results.ID | Should -Contain 60000
        }
    }
}
