#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe "Copy-DbaResourceGovernor" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Copy-DbaResourceGovernor
            $parameterNames = $TestConfig.CommonParameters
            $parameterNames += @(
                "Source",
                "SourceSqlCredential", 
                "Destination",
                "DestinationSqlCredential",
                "ResourcePool",
                "ExcludeResourcePool",
                "Force",
                "EnableException",
                "Confirm",
                "WhatIf"
            )
        }

        It "Has parameter: <_>" -ForEach $parameterNames {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters ($($parameterNames.Count))" {
            $command.Parameters.Values.Name | Should -HaveCount $parameterNames.Count
        }
    }
}

Describe "Copy-DbaResourceGovernor" -Tag "IntegrationTests" {
    BeforeAll {
        $splatSetup = @{
            WarningAction = 'SilentlyContinue'
            SqlInstance = $TestConfig.instance2
        }

        $setupQueries = @(
            "CREATE RESOURCE POOL dbatoolsci_prod WITH (MAX_CPU_PERCENT = 100, MIN_CPU_PERCENT = 50)",
            "CREATE WORKLOAD GROUP dbatoolsci_prodprocessing WITH (IMPORTANCE = MEDIUM) USING dbatoolsci_prod",
            "CREATE RESOURCE POOL dbatoolsci_offhoursprocessing WITH (MAX_CPU_PERCENT = 50, MIN_CPU_PERCENT = 0)",
            "CREATE WORKLOAD GROUP dbatoolsci_goffhoursprocessing WITH (IMPORTANCE = LOW) USING dbatoolsci_offhoursprocessing",
            "ALTER RESOURCE GOVERNOR RECONFIGURE",
            "CREATE FUNCTION dbatoolsci_fnRG() RETURNS sysname WITH SCHEMABINDING AS BEGIN RETURN N'dbatoolsci_goffhoursprocessing' END",
            "ALTER RESOURCE GOVERNOR with (CLASSIFIER_FUNCTION = dbo.dbatoolsci_fnRG); ALTER RESOURCE GOVERNOR RECONFIGURE;"
        )

        foreach ($query in $setupQueries) {
            Invoke-DbaQuery @splatSetup -Query $query
        }
    }

    AfterAll {
        $splatCleanup = @{
            WarningAction = 'SilentlyContinue'
            SqlInstance = @($TestConfig.instance2, $TestConfig.instance3)
        }

        Get-DbaProcess -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Program 'dbatools PowerShell module - dbatools.io' | 
            Stop-DbaProcess -WarningAction SilentlyContinue

        $cleanupQueries = @(
            "ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = NULL); ALTER RESOURCE GOVERNOR RECONFIGURE",
            "DROP FUNCTION [dbo].[dbatoolsci_fnRG];ALTER RESOURCE GOVERNOR RECONFIGURE",
            "DROP WORKLOAD GROUP [dbatoolsci_prodprocessing];ALTER RESOURCE GOVERNOR RECONFIGURE",
            "DROP WORKLOAD GROUP [dbatoolsci_goffhoursprocessing];ALTER RESOURCE GOVERNOR RECONFIGURE", 
            "DROP RESOURCE POOL [dbatoolsci_offhoursprocessing];ALTER RESOURCE GOVERNOR RECONFIGURE",
            "DROP RESOURCE POOL [dbatoolsci_prod];ALTER RESOURCE GOVERNOR RECONFIGURE"
        )

        foreach ($query in $cleanupQueries) {
            Invoke-DbaQuery @splatCleanup -Query $query
        }
    }

    Context "When copying resource governor configuration" {
        BeforeAll {
            $splatCopy = @{
                Source = $TestConfig.instance2
                Destination = $TestConfig.instance3
                Force = $true
                WarningAction = 'SilentlyContinue'
            }
            $results = Copy-DbaResourceGovernor @splatCopy
        }

        It "Copies all components successfully" {
            $results.Status | Should -Be 'Successful'
            $results.Status.Count | Should -BeGreaterThan 3
            $results.Name | Should -Contain 'dbatoolsci_prod'
        }

        It "Copies the classifier function" {
            $classifierResults = Get-DbaRgClassifierFunction -SqlInstance $TestConfig.instance3
            $classifierResults.Name | Should -Be 'dbatoolsci_fnRG'
        }
    }
}
