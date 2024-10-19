param($ModuleName = 'dbatools')

Describe "Get-DbaDbQueryStoreOption" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbQueryStoreOption
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    # Add more contexts here for integration tests
    # For example:
    # Context "Integration Tests" {
    #     BeforeAll {
    #         $server = Connect-DbaInstance -SqlInstance $global:instance2
    #         $randomDb = "dbatoolsci_$(Get-Random)"
    #         $server.Query("CREATE DATABASE $randomDb")
    #         $server.Query("ALTER DATABASE $randomDb SET QUERY_STORE = ON")
    #     }
    #
    #     AfterAll {
    #         $server.Query("DROP DATABASE $randomDb")
    #     }
    #
    #     It "Returns query store options" {
    #         $results = Get-DbaDbQueryStoreOption -SqlInstance $global:instance2 -Database $randomDb
    #         $results | Should -Not -BeNullOrEmpty
    #         $results.Database | Should -Be $randomDb
    #         $results.ActualState | Should -Be "ReadWrite"
    #     }
    # }
}
