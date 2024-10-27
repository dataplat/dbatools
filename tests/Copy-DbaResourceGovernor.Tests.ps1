#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe "Copy-DbaResourceGovernor" -Tag "UnitTests" {
    BeforeAll {
        $command = Get-Command Copy-DbaResourceGovernor
        $expected = $TestConfig.CommonParameters
        $expected += @(
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
    Context "Parameter validation" {
        It "Has parameter: <_>" -ForEach $expected {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters ($($expected.Count))" {
            $hasparms = $command.Parameters.Values.Name
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasparms | Should -BeNullOrEmpty
        }
    }
}

Describe "Copy-DbaResourceGovernor" -Tag "IntegrationTests" {
    BeforeAll {
        $querySplat = @{
            SqlInstance = $TestConfig.instance2
            WarningAction = 'SilentlyContinue'
        }

        # Create prod pool and workload
        Invoke-DbaQuery @querySplat -Query "CREATE RESOURCE POOL dbatoolsci_prod WITH (MAX_CPU_PERCENT = 100, MIN_CPU_PERCENT = 50)"
        Invoke-DbaQuery @querySplat -Query "CREATE WORKLOAD GROUP dbatoolsci_prodprocessing WITH (IMPORTANCE = MEDIUM) USING dbatoolsci_prod"

        # Create offhours pool and workload
        Invoke-DbaQuery @querySplat -Query "CREATE RESOURCE POOL dbatoolsci_offhoursprocessing WITH (MAX_CPU_PERCENT = 50, MIN_CPU_PERCENT = 0)"
        Invoke-DbaQuery @querySplat -Query "CREATE WORKLOAD GROUP dbatoolsci_goffhoursprocessing WITH (IMPORTANCE = LOW) USING dbatoolsci_offhoursprocessing"

        Invoke-DbaQuery @querySplat -Query "ALTER RESOURCE GOVERNOR RECONFIGURE"

        # Create and set classifier function
        Invoke-DbaQuery @querySplat -Query "CREATE FUNCTION dbatoolsci_fnRG() RETURNS sysname WITH SCHEMABINDING AS BEGIN RETURN N'dbatoolsci_goffhoursprocessing' END"
        Invoke-DbaQuery @querySplat -Query "ALTER RESOURCE GOVERNOR with (CLASSIFIER_FUNCTION = dbo.dbatoolsci_fnRG); ALTER RESOURCE GOVERNOR RECONFIGURE;"
    }

    AfterAll {
        $cleanupSplat = @{
            SqlInstance = $TestConfig.instance2, $TestConfig.instance3
            WarningAction = 'SilentlyContinue'
        }

        Get-DbaProcess -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue

        Invoke-DbaQuery @cleanupSplat -Query "ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = NULL); ALTER RESOURCE GOVERNOR RECONFIGURE"
        Invoke-DbaQuery @cleanupSplat -Query "DROP FUNCTION [dbo].[dbatoolsci_fnRG];ALTER RESOURCE GOVERNOR RECONFIGURE"
        Invoke-DbaQuery @cleanupSplat -Query "DROP WORKLOAD GROUP [dbatoolsci_prodprocessing];ALTER RESOURCE GOVERNOR RECONFIGURE"
        Invoke-DbaQuery @cleanupSplat -Query "DROP WORKLOAD GROUP [dbatoolsci_goffhoursprocessing];ALTER RESOURCE GOVERNOR RECONFIGURE"
        Invoke-DbaQuery @cleanupSplat -Query "DROP RESOURCE POOL [dbatoolsci_offhoursprocessing];ALTER RESOURCE GOVERNOR RECONFIGURE"
        Invoke-DbaQuery @cleanupSplat -Query "DROP RESOURCE POOL [dbatoolsci_prod];ALTER RESOURCE GOVERNOR RECONFIGURE"
    }

    Context "When copying resource governor settings" {
        It "Copies the resource governor successfully" {
            $copyRGSplat = @{
                Source = $TestConfig.instance2
                Destination = $TestConfig.instance3
                Force = $true
                WarningAction = 'SilentlyContinue'
            }

            $results = Copy-DbaResourceGovernor @copyRGSplat
            $results.Status | Select-Object -Unique | Should -BeExactly 'Successful'
            $results.Status.Count | Should -BeGreaterThan 3
            $results.Name | Should -Contain 'dbatoolsci_prod'
        }

        It "Returns the proper classifier function" {
            $results = Get-DbaRgClassifierFunction -SqlInstance $TestConfig.instance3
            $results.Name | Should -BeExactly 'dbatoolsci_fnRG'
        }
    }
}