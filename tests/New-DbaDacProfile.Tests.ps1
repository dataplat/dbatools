param($ModuleName = 'dbatools')

Describe "New-DbaDacProfile" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaDacProfile
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[]
        }
        It "Should have Path as a parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type String
        }
        It "Should have ConnectionString as a parameter" {
            $CommandUnderTest | Should -HaveParameter ConnectionString -Type String[]
        }
        It "Should have PublishOptions as a parameter" {
            $CommandUnderTest | Should -HaveParameter PublishOptions -Type Hashtable
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            $dbname = "dbatoolsci_publishprofile"
            $db = New-DbaDatabase -SqlInstance $global:instance1 -Name $dbname
            $null = $db.Query("CREATE TABLE dbo.example (id int);
                INSERT dbo.example
                SELECT top 100 1
                FROM sys.objects")
        }
        AfterAll {
            Remove-DbaDatabase -SqlInstance $global:instance1 -Database $dbname -Confirm:$false
        }

        It "returns the right results" {
            $publishprofile = New-DbaDacProfile -SqlInstance $global:instance1 -Database $dbname
            $publishprofile.FileName | Should -Match 'publish.xml'
            Remove-Item -Confirm:$false -Path $publishprofile.FileName -ErrorAction SilentlyContinue
        }
    }
}
