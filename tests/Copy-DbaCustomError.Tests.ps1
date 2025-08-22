#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaCustomError",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "CustomError",
                "ExcludeCustomError",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $sourceServer = Connect-DbaInstance -SqlInstance $TestConfig.instance2 -Database master
        $sourceServer.Query("IF EXISTS (SELECT 1 FROM sys.messages WHERE message_id = 60000) EXEC sp_dropmessage @msgnum = 60000, @lang = 'all'")
        $sourceServer.Query("EXEC sp_addmessage @msgnum = 60000, @severity = 16, @msgtext = N'The item named %s already exists in %s.', @lang = 'us_english'")
        $sourceServer.Query("EXEC sp_addmessage @msgnum = 60000, @severity = 16, @msgtext = N'L''élément nommé %1! existe déjà dans %2!', @lang = 'French'")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $serversToClean = @($TestConfig.instance2, $TestConfig.instance3)
        foreach ($serverInstance in $serversToClean) {
            $cleanupServer = Connect-DbaInstance -SqlInstance $serverInstance -Database master
            $cleanupServer.Query("IF EXISTS (SELECT 1 FROM sys.messages WHERE message_id = 60000) EXEC sp_dropmessage @msgnum = 60000, @lang = 'all'") | Out-Null
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When copying custom errors" {
        BeforeEach {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $destServer = Connect-DbaInstance -SqlInstance $TestConfig.instance3 -Database master
            $destServer.Query("IF EXISTS (SELECT 1 FROM sys.messages WHERE message_id = 60000) EXEC sp_dropmessage @msgnum = 60000, @lang = 'all'")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should successfully copy custom error messages" {
            $splatCopyError = @{
                Source      = $TestConfig.instance2
                Destination = $TestConfig.instance3
                CustomError = 60000
            }
            $copyResults = Copy-DbaCustomError @splatCopyError
            $copyResults.Name[0] | Should -Be "60000:'us_english'"
            $copyResults.Name[1] | Should -Match "60000\:'Fran"
            $copyResults.Status | Should -Be @("Successful", "Successful")
        }

        It "Should skip existing custom errors" {
            $splatFirstCopy = @{
                Source      = $TestConfig.instance2
                Destination = $TestConfig.instance3
                CustomError = 60000
            }
            Copy-DbaCustomError @splatFirstCopy

            $splatSecondCopy = @{
                Source      = $TestConfig.instance2
                Destination = $TestConfig.instance3
                CustomError = 60000
            }
            $skipResults = Copy-DbaCustomError @splatSecondCopy
            $skipResults.Name[0] | Should -Be "60000:'us_english'"
            $skipResults.Name[1] | Should -Match "60000\:'Fran"
            $skipResults.Status | Should -Be @("Skipped", "Skipped")
        }

        It "Should verify custom error exists" {
            $errorResults = Get-DbaCustomError -SqlInstance $TestConfig.instance2
            $errorResults.ID | Should -Contain 60000
        }
    }
}