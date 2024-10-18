param($ModuleName = 'dbatools')

Describe "Get-DbaSchemaChangeHistory" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaSchemaChangeHistory
        }
        It "Should have SqlInstance as a non-mandatory parameter of type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a non-mandatory parameter of type System.Management.Automation.PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have Database as a non-mandatory parameter of type System.Object[]" {
            $CommandUnderTest | Should -HaveParameter Database -Type System.Object[] -Mandatory:$false
        }
        It "Should have ExcludeDatabase as a non-mandatory parameter of type System.Object[]" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type System.Object[] -Mandatory:$false
        }
        It "Should have Since as a non-mandatory parameter of type Dataplat.Dbatools.Utility.DbaDateTime" {
            $CommandUnderTest | Should -HaveParameter Since -Type Dataplat.Dbatools.Utility.DbaDateTime -Mandatory:$false
        }
        It "Should have Object as a non-mandatory parameter of type System.String[]" {
            $CommandUnderTest | Should -HaveParameter Object -Type System.String[] -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
    }
}

Describe "Get-DbaSchemaChangeHistory Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        . (Join-Path $PSScriptRoot 'constants.ps1')
    }

    Context "Testing if schema changes are discovered" {
        BeforeAll {
            $db = Get-DbaDatabase -SqlInstance $global:instance1 -Database tempdb
            $db.Query("CREATE TABLE dbatoolsci_schemachange (id int identity)")
            $db.Query("EXEC sp_rename 'dbatoolsci_schemachange', 'dbatoolsci_schemachange1'")
        }
        AfterAll {
            $db.Query("DROP TABLE dbo.dbatoolsci_schemachange1")
        }

        It "notices dbatoolsci_schemachange changed" {
            $results = Get-DbaSchemaChangeHistory -SqlInstance $global:instance1 -Database tempdb
            $results.Object -match 'dbatoolsci_schemachange' | Should -Be $true
        }
    }
}
