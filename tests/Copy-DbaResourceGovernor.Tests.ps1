param($ModuleName = 'dbatools')

Describe "Copy-DbaResourceGovernor" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"

        $sql = @"
CREATE RESOURCE POOL dbatoolsci_prod
WITH
(
     MAX_CPU_PERCENT = 100,
     MIN_CPU_PERCENT = 50
);
CREATE WORKLOAD GROUP dbatoolsci_prodprocessing
WITH
(
     IMPORTANCE = MEDIUM
) USING dbatoolsci_prod;
CREATE RESOURCE POOL dbatoolsci_offhoursprocessing
WITH
(
     MAX_CPU_PERCENT = 50,
     MIN_CPU_PERCENT = 0
);
CREATE WORKLOAD GROUP dbatoolsci_goffhoursprocessing
WITH
(
     IMPORTANCE = LOW
)
USING dbatoolsci_offhoursprocessing;
ALTER RESOURCE GOVERNOR RECONFIGURE;
CREATE FUNCTION dbatoolsci_fnRG()
RETURNS sysname
WITH SCHEMABINDING
AS
BEGIN
     RETURN N'dbatoolsci_goffhoursprocessing'
END;
ALTER RESOURCE GOVERNOR with (CLASSIFIER_FUNCTION = dbo.dbatoolsci_fnRG);
ALTER RESOURCE GOVERNOR RECONFIGURE;
"@
        Invoke-DbaQuery -WarningAction SilentlyContinue -SqlInstance $script:instance2 -Query $sql
    }

    AfterAll {
        $cleanup = @"
ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = NULL);
ALTER RESOURCE GOVERNOR RECONFIGURE;
DROP FUNCTION [dbo].[dbatoolsci_fnRG];
ALTER RESOURCE GOVERNOR RECONFIGURE;
DROP WORKLOAD GROUP [dbatoolsci_prodprocessing];
ALTER RESOURCE GOVERNOR RECONFIGURE;
DROP WORKLOAD GROUP [dbatoolsci_goffhoursprocessing];
ALTER RESOURCE GOVERNOR RECONFIGURE;
DROP RESOURCE POOL [dbatoolsci_offhoursprocessing];
ALTER RESOURCE GOVERNOR RECONFIGURE;
DROP RESOURCE POOL [dbatoolsci_prod];
ALTER RESOURCE GOVERNOR RECONFIGURE;
"@
        Get-DbaProcess -SqlInstance $script:instance2, $script:instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
        Invoke-DbaQuery -WarningAction SilentlyContinue -SqlInstance $script:instance2, $script:instance3 -Query $cleanup
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Copy-DbaResourceGovernor
        }
        It "Should have Source parameter" {
            $CommandUnderTest | Should -HaveParameter Source -Type DbaInstanceParameter
        }
        It "Should have SourceSqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SourceSqlCredential -Type PSCredential
        }
        It "Should have Destination parameter" {
            $CommandUnderTest | Should -HaveParameter Destination -Type DbaInstanceParameter[]
        }
        It "Should have DestinationSqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationSqlCredential -Type PSCredential
        }
        It "Should have ResourcePool parameter" {
            $CommandUnderTest | Should -HaveParameter ResourcePool -Type Object[]
        }
        It "Should have ExcludeResourcePool parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeResourcePool -Type Object[]
        }
        It "Should have Force parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type SwitchParameter
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }

    Context "Command works" {
        It "copies the resource governor successfully" {
            $results = Copy-DbaResourceGovernor -Source $script:instance2 -Destination $script:instance3 -Force -WarningAction SilentlyContinue
            $results.Status | Select-Object -Unique | Should -Be 'Successful'
            $results.Status.Count | Should -BeGreaterThan 3
            $results.Name | Should -Contain 'dbatoolsci_prod'
        }
        It "returns the proper classifier function" {
            $results = Get-DbaRgClassifierFunction -SqlInstance $script:instance3
            $results.Name | Should -Be 'dbatoolsci_fnRG'
        }
    }
}
