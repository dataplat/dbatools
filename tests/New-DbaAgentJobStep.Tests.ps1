$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Job', 'StepId', 'StepName', 'Subsystem', 'SubsystemServer', 'Command', 'CmdExecSuccessCode', 'OnSuccessAction', 'OnSuccessStepId', 'OnFailAction', 'OnFailStepId', 'Database', 'DatabaseUser', 'RetryAttempts', 'RetryInterval', 'OutputFileName', 'Insert', 'Flag', 'ProxyName', 'Force', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "New Agent Job Step is added properly" {
        AfterAll {
            Remove-DbaAgentJob -SqlInstance $script:instance2 -Job "dbatoolsci Job One","dbatoolsci Job Two"
        }
        # Create job to add step to
        $job = New-DbaAgentJob -SqlInstance $script:instance2 -Job "dbatoolsci Job One" -Description "Just another job"
        $jobTwo = New-DbaAgentJob -SqlInstance $script:instance2 -Job "dbatoolsci Job Two" -Description "Just another job"

        It "Should have the right name and description" {
            $results = New-DbaAgentJobStep -SqlInstance $script:instance2 -Job $job -StepName "Step One"
            $results.Name | Should -Be "Step One"
        }

        It "Should have the right properties" {
            $jobStep = @{
                SqlInstance = $script:instance2
                Job = $jobTwo
                StepName = "Step X"
                Subsystem = "TransactSql"
                Command = "select 1"
                Database = "master"
                RetryAttempts = 2
                RetryInterval = 5
                OutputFileName = "log.txt"
            }
            $results = New-DbaAgentJobStep @jobStep
            $results.Name | Should -Be "Step X"
            $results.Subsystem | Should -Be "TransactSql"
            $results.Command | Should -Be "Select 1"
            $results.DatabaseName | Should -Be "master"
            $results.RetryAttempts | Should -Be 2
            $results.RetryInterval | Should -Be 5
            $results.OutputFileName | Should -Be "log.txt"
        }


        It "Should actually for sure exist" {
            $newresults = Get-DbaAgentJob -SqlInstance $script:instance2 -Job "dbatoolsci Job One"
            $newresults.JobSteps.Name | Should -Be "Step One"
        }

        It "Should not write over existing job steps" {
            New-DbaAgentJobStep -SqlInstance $script:instance2 -Job "dbatoolsci Job One" -StepName "Step One" -WarningAction SilentlyContinue -WarningVariable warn
            $warn -match "already exists" | Should -Be $true
            $newresults = Get-DbaAgentJob -SqlInstance $script:instance2 -Job "dbatoolsci Job One"
            $newresults.JobSteps.Name | Should -Be "Step One"
        }

        It "Force should add jobstep to job and the older job step should be second" {
            $results = New-DbaAgentJobStep -SqlInstance $script:instance2 -Job "dbatoolsci Job One" -StepName "New Step One" -StepId 1 -Force
            $results.Name | Should -Be "New Step One"
            $newresults = Get-DbaAgentJob -SqlInstance $script:instance2 -Job "dbatoolsci Job One"
            $newresults.JobSteps | Where-Object Id -eq 1 | Select-Object -ExpandProperty Name | Should -Be "New Step One"
            $newresults.JobSteps | Where-Object Id -eq 2 | Select-Object -ExpandProperty Name | Should -Be "Step One"
        }

        It "Insert should insert jobstep between steps and update IDs" {
            $results = New-DbaAgentJobStep -SqlInstance $script:instance2 -Job "dbatoolsci Job One" -StepName "New Step Three" -StepId 2 -Insert
            $results.Name | Should -Be "New Step Three"
            $newresults = Get-DbaAgentJob -SqlInstance $script:instance2 -Job "dbatoolsci Job One"
            $newresults.JobSteps | Where-Object Id -eq 1 | Select-Object -ExpandProperty Name | Should -Be "New Step One"
            $newresults.JobSteps | Where-Object Id -eq 2 | Select-Object -ExpandProperty Name | Should -Be "New Step Three"
            $newresults.JobSteps | Where-Object Id -eq 3 | Select-Object -ExpandProperty Name | Should -Be "Step One"
        }
    }
}