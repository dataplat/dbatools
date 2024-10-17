param($ModuleName = 'dbatools')

Describe "Get-DbaDbStoredProcedure Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbStoredProcedure
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Database as a non-mandatory parameter of type Object[]" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[] -Not -Mandatory
        }
        It "Should have ExcludeDatabase as a non-mandatory parameter of type Object[]" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type Object[] -Not -Mandatory
        }
        It "Should have ExcludeSystemSp as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeSystemSp -Type Switch -Not -Mandatory
        }
        It "Should have Name as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Name -Type String[] -Not -Mandatory
        }
        It "Should have Schema as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Schema -Type String[] -Not -Mandatory
        }
        It "Should have InputObject as a non-mandatory parameter of type Database[]" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Database[] -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }
}

Describe "Get-DbaDbStoredProcedure Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $random = Get-Random
        $db1Name = "dbatoolsci_$random"
        $db1 = New-DbaDatabase -SqlInstance $server -Name $db1Name
        $procName = "proc1"
        $db1.Query("CREATE PROCEDURE $procName AS SELECT 1")

        $schemaName = "schema1"
        $procName2 = "proc2"
        $db1.Query("CREATE SCHEMA $schemaName")
        $db1.Query("CREATE PROCEDURE $schemaName.$procName2 AS SELECT 1")
    }

    AfterAll {
        $db1 | Remove-DbaDatabase -Confirm:$false
    }

    Context "Command actually works" {
        It "Should have standard properties" {
            $results = Get-DbaDbStoredProcedure -SqlInstance $script:instance2 -Database $db1Name
            $ExpectedProps = 'ComputerName', 'InstanceName', 'SqlInstance'
            $results[0].PsObject.Properties.Name | Should -Contain $ExpectedProps
        }

        It "Should get test procedure: $procName" {
            $results = Get-DbaDbStoredProcedure -SqlInstance $script:instance2 -Database $db1Name
            $results | Where-Object Name -eq $procName | Should -Not -BeNullOrEmpty
        }

        It "Should include system procedures" {
            $results = Get-DbaDbStoredProcedure -SqlInstance $script:instance2 -Database $db1Name
            $results | Where-Object Name -eq 'sp_columns' | Should -Not -BeNullOrEmpty
        }
    }

    Context "Exclusions work correctly" {
        It "Should contain no procs from master database" {
            $results = Get-DbaDbStoredProcedure -SqlInstance $script:instance2 -ExcludeDatabase master
            $results.Database | Should -Not -Contain 'master'
        }

        It "Should exclude system procedures" {
            $results = Get-DbaDbStoredProcedure -SqlInstance $script:instance2 -Database $db1Name -ExcludeSystemSp
            $results | Where-Object Name -eq 'sp_helpdb' | Should -BeNullOrEmpty
        }
    }

    Context "Piping works" {
        It "Should allow piping from string" {
            $results = $script:instance2 | Get-DbaDbStoredProcedure -Database $db1Name
            $results | Where-Object Name -eq $procName | Should -Not -BeNullOrEmpty
        }

        It "Should allow piping from Get-DbaDatabase" {
            $results = Get-DbaDatabase -SqlInstance $script:instance2 -Database $db1Name | Get-DbaDbStoredProcedure
            $results | Where-Object Name -eq $procName | Should -Not -BeNullOrEmpty
        }
    }

    Context "Search by name and schema" {
        It "Search by name" {
            $results = $script:instance2 | Get-DbaDbStoredProcedure -Database $db1Name -Name $procName
            $results.Name | Should -Be $procName
            $results.DatabaseId | Should -Be $db1.Id
        }

        It "Search by 2 part name" {
            $results = $script:instance2 | Get-DbaDbStoredProcedure -Database $db1Name -Name "$schemaName.$procName2"
            $results.Name | Should -Be $procName2
            $results.Schema | Should -Be $schemaName
        }

        It "Search by 3 part name and omit the -Database param" {
            $results = $script:instance2 | Get-DbaDbStoredProcedure -Name "$db1Name.$schemaName.$procName2"
            $results.Name | Should -Be $procName2
            $results.Schema | Should -Be $schemaName
            $results.Database | Should -Be $db1Name
        }

        It "Search by name and schema params" {
            $results = $script:instance2 | Get-DbaDbStoredProcedure -Database $db1Name -Name $procName2 -Schema $schemaName
            $results.Name | Should -Be $procName2
            $results.Schema | Should -Be $schemaName
        }

        It "Search by schema name" {
            $results = $script:instance2 | Get-DbaDbStoredProcedure -Database $db1Name -Schema $schemaName
            $results.Name | Should -Be $procName2
            $results.Schema | Should -Be $schemaName
        }
    }
}
