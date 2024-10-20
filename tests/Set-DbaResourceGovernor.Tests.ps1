param($ModuleName = 'dbatools')

Describe "Set-DbaResourceGovernor" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaResourceGovernor
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Enabled",
            "Disabled",
            "ClassifierFunction",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command actually works" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        BeforeAll {
            $classifierFunction = "dbatoolsci_fnRGClassifier"

            $createUDFQuery = "CREATE FUNCTION $classifierFunction()
            RETURNS SYSNAME
            WITH SCHEMABINDING
            AS
            BEGIN
            RETURN DB_NAME();
            END;"
            Invoke-DbaQuery -SqlInstance $global:instance2 -Query $createUDFQuery -Database "master"
            Set-DbaResourceGovernor -SqlInstance $global:instance2 -Disabled
        }

        It "enables resource governor" {
            $results = Set-DbaResourceGovernor -SqlInstance $global:instance2 -Enabled
            $results.Enabled | Should -Be $true
        }

        It "disables resource governor" {
            $results = Set-DbaResourceGovernor -SqlInstance $global:instance2 -Disabled
            $results.Enabled | Should -Be $false
        }

        It "modifies resource governor classifier function" {
            $qualifiedClassifierFunction = "[dbo].[$classifierFunction]"
            $results = Set-DbaResourceGovernor -SqlInstance $global:instance2 -ClassifierFunction $classifierFunction
            $results.ClassifierFunction | Should -Be $qualifiedClassifierFunction
        }

        It "removes resource governor classifier function" {
            $results = Set-DbaResourceGovernor -SqlInstance $global:instance2 -ClassifierFunction 'NULL'
            $results.ClassifierFunction | Should -Be ''
        }

        AfterAll {
            $dropUDFQuery = "DROP FUNCTION [dbo].[$classifierFunction];"
            Invoke-DbaQuery -SqlInstance $global:instance2 -Query $dropUDFQuery -Database "master"
        }
    }
}
