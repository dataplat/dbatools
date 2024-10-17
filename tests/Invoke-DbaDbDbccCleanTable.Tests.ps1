param($ModuleName = 'dbatools')

Describe "Invoke-DbaDbDbccCleanTable" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Invoke-DbaDbDbccCleanTable
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[] -Not -Mandatory
        }
        It "Should have Object parameter" {
            $CommandUnderTest | Should -HaveParameter Object -Type String[] -Not -Mandatory
        }
        It "Should have BatchSize parameter" {
            $CommandUnderTest | Should -HaveParameter BatchSize -Type Int32 -Not -Mandatory
        }
        It "Should have NoInformationalMessages parameter" {
            $CommandUnderTest | Should -HaveParameter NoInformationalMessages -Type SwitchParameter -Not -Mandatory
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter -Not -Mandatory
        }
    }

    Context "Command usage" {
        BeforeAll {
            . (Join-Path $PSScriptRoot 'constants.ps1')
            $db = Get-DbaDatabase -SqlInstance $script:instance1 -Database tempdb
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
                $result = Invoke-DbaDbDbccCleanTable -SqlInstance $script:instance1 -Database 'tempdb' -Object 'dbo.dbatoolct_example' -Confirm:$false
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
                $result = Invoke-DbaDbDbccCleanTable -SqlInstance $script:instance1 -Database 'tempdb' -Object 'dbo.dbatoolct_example' -BatchSize 1000 -Confirm:$false
            }
            It "Returns results for table" {
                $result.Cmd | Should -Be "DBCC CLEANTABLE('tempdb', 'dbo.dbatoolct_example', 1000)"
                $result.Output.Substring(0, 25) | Should -Be 'DBCC execution completed.'
            }
        }

        Context "Validate NoInformationalMessages parameter" {
            BeforeAll {
                $result = Invoke-DbaDbDbccCleanTable -SqlInstance $script:instance1 -Database 'tempdb' -Object 'dbo.dbatoolct_example' -NoInformationalMessages -Confirm:$false
            }
            It "Returns results for table" {
                $result.Cmd | Should -Be "DBCC CLEANTABLE('tempdb', 'dbo.dbatoolct_example') WITH NO_INFOMSGS"
                $result.Output | Should -BeNullOrEmpty
            }
        }
    }
}
