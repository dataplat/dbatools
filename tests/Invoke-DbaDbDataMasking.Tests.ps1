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
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Database",
            "FilePath",
            "Locale",
            "CharacterString",
            "Table",
            "Column",
            "ExcludeTable",
            "ExcludeColumn",
            "MaxValue",
            "ModulusFactor",
            "ExactLength",
            "CommandTimeout",
            "BatchSize",
            "Retry",
            "DictionaryFilePath",
            "DictionaryExportPath",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
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
