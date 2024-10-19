param($ModuleName = 'dbatools')

Describe "Remove-DbaDbUdf" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaDbUdf
        }
        It "Should have SqlInstance as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have ExcludeDatabase as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase
        }
        It "Should have ExcludeSystemUdf as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeSystemUdf
        }
        It "Should have Schema as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Schema
        }
        It "Should have ExcludeSchema as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeSchema
        }
        It "Should have Name as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Name
        }
        It "Should have ExcludeName as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeName
        }
        It "Should have InputObject as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command usage" {
        BeforeAll {
            . (Join-Path $PSScriptRoot 'constants.ps1')
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $dbname1 = "dbatoolsci_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $server -Name $dbname1

            $udf1 = "dbatoolssci_udf1_$(Get-Random)"
            $udf2 = "dbatoolssci_udf2_$(Get-Random)"
            $null = $server.Query("CREATE FUNCTION dbo.$udf1 (@a int) RETURNS TABLE AS RETURN (SELECT 1 a);", $dbname1)
            $null = $server.Query("CREATE FUNCTION dbo.$udf2 (@a int) RETURNS TABLE AS RETURN (SELECT 1 a);", $dbname1)
        }

        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance $server -Database $dbname1 -Confirm:$false
        }

        It "removes a user defined function" {
            Get-DbaDbUdf -SqlInstance $server -Database $dbname1 -Name $udf1 | Should -Not -BeNullOrEmpty
            Remove-DbaDbUdf -SqlInstance $server -Database $dbname1 -Name $udf1 -Confirm:$false
            Get-DbaDbUdf -SqlInstance $server -Database $dbname1 -Name $udf1 | Should -BeNullOrEmpty
        }

        It "supports piping user defined function" {
            Get-DbaDbUdf -SqlInstance $server -Database $dbname1 -Name $udf2 | Should -Not -BeNullOrEmpty
            Get-DbaDbUdf -SqlInstance $server -Database $dbname1 -Name $udf2 | Remove-DbaDbUdf -Confirm:$false
            Get-DbaDbUdf -SqlInstance $server -Database $dbname1 -Name $udf2 | Should -BeNullOrEmpty
        }
    }
}
