$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $CommandName = "Invoke-DbaDbDataMasking"
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance',
        'SqlCredential',
        'Database',
        'FilePath',
        'Locale',
        'CharacterString',
        'Table',
        'Column',
        'ExcludeTable',
        'ExcludeColumn',
        'MaxValue',
        'ModulusFactor',
        'ExactLength',
        'CommandTimeout',
        'BatchSize',
        'Retry',
        'DictionaryFilePath',
        'DictionaryExportPath',
        'EnableException'

        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $db = "dbatoolsci_masker"
        $sql = "CREATE TABLE [dbo].[people](
                    [fname] [varchar](50) NULL,
                    [lname] [varchar](50) NULL,
                    [dob] [datetime] NULL,
                    [percenttest] [decimal](15,3) NULL,
                    [bittest] bit NULL
                ) ON [PRIMARY]
                GO
                INSERT INTO people (fname, lname, dob, percenttest,bittest) VALUES ('Joe','Schmoe','2/2/2000',29.53,1)
                INSERT INTO people (fname, lname, dob, percenttest,bittest) VALUES ('Jane','Schmee','2/2/1950',65.38,0)
                GO
                CREATE TABLE [dbo].[people2](
                                    [fname] [varchar](50) NULL,
                                    [lname] [varchar](50) NULL,
                                    [dob] [datetime] NULL,
                                    [percenttest] [decimal](15,3) NULL,
                                    [bittest] bit NULL
                                ) ON [PRIMARY]
                GO
                INSERT INTO people2 (fname, lname, dob, percenttest,bittest) VALUES ('Layla','Schmoe','2/2/2000',29.53,1)
                INSERT INTO people2 (fname, lname, dob, percenttest,bittest) VALUES ('Eric','Schmee','2/2/1950',65.38,0)"
        New-DbaDatabase -SqlInstance $TestConfig.instance2 -SqlCredential $TestConfig.SqlCredential -Name $db
        Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -SqlCredential $TestConfig.SqlCredential -Database $db -Query $sql
    }

    AfterAll {
        Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -SqlCredential $TestConfig.SqlCredential -Database $db -Confirm:$false
        $file | Remove-Item -Confirm:$false -ErrorAction Ignore
    }

    Context "Command works" {
        It "starts with the right data" {
            Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -SqlCredential $TestConfig.SqlCredential -Database $db -Query "select * from people where fname = 'Joe'" | Should -Not -Be $null
            Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -SqlCredential $TestConfig.SqlCredential -Database $db -Query "select * from people where lname = 'Schmee'" | Should -Not -Be $null
            Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -SqlCredential $TestConfig.SqlCredential -Database $db -Query "select * from people where percenttest = 29.53" | Should -Not -Be $null
            Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -SqlCredential $TestConfig.SqlCredential -Database $db -Query "select * from people where percenttest = 65.38" | Should -Not -Be $null
            Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -SqlCredential $TestConfig.SqlCredential -Database $db -Query "select * from people where bittest = 1 AND lname = 'Schmoe'" | Should -Not -Be $null
            Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -SqlCredential $TestConfig.SqlCredential -Database $db -Query "select * from people where bittest = 0 AND lname = 'Schmee'" | Should -Not -Be $null
        }
        It "returns the proper output" {
            $file = New-DbaDbMaskingConfig -SqlInstance $TestConfig.instance2 -SqlCredential $TestConfig.SqlCredential -Database $db -Path C:\temp

            [array]$results = $file | Invoke-DbaDbDataMasking -SqlInstance $TestConfig.instance2 -SqlCredential $TestConfig.SqlCredential -Database $db -Confirm:$false
            Remove-Item -Path $file.FullName

            $results[0].Rows | Should -Be 2
            $results[0].Database | Should -Contain $db

            $results[1].Rows | Should -Be 2
            $results[1].Database | Should -Contain $db
        }

        It "masks the data and does not delete it" {
            Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -SqlCredential $TestConfig.SqlCredential -Database $db -Query "select * from people" | Should -Not -Be $null
            Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -SqlCredential $TestConfig.SqlCredential -Database $db -Query "select * from people where fname = 'Joe'" | Should -Be $null
            Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -SqlCredential $TestConfig.SqlCredential -Database $db -Query "select * from people where lname = 'Schmee'" | Should -Be $null
            Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -SqlCredential $TestConfig.SqlCredential -Database $db -Query "select * from people where percenttest = 29.53" | Should -Be $null
            Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -SqlCredential $TestConfig.SqlCredential -Database $db -Query "select * from people where percenttest = 65.38" | Should -Be $null
            Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -SqlCredential $TestConfig.SqlCredential -Database $db -Query "select * from people where bittest = 1 AND lname = 'Schmoe'" | Should -Be $null
            Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -SqlCredential $TestConfig.SqlCredential -Database $db -Query "select * from people where bittest = 0 AND lname = 'Schmee'" | Should -Be $null
        }
    }
}
