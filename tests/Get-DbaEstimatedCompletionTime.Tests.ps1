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
        if ($script:bigDatabaseBackup) {
            try {
                if (-not (Test-Path -Path $script:bigDatabaseBackup) -and $script:bigDatabaseBackupSourceUrl) {
                    Invoke-WebRequest -Uri $script:bigDatabaseBackupSourceUrl -OutFile $script:bigDatabaseBackup -ErrorAction Stop
                }
                $null = Restore-DbaDatabase -SqlInstance $script:instance2 -Path $script:bigDatabaseBackup -DatabaseName checkdbTestDatabase -WithReplace -ReplaceDbNameInFile -EnableException
                $null = New-DbaAgentJob -SqlInstance $script:instance2 -Job checkdbTestJob -EnableException
                $null = New-DbaAgentJobStep -SqlInstance $script:instance2 -Job checkdbTestJob -StepName checkdb -Subsystem TransactSql -Command "DBCC CHECKDB('checkdbTestDatabase')" -EnableException
                $skip = $false
            } catch {
                Write-Information "Test for $commandname failed in BeforeAll because: $_"
            }
        }
    }

    AfterAll {
        $null = Get-DbaAgentJob -SqlInstance $script:instance2 -Job checkdbTestJob | Remove-DbaAgentJob -Confirm:$false
        $null = Get-DbaDatabase -SqlInstance $script:instance2 -Database checkdbTestDatabase | Remove-DbaDatabase -Confirm:$false
    }

    Context "Gets correct results" {
        It -Skip:$skip "Gets Query Estimated Completion" {
            $job = Start-DbaAgentJob -SqlInstance $script:instance2 -Job checkdbTestJob
            Start-Sleep -Seconds 1
            $results = Get-DbaEstimatedCompletionTime -SqlInstance $script:instance2
            while ($job.CurrentRunStatus -eq 'Executing') {
                Start-Sleep -Seconds 1
                $job.Refresh()
            }

            $results | Should -Not -BeNullOrEmpty
            $results.Command | Should -Match 'DBCC'
            $results.Database | Should -Be checkdbTestDatabase
        }

        It -Skip:$skip "Gets Query Estimated Completion when using -Database" {
            $job = Start-DbaAgentJob -SqlInstance $script:instance2 -Job checkdbTestJob
            Start-Sleep -Seconds 1
            $results = Get-DbaEstimatedCompletionTime -SqlInstance $script:instance2 -Database checkdbTestDatabase
            while ($job.CurrentRunStatus -eq 'Executing') {
                Start-Sleep -Seconds 1
                $job.Refresh()
            }

            $results | Should -Not -BeNullOrEmpty
            $results.Command | Should -Match 'DBCC'
            $results.Database | Should -Be checkdbTestDatabase
        }

        It -Skip:$skip "Gets no Query Estimated Completion when using -ExcludeDatabase" {
            $job = Start-DbaAgentJob -SqlInstance $script:instance2 -Job checkdbTestJob
            Start-Sleep -Seconds 1
            $results = Get-DbaEstimatedCompletionTime -SqlInstance $script:instance2 -ExcludeDatabase checkdbTestDatabase
            while ($job.CurrentRunStatus -eq 'Executing') {
                Start-Sleep -Seconds 1
                $job.Refresh()
            }

            $results | Should -BeNullOrEmpty
        }
    }
}