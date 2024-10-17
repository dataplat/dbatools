param($ModuleName = 'dbatools')

Describe "Set-DbaResourceGovernor" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaResourceGovernor
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Enabled as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Enabled -Type switch
        }
        It "Should have Disabled as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Disabled -Type switch
        }
        It "Should have ClassifierFunction as a parameter" {
            $CommandUnderTest | Should -HaveParameter ClassifierFunction -Type string
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type switch
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
            Set-DbaResourceGovernor -SqlInstance $global:instance2 -Disabled -Confirm:$false
        }

        It "enables resource governor" {
            $results = Set-DbaResourceGovernor -SqlInstance $global:instance2 -Enabled -Confirm:$false
            $results.Enabled | Should -Be $true
        }

        It "disables resource governor" {
            $results = Set-DbaResourceGovernor -SqlInstance $global:instance2 -Disabled -Confirm:$false
            $results.Enabled | Should -Be $false
        }

        It "modifies resource governor classifier function" {
            $qualifiedClassifierFunction = "[dbo].[$classifierFunction]"
            $results = Set-DbaResourceGovernor -SqlInstance $global:instance2 -ClassifierFunction $classifierFunction -Confirm:$false
            $results.ClassifierFunction | Should -Be $qualifiedClassifierFunction
        }

        It "removes resource governor classifier function" {
            $results = Set-DbaResourceGovernor -SqlInstance $global:instance2 -ClassifierFunction 'NULL' -Confirm:$false
            $results.ClassifierFunction | Should -Be ''
        }

        AfterAll {
            $dropUDFQuery = "DROP FUNCTION [dbo].[$classifierFunction];"
            Invoke-DbaQuery -SqlInstance $global:instance2 -Query $dropUDFQuery -Database "master"
        }
    }
}
