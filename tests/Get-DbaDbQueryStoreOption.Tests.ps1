param($ModuleName = 'dbatools')

Describe "Get-DbaDbQueryStoreOption" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbQueryStoreOption
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[]
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type Object[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
        It "Should have Verbose as a parameter" {
            $CommandUnderTest | Should -HaveParameter Verbose -Type Switch
        }
        It "Should have Debug as a parameter" {
            $CommandUnderTest | Should -HaveParameter Debug -Type Switch
        }
        It "Should have ErrorAction as a parameter" {
            $CommandUnderTest | Should -HaveParameter ErrorAction -Type ActionPreference
        }
        It "Should have WarningAction as a parameter" {
            $CommandUnderTest | Should -HaveParameter WarningAction -Type ActionPreference
        }
        It "Should have InformationAction as a parameter" {
            $CommandUnderTest | Should -HaveParameter InformationAction -Type ActionPreference
        }
        It "Should have ProgressAction as a parameter" {
            $CommandUnderTest | Should -HaveParameter ProgressAction -Type ActionPreference
        }
        It "Should have ErrorVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter ErrorVariable -Type String
        }
        It "Should have WarningVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter WarningVariable -Type String
        }
        It "Should have InformationVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter InformationVariable -Type String
        }
        It "Should have OutVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter OutVariable -Type String
        }
        It "Should have OutBuffer as a parameter" {
            $CommandUnderTest | Should -HaveParameter OutBuffer -Type Int32
        }
        It "Should have PipelineVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter PipelineVariable -Type String
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
