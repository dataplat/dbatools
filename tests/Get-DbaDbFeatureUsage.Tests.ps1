param($ModuleName = 'dbatools')

Describe "Get-DbaDbFeatureUsage" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbFeatureUsage
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Database",
            "ExcludeDatabase",
            "InputObject",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            # Run setup code to get script variables within scope of the discovery phase
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        BeforeAll {
            $dbname = "dbatoolsci_test_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $server.Query("Create Database [$dbname]")
            $server.Query("Create Table [$dbname].dbo.TestCompression
                (Column1 nvarchar(10),
                Column2 int PRIMARY KEY,
                Column3 nvarchar(18));")
            $server.Query("ALTER TABLE [$dbname].dbo.TestCompression REBUILD PARTITION = ALL WITH (DATA_COMPRESSION = ROW);")
        }

        AfterAll {
            $server.Query("DROP Database [$dbname]")
        }

        It "Gets Feature Usage" {
            $results = Get-DbaDbFeatureUsage -SqlInstance $global:instance2
            $results | Should -Not -BeNullOrEmpty
        }

        It "Gets Feature Usage using -Database" {
            $results = Get-DbaDbFeatureUsage -SqlInstance $global:instance2 -Database $dbname
            $results | Should -Not -BeNullOrEmpty
            $results.Feature | Should -Be "Compression"
        }

        It "Gets Feature Usage using -ExcludeDatabase" {
            $results = Get-DbaDbFeatureUsage -SqlInstance $global:instance2 -ExcludeDatabase $dbname
            $results.database | Should -Not -Contain $dbname
        }
    }
}
