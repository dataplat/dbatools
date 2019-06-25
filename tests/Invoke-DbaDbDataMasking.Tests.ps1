$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'FilePath', 'Locale', 'CharacterString', 'Table', 'Column', 'ExcludeTable', 'ExcludeColumn', 'Query', 'MaxValue', 'ModulusFactor', 'ExactLength', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
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
        New-DbaDatabase -SqlInstance $script:instance2 -Name $db
        Invoke-DbaQuery -SqlInstance $script:instance2 -Database $db -Query $sql
    }

    AfterAll {
        Remove-DbaDatabase -SqlInstance $script:instance2 -Database $db -Confirm:$false
        $file | Remove-Item -Confirm:$false -ErrorAction Ignore
    }

    Context "Command works" {
        It "starts with the right data" {
            Invoke-DbaQuery -SqlInstance $script:instance2 -Database $db -Query "select * from people where fname = 'Joe'" | Should -Not -Be $null
            Invoke-DbaQuery -SqlInstance $script:instance2 -Database $db -Query "select * from people where lname = 'Schmee'" | Should -Not -Be $null
        }
        It "returns the proper output" {
            $file = New-DbaDbMaskingConfig -SqlInstance $script:instance2 -Database $db -Path C:\temp
            $results = $file | Invoke-DbaDbDataMasking -SqlInstance $script:instance2 -Database $db -Confirm:$false
            foreach ($result in $results) {
                $result.Rows | Should -Be 2
                $result.Database | Should -Contain $db
            }

        }
        It "masks the data and does not delete it" {
            Invoke-DbaQuery -SqlInstance $script:instance2 -Database $db -Query "select * from people" | Should -Not -Be $null
            Invoke-DbaQuery -SqlInstance $script:instance2 -Database $db -Query "select * from people where fname = 'Joe'" | Should -Be $null
            Invoke-DbaQuery -SqlInstance $script:instance2 -Database $db -Query "select * from people where lname = 'Schmee'" | Should -Be $null
        }
    }
}