param($ModuleName = 'dbatools')

Describe "Add-DbaExtendedProperty" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Add-DbaExtendedProperty
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have Name as a parameter" {
            $CommandUnderTest | Should -HaveParameter Name
        }
        It "Should have Value as a parameter" {
            $CommandUnderTest | Should -HaveParameter Value
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            $random = Get-Random
            $server2 = Connect-DbaInstance -SqlInstance $global:instance2
            $null = Get-DbaProcess -SqlInstance $server2 | Where-Object Program -match dbatools | Stop-DbaProcess -Confirm:$false
            $newDbName = "dbatoolsci_newdb_$random"
            $db = New-DbaDatabase -SqlInstance $server2 -Name $newDbName
        }

        AfterAll {
            $null = $db | Remove-DbaDatabase -Confirm:$false
        }

        It "adds an extended property to a database" {
            $ep = $db | Add-DbaExtendedProperty -Name "Test_Database_Name" -Value "Sup"
            $ep.Name | Should -Be "Test_Database_Name"
            $ep.ParentName | Should -Be $db.Name
            $ep.Value | Should -Be "Sup"
        }
    }
}
