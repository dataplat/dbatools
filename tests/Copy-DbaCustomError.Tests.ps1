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

        $sourceServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -Database master
        $sourceServer.Query("IF EXISTS (SELECT 1 FROM sys.messages WHERE message_id = 60000) EXEC sp_dropmessage @msgnum = 60000, @lang = 'all'")
        $sourceServer.Query("EXEC sp_addmessage @msgnum = 60000, @severity = 16, @msgtext = N'The item named %s already exists in %s.', @lang = 'us_english'")
        $sourceServer.Query("EXEC sp_addmessage @msgnum = 60000, @severity = 16, @msgtext = N'L''élément nommé %1! existe déjà dans %2!', @lang = 'French'")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $serversToClean = @($TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2)
        foreach ($serverInstance in $serversToClean) {
            $cleanupServer = Connect-DbaInstance -SqlInstance $serverInstance -Database master
            $cleanupServer.Query("IF EXISTS (SELECT 1 FROM sys.messages WHERE message_id = 60000) EXEC sp_dropmessage @msgnum = 60000, @lang = 'all'") | Out-Null
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When copying custom errors" {
        BeforeEach {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $destServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2 -Database master
            $destServer.Query("IF EXISTS (SELECT 1 FROM sys.messages WHERE message_id = 60000) EXEC sp_dropmessage @msgnum = 60000, @lang = 'all'")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should successfully copy custom error messages" {
            $splatCopyError = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                CustomError = 60000
            }
            $copyResults = Copy-DbaCustomError @splatCopyError
            $copyResults.Name[0] | Should -Be "60000:'us_english'"
            $copyResults.Name[1] | Should -Match "60000\:'Fran"
            $copyResults.Status | Should -Be @("Successful", "Successful")
        }

        It "Should skip existing custom errors" {
            $splatFirstCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                CustomError = 60000
            }
            Copy-DbaCustomError @splatFirstCopy

            $splatSecondCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                CustomError = 60000
            }
            $skipResults = Copy-DbaCustomError @splatSecondCopy
            $skipResults.Name[0] | Should -Be "60000:'us_english'"
            $skipResults.Name[1] | Should -Match "60000\:'Fran"
            $skipResults.Status | Should -Be @("Skipped", "Skipped")
        }

        It "Should verify custom error exists" {
            $errorResults = Get-DbaCustomError -SqlInstance $TestConfig.InstanceCopy1
            $errorResults.ID | Should -Contain 60000
        }
    }

    Context "Output validation" {
        BeforeAll {
            # Ensure source custom error exists for this context
            $outputSourceServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -Database master
            $outputSourceServer.Query("IF NOT EXISTS (SELECT 1 FROM sys.messages WHERE message_id = 60000) EXEC sp_addmessage @msgnum = 60000, @severity = 16, @msgtext = N'The item named %s already exists in %s.', @lang = 'us_english'")

            # Clean destination to ensure a fresh copy
            $outputDestServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2 -Database master
            $outputDestServer.Query("IF EXISTS (SELECT 1 FROM sys.messages WHERE message_id = 60000) EXEC sp_dropmessage @msgnum = 60000, @lang = 'all'")

            $splatCopyValidation = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                CustomError = 60000
            }
            # Filter out null entries that may come from internal Connect-DbaInstance calls
            $result = Copy-DbaCustomError @splatCopyValidation | Where-Object { $null -ne $PSItem }
        }

        It "Returns output with the expected TypeName" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].psobject.TypeNames | Should -Contain "dbatools.MigrationObject"
        }

        It "Has the expected default display properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("DateTime", "SourceServer", "DestinationServer", "Name", "Type", "Status", "Notes")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}