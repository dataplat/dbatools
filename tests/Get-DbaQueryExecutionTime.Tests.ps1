param($ModuleName = 'dbatools')

Describe "Get-DbaQueryExecutionTime" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaQueryExecutionTime
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "MaxResultsPerDb",
                "MinExecs",
                "MinExecMs",
                "ExcludeSystem",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            # Run setup code to get script variables within scope of the discovery phase
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        Context "Connects and retrieves query execution times" -ForEach $global:instance1, $global:instance2 {
            BeforeAll {
                $server = Connect-DbaInstance -SqlInstance $_
            }

            It "Returns query execution times" {
                $results = Get-DbaQueryExecutionTime -SqlInstance $server -MaxResultsPerDb 5
                $results | Should -Not -BeNullOrEmpty
                $results.Count | Should -BeLessOrEqual 5
            }

            It "Respects the MinExecs parameter" {
                $minExecs = 2
                $results = Get-DbaQueryExecutionTime -SqlInstance $server -MinExecs $minExecs -MaxResultsPerDb 5
                $results | Should -Not -BeNullOrEmpty
                $results | ForEach-Object { $_.ExecutionCount | Should -BeGreaterOrEqual $minExecs }
            }

            It "Respects the MinExecMs parameter" {
                $minExecMs = 100
                $results = Get-DbaQueryExecutionTime -SqlInstance $server -MinExecMs $minExecMs -MaxResultsPerDb 5
                $results | Should -Not -BeNullOrEmpty
                $results | ForEach-Object { $_.AvgElapsedTime | Should -BeGreaterOrEqual $minExecMs }
            }

            It "Excludes system databases when ExcludeSystem is specified" {
                $results = Get-DbaQueryExecutionTime -SqlInstance $server -ExcludeSystem -MaxResultsPerDb 5
                $results | Should -Not -BeNullOrEmpty
                $results.Database | Should -Not -Contain @('master', 'model', 'msdb', 'tempdb')
            }
        }
    }
}
