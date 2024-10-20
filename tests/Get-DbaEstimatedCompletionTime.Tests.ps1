$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {

    BeforeAll {
        $skip = $true
        if ($TestConfig.bigDatabaseBackup) {
            try {
                if (-not (Test-Path -Path $TestConfig.bigDatabaseBackup) -and $TestConfig.bigDatabaseBackupSourceUrl) {
                    Invoke-WebRequest -Uri $TestConfig.bigDatabaseBackupSourceUrl -OutFile $TestConfig.bigDatabaseBackup -ErrorAction Stop
                }
                $null = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path $TestConfig.bigDatabaseBackup -DatabaseName checkdbTestDatabase -WithReplace -ReplaceDbNameInFile -EnableException
                $null = New-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job checkdbTestJob -EnableException
                $null = New-DbaAgentJobStep -SqlInstance $TestConfig.instance2 -Job checkdbTestJob -StepName checkdb -Subsystem TransactSql -Command "DBCC CHECKDB('checkdbTestDatabase')" -EnableException
                $skip = $false
            } catch {
                Write-Host -Object "Test for $CommandName failed in BeforeAll because: $_" -ForegroundColor Cyan
            }
        }
    }

    AfterAll {
        $null = Get-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job checkdbTestJob | Remove-DbaAgentJob -Confirm:$false
        $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database checkdbTestDatabase | Remove-DbaDatabase -Confirm:$false
    }

    Context "Gets correct results" {
        It -Skip:$skip "Gets Query Estimated Completion" {
            $job = Start-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job checkdbTestJob
            Start-Sleep -Seconds 1
            $results = Get-DbaEstimatedCompletionTime -SqlInstance $TestConfig.instance2
            while ($job.CurrentRunStatus -eq 'Executing') {
                Start-Sleep -Seconds 1
                $job.Refresh()
            }

            $results | Should -Not -BeNullOrEmpty
            $results.Command | Should -Match 'DBCC'
            $results.Database | Should -Be checkdbTestDatabase
        }

        It -Skip:$skip "Gets Query Estimated Completion when using -Database" {
            $job = Start-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job checkdbTestJob
            Start-Sleep -Seconds 1
            $results = Get-DbaEstimatedCompletionTime -SqlInstance $TestConfig.instance2 -Database checkdbTestDatabase
            while ($job.CurrentRunStatus -eq 'Executing') {
                Start-Sleep -Seconds 1
                $job.Refresh()
            }

            $results | Should -Not -BeNullOrEmpty
            $results.Command | Should -Match 'DBCC'
            $results.Database | Should -Be checkdbTestDatabase
        }

        It -Skip:$skip "Gets no Query Estimated Completion when using -ExcludeDatabase" {
            $job = Start-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job checkdbTestJob
            Start-Sleep -Seconds 1
            $results = Get-DbaEstimatedCompletionTime -SqlInstance $TestConfig.instance2 -ExcludeDatabase checkdbTestDatabase
            while ($job.CurrentRunStatus -eq 'Executing') {
                Start-Sleep -Seconds 1
                $job.Refresh()
            }

            $results | Should -BeNullOrEmpty
        }
    }
}
