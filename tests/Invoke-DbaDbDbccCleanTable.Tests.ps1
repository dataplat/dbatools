param($ModuleName = 'dbatools')

Describe "Invoke-DbaDbDbccCleanTable" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Invoke-DbaDbDbccCleanTable
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have Object parameter" {
            $CommandUnderTest | Should -HaveParameter Object
        }
        It "Should have BatchSize parameter" {
            $CommandUnderTest | Should -HaveParameter BatchSize
        }
        It "Should have NoInformationalMessages parameter" {
            $CommandUnderTest | Should -HaveParameter NoInformationalMessages
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command usage" {
        BeforeAll {
            . (Join-Path $PSScriptRoot 'constants.ps1')
            $db = Get-DbaDatabase -SqlInstance $global:instance1 -Database tempdb
            $null = $db.Query("CREATE TABLE dbo.dbatoolct_example (object_id int, [definition] nvarchar(max),Document varchar(2000));
            INSERT INTO dbo.dbatoolct_example([object_id], [definition], Document) Select [object_id], [definition], REPLICATE('ab', 800) from master.sys.sql_modules;
            ALTER TABLE dbo.dbatoolct_example DROP COLUMN Definition, Document;")
        }
        AfterAll {
            try {
                $null = $db.Query("DROP TABLE dbo.dbatoolct_example")
            } catch {
                $null = 1
            }
        }

        Context "Validate standard output" {
            BeforeAll {
                $props = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Object', 'Cmd', 'Output'
                $result = Invoke-DbaDbDbccCleanTable -SqlInstance $global:instance1 -Database 'tempdb' -Object 'dbo.dbatoolct_example' -Confirm:$false
            }
            It "Should return property: <_>" -ForEach $props {
                $result[0].PSObject.Properties[$_] | Should -Not -BeNullOrEmpty
            }
            It "Returns correct results" {
                $result.Database | Should -Be 'tempdb'
                $result.Object | Should -Be 'dbo.dbatoolct_example'
                $result.Output.Substring(0, 25) | Should -Be 'DBCC execution completed.'
            }
        }

        Context "Validate BatchSize parameter" {
            BeforeAll {
                $result = Invoke-DbaDbDbccCleanTable -SqlInstance $global:instance1 -Database 'tempdb' -Object 'dbo.dbatoolct_example' -BatchSize 1000 -Confirm:$false
            }
            It "Returns results for table" {
                $result.Cmd | Should -Be "DBCC CLEANTABLE('tempdb', 'dbo.dbatoolct_example', 1000)"
                $result.Output.Substring(0, 25) | Should -Be 'DBCC execution completed.'
            }
        }

        Context "Validate NoInformationalMessages parameter" {
            BeforeAll {
                $result = Invoke-DbaDbDbccCleanTable -SqlInstance $global:instance1 -Database 'tempdb' -Object 'dbo.dbatoolct_example' -NoInformationalMessages -Confirm:$false
            }
            It "Returns results for table" {
                $result.Cmd | Should -Be "DBCC CLEANTABLE('tempdb', 'dbo.dbatoolct_example') WITH NO_INFOMSGS"
                $result.Output | Should -BeNullOrEmpty
            }
        }
    }
}
