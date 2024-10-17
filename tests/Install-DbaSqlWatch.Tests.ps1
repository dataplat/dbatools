param($ModuleName = 'dbatools')

Describe "Install-DbaSqlWatch" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Install-DbaSqlWatch
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String
        }
        It "Should have LocalFile as a parameter" {
            $CommandUnderTest | Should -HaveParameter LocalFile -Type String
        }
        It "Should have PreRelease as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter PreRelease -Type SwitchParameter
        }
        It "Should have Force as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type SwitchParameter
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }

    Context "Testing SqlWatch installer" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        BeforeAll {
            $database = "dbatoolsci_sqlwatch_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $server.Query("CREATE DATABASE $database")
        }
        AfterAll {
            Uninstall-DbaSqlWatch -SqlInstance $script:instance2 -Database $database
            Remove-DbaDatabase -SqlInstance $script:instance2 -Database $database -Confirm:$false
        }

        It "Installs to specified database: <database>" {
            $results = Install-DbaSqlWatch -SqlInstance $script:instance2 -Database $database
            $results[0].Database | Should -Be $database
        }

        It "Returns an object with the expected properties" {
            $results = Install-DbaSqlWatch -SqlInstance $script:instance2 -Database $database
            $result = $results[0]
            $ExpectedProps = 'SqlInstance', 'InstanceName', 'ComputerName', 'Database', 'Status', 'DashboardPath'
            $result.PsObject.Properties.Name | Should -Be $ExpectedProps
        }

        It "Installed tables" {
            $tableCount = (Get-DbaDbTable -SqlInstance $script:instance2 -Database $database | Where-Object { $_.Name -like "sqlwatch_*" }).Count
            $tableCount | Should -BeGreaterThan 0
        }

        It "Installed views" {
            $viewCount = (Get-DbaDbView -SqlInstance $script:instance2 -Database $database | Where-Object { $_.Name -like "vw_sqlwatch_*" }).Count
            $viewCount | Should -BeGreaterThan 0
        }

        It "Installed stored procedures" {
            $sprocCount = (Get-DbaDbStoredProcedure -SqlInstance $script:instance2 -Database $database | Where-Object { $_.Name -like "usp_sqlwatch_*" }).Count
            $sprocCount | Should -BeGreaterThan 0
        }

        It "Installed SQL Agent jobs" {
            $agentCount = (Get-DbaAgentJob -SqlInstance $script:instance2 | Where-Object { ($_.Name -like "SqlWatch-*") -or ($_.Name -like "DBA-PERF-*") }).Count
            $agentCount | Should -BeGreaterThan 0
        }
    }
}
