param($ModuleName = 'dbatools')

Describe "Get-DbaDbCompression" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbCompression
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[] -Not -Mandatory
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type String[] -Not -Mandatory
        }
        It "Should have Table as a parameter" {
            $CommandUnderTest | Should -HaveParameter Table -Type String[] -Not -Mandatory
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter -Not -Mandatory
        }
    }

    Context "Command usage" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $dbname = "dbatoolsci_test_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $null = $server.Query("Create Database [$dbname]")
            $null = $server.Query("select * into syscols from sys.all_columns
                                    select * into sysallparams from sys.all_parameters
                                    create clustered index CL_sysallparams on sysallparams (object_id)
                                    create nonclustered index NC_syscols on syscols (precision) include (collation_name)", $dbname)
        }
        AfterAll {
            Get-DbaProcess -SqlInstance $script:instance2 -Database $dbname | Stop-DbaProcess -WarningAction SilentlyContinue
            Remove-DbaDatabase -SqlInstance $script:instance2 -Database $dbname -Confirm:$false
        }

        Context "Command handles heaps and clustered indexes" {
            BeforeAll {
                $results = Get-DbaDbCompression -SqlInstance $script:instance2 -Database $dbname
            }
            It "Gets results" {
                $results | Should -Not -BeNullOrEmpty
                $results.Database | Get-Unique | Should -Be $dbname
                $results.DatabaseId | Get-Unique | Should -Be $server.Query("SELECT database_id FROM sys.databases WHERE name = '$dbname'").database_id
            }
            It "Should return compression level for object <TableName>" -ForEach @(
                @{ TableName = 'syscols' }
                @{ TableName = 'sysallparams' }
            ) {
                $row = $results | Where-Object { $_.IndexId -le 1 -and $_.TableName -eq $TableName }
                $row.DataCompression | Should -BeIn ('None', 'Row', 'Page')
            }
        }

        Context "Command handles nonclustered indexes" {
            BeforeAll {
                $results = Get-DbaDbCompression -SqlInstance $script:instance2 -Database $dbname
            }
            It "Gets results" {
                $results | Should -Not -BeNullOrEmpty
            }
            It "Should return compression level for nonclustered index <IndexName>" -ForEach @(
                @{ IndexName = 'NC_syscols' }
            ) {
                $row = $results | Where-Object { $_.IndexId -gt 1 -and $_.IndexName -eq $IndexName }
                $row.DataCompression | Should -BeIn ('None', 'Row', 'Page')
            }
        }

        Context "Command excludes results for specified database" {
            It "Shouldn't get any results for $dbname" {
                $result = Get-DbaDbCompression -SqlInstance $script:instance2 -Database $dbname -ExcludeDatabase $dbname
                $result | Should -Not -Contain $dbname
            }
        }
    }
}
