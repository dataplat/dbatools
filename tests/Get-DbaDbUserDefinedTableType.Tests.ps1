param($ModuleName = 'dbatools')

Describe "Get-DbaDbUserDefinedTableType" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbUserDefinedTableType
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "Type",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command usage" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $tabletypename = ("dbatools_{0}" -f $(Get-Random))
            $tabletypename1 = ("dbatools_{0}" -f $(Get-Random))
            $server.Query("CREATE TYPE $tabletypename AS TABLE([column1] INT NULL)", 'tempdb')
            $server.Query("CREATE TYPE $tabletypename1 AS TABLE([column1] INT NULL)", 'tempdb')
        }
        AfterAll {
            $null = $server.Query("DROP TYPE $tabletypename", 'tempdb')
            $null = $server.Query("DROP TYPE $tabletypename1", 'tempdb')
        }

        Context "Gets a Db User Defined Table Type" {
            BeforeAll {
                $results = Get-DbaDbUserDefinedTableType -SqlInstance $global:instance2 -Database tempdb -Type $tabletypename
            }
            It "Gets results" {
                $results | Should -Not -BeNullOrEmpty
            }
            It "Should have a name of $tabletypename" {
                $results.Name | Should -Be "$tabletypename"
            }
            It "Should have an owner of dbo" {
                $results.Owner | Should -Be "dbo"
            }
            It "Should have a count of 1" {
                $results | Should -HaveCount 1
            }
        }

        Context "Gets all the Db User Defined Table Type" {
            BeforeAll {
                $results = Get-DbaDbUserDefinedTableType -SqlInstance $global:instance2 -Database tempdb
            }
            It "Gets results" {
                $results | Should -Not -BeNullOrEmpty
            }
            It "Should have a count of 2" {
                $results | Should -HaveCount 2
            }
        }
    }
}
