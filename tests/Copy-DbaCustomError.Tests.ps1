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
        $primaryServer = Connect-DbaInstance -SqlInstance $TestConfig.instance2 -Database master

        # Add test messages in English and French
        $messageParams = @{
            msgnum = 60000
            severity = 16
            englishText = "The item named %s already exists in %s."
            frenchText = "L'élément nommé %1! existe déjà dans %2!"
        }

        $primaryServer.Query("EXEC sp_addmessage @msgnum = $($messageParams.msgnum),
            @severity = $($messageParams.severity),
            @msgtext = N'$($messageParams.englishText)',
            @lang = 'us_english'")

        $primaryServer.Query("EXEC sp_addmessage @msgnum = $($messageParams.msgnum),
            @severity = $($messageParams.severity),
            @msgtext = N'$($messageParams.frenchText)',
            @lang = 'French'")
    }

    AfterAll {
        $serversToClean = @($TestConfig.instance2, $TestConfig.instance3)
        foreach ($serverInstance in $serversToClean) {
            $cleanupServer = Connect-DbaInstance -SqlInstance $serverInstance -Database master
            $cleanupServer.Query("EXEC sp_dropmessage @msgnum = 60000, @lang = 'all'")
        }
    }

    Context "When copying custom errors" {
        It "Should successfully copy custom error messages" {
            $copyResults = Copy-DbaCustomError -Source $TestConfig.instance2 -Destination $TestConfig.instance3 -CustomError 60000

            $copyResults.Name.Count | Should -Be 2
            $copyResults.Name[0] | Should -BeExactly "60000:'us_english'"
            # the French message broke Pester v5 encoding so we're using -Match instead of -BeExactly
            # Expected @('60000:'us_english'', '60000:'FranÃ§ais''), but got @(60000:'us_english', 60000:'Français').
            $copyResults.Name[1] | Should -Match "60000:'Fran"
            $copyResults.Status | Should -BeExactly @('Successful', 'Successful')
        }

        It "Should skip existing custom errors" {
            $duplicateResults = Copy-DbaCustomError -Source $TestConfig.instance2 -Destination $TestConfig.instance3 -CustomError 60000

            $duplicateResults.Name.Count | Should -Be 2
            $duplicateResults.Name[0] | Should -BeExactly "60000:'us_english'"
            # the French message broke Pester v5 so we're using -Match instead of -BeExactly
            # Expected @('60000:'us_english'', '60000:'FranÃ§ais''), but got @(60000:'us_english', 60000:'Français').
            $duplicateResults.Name[1] | Should -Match "60000:'Fran"
            $duplicateResults.Status | Should -BeExactly @('Skipped', 'Skipped')
        }

        It "Should verify custom error exists" {
            $customErrors = Get-DbaCustomError -SqlInstance $TestConfig.instance2
            $customErrors.ID | Should -Contain 60000
        }
    }
}