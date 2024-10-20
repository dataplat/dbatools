param($ModuleName = 'dbatools')

Describe "Copy-DbaResourceGovernor" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Copy-DbaResourceGovernor
        }
        $knownParameters = @(
            'Source',
            'SourceSqlCredential',
            'Destination',
            'DestinationSqlCredential',
            'ResourcePool',
            'ExcludeResourcePool',
            'Force',
            'EnableException',
            'WhatIf',
            'Confirm'
        )
        It "Should have the correct parameters" {
            $command | Should -HaveParameter $knownParameters
        }
    }

    Context "Command works" -Tag "IntegrationTests" {
        BeforeAll {
            $sql = @"
CREATE RESOURCE POOL dbatoolsci_prod
WITH
(
     MAX_CPU_PERCENT = 100,
     MIN_CPU_PERCENT = 50
)
CREATE WORKLOAD GROUP dbatoolsci_prodprocessing
WITH
(
     IMPORTANCE = MEDIUM
) USING dbatoolsci_prod
CREATE RESOURCE POOL dbatoolsci_offhoursprocessing
WITH
(
     MAX_CPU_PERCENT = 50,
     MIN_CPU_PERCENT = 0
)
CREATE WORKLOAD GROUP dbatoolsci_goffhoursprocessing
WITH
(
     IMPORTANCE = LOW
)
USING dbatoolsci_offhoursprocessing
ALTER RESOURCE GOVERNOR RECONFIGURE
CREATE FUNCTION dbatoolsci_fnRG()
RETURNS sysname
WITH SCHEMABINDING
AS
BEGIN
     RETURN N'dbatoolsci_goffhoursprocessing'
END
ALTER RESOURCE GOVERNOR with (CLASSIFIER_FUNCTION = dbo.dbatoolsci_fnRG)
ALTER RESOURCE GOVERNOR RECONFIGURE
"@
            Invoke-DbaQuery -WarningAction SilentlyContinue -SqlInstance $global:instance2 -Query $sql
        }

        AfterAll {
            $cleanup = @"
ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = NULL)
ALTER RESOURCE GOVERNOR RECONFIGURE
DROP FUNCTION [dbo].[dbatoolsci_fnRG]
ALTER RESOURCE GOVERNOR RECONFIGURE
DROP WORKLOAD GROUP [dbatoolsci_prodprocessing]
ALTER RESOURCE GOVERNOR RECONFIGURE
DROP WORKLOAD GROUP [dbatoolsci_goffhoursprocessing]
ALTER RESOURCE GOVERNOR RECONFIGURE
DROP RESOURCE POOL [dbatoolsci_offhoursprocessing]
ALTER RESOURCE GOVERNOR RECONFIGURE
DROP RESOURCE POOL [dbatoolsci_prod]
ALTER RESOURCE GOVERNOR RECONFIGURE
"@
            Get-DbaProcess -SqlInstance $global:instance2, $global:instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
            Invoke-DbaQuery -WarningAction SilentlyContinue -SqlInstance $global:instance2, $global:instance3 -Query $cleanup
        }

        It "copies the resource governor successfully" {
            $results = Copy-DbaResourceGovernor -Source $global:instance2 -Destination $global:instance3 -Force -WarningAction SilentlyContinue
            $results.Status | Select-Object -Unique | Should -Be 'Successful'
            $results.Status.Count | Should -BeGreaterThan 3
            $results.Name | Should -Contain 'dbatoolsci_prod'
        }

        It "returns the proper classifier function" {
            $results = Get-DbaRgClassifierFunction -SqlInstance $global:instance3
            $results.Name | Should -Be 'dbatoolsci_fnRG'
        }
    }
}
