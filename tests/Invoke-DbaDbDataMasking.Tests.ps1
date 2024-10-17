param($ModuleName = 'dbatools')

Describe "Invoke-DbaDbDataMasking" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $db = "dbatoolsci_masker"
        $sql = "CREATE TABLE [dbo].[people](
                    [fname] [varchar](50) NULL,
                    [lname] [varchar](50) NULL,
                    [dob] [datetime] NULL
                ) ON [PRIMARY]
                GO
                INSERT INTO people (fname, lname, dob) VALUES ('Joe','Schmoe','2/2/2000')
                INSERT INTO people (fname, lname, dob) VALUES ('Jane','Schmee','2/2/1950')
                GO
                CREATE TABLE [dbo].[people2](
                                    [fname] [varchar](50) NULL,
                                    [lname] [varchar](50) NULL,
                                    [dob] [datetime] NULL
                                ) ON [PRIMARY]
                GO
                INSERT INTO people2 (fname, lname, dob) VALUES ('Layla','Schmoe','2/2/2000')
                INSERT INTO people2 (fname, lname, dob) VALUES ('Eric','Schmee','2/2/1950')"
        New-DbaDatabase -SqlInstance $global:instance2 -SqlCredential $env:SqlCredential -Name $db
        Invoke-DbaQuery -SqlInstance $global:instance2 -SqlCredential $env:SqlCredential -Database $db -Query $sql
    }

    AfterAll {
        Remove-DbaDatabase -SqlInstance $global:instance2 -SqlCredential $env:SqlCredential -Database $db -Confirm:$false
        $file | Remove-Item -Confirm:$false -ErrorAction Ignore
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Invoke-DbaDbDataMasking
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
        It "Should have FilePath as a parameter" {
            $CommandUnderTest | Should -HaveParameter FilePath -Type Object
        }
        It "Should have Locale as a parameter" {
            $CommandUnderTest | Should -HaveParameter Locale -Type String
        }
        It "Should have CharacterString as a parameter" {
            $CommandUnderTest | Should -HaveParameter CharacterString -Type String
        }
        It "Should have Table as a parameter" {
            $CommandUnderTest | Should -HaveParameter Table -Type String[]
        }
        It "Should have Column as a parameter" {
            $CommandUnderTest | Should -HaveParameter Column -Type String[]
        }
        It "Should have ExcludeTable as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeTable -Type String[]
        }
        It "Should have ExcludeColumn as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeColumn -Type String[]
        }
        It "Should have MaxValue as a parameter" {
            $CommandUnderTest | Should -HaveParameter MaxValue -Type Int32
        }
        It "Should have ModulusFactor as a parameter" {
            $CommandUnderTest | Should -HaveParameter ModulusFactor -Type Int32
        }
        It "Should have ExactLength as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExactLength -Type Switch
        }
        It "Should have CommandTimeout as a parameter" {
            $CommandUnderTest | Should -HaveParameter CommandTimeout -Type Int32
        }
        It "Should have BatchSize as a parameter" {
            $CommandUnderTest | Should -HaveParameter BatchSize -Type Int32
        }
        It "Should have Retry as a parameter" {
            $CommandUnderTest | Should -HaveParameter Retry -Type Int32
        }
        It "Should have DictionaryFilePath as a parameter" {
            $CommandUnderTest | Should -HaveParameter DictionaryFilePath -Type String[]
        }
        It "Should have DictionaryExportPath as a parameter" {
            $CommandUnderTest | Should -HaveParameter DictionaryExportPath -Type String
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Command works" {
        It "starts with the right data" {
            $query = "select * from people where fname = 'Joe'"
            $result = Invoke-DbaQuery -SqlInstance $global:instance2 -SqlCredential $env:SqlCredential -Database $db -Query $query
            $result | Should -Not -BeNullOrEmpty
        }

        It "starts with the right data (lname)" {
            $query = "select * from people where lname = 'Schmee'"
            $result = Invoke-DbaQuery -SqlInstance $global:instance2 -SqlCredential $env:SqlCredential -Database $db -Query $query
            $result | Should -Not -BeNullOrEmpty
        }

        It "returns the proper output" {
            $file = New-DbaDbMaskingConfig -SqlInstance $global:instance2 -SqlCredential $env:SqlCredential -Database $db -Path C:\temp

            [array]$results = $file | Invoke-DbaDbDataMasking -SqlInstance $global:instance2 -SqlCredential $env:SqlCredential -Database $db -Confirm:$false

            $results[0].Rows | Should -Be 2
            $results[0].Database | Should -Contain $db

            $results[1].Rows | Should -Be 2
            $results[1].Database | Should -Contain $db
        }

        It "masks the data and does not delete it" {
            $query1 = "select * from people"
            $result1 = Invoke-DbaQuery -SqlInstance $global:instance2 -SqlCredential $env:SqlCredential -Database $db -Query $query1
            $result1 | Should -Not -BeNullOrEmpty

            $query2 = "select * from people where fname = 'Joe'"
            $result2 = Invoke-DbaQuery -SqlInstance $global:instance2 -SqlCredential $env:SqlCredential -Database $db -Query $query2
            $result2 | Should -BeNullOrEmpty

            $query3 = "select * from people where lname = 'Schmee'"
            $result3 = Invoke-DbaQuery -SqlInstance $global:instance2 -SqlCredential $env:SqlCredential -Database $db -Query $query3
            $result3 | Should -BeNullOrEmpty
        }
    }
}
