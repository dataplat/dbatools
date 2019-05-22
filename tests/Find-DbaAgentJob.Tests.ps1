$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'JobName', 'ExcludeJobName', 'StepName', 'LastUsed', 'IsDisabled', 'IsFailed', 'IsNotScheduled', 'IsNoEmailNotification', 'Category', 'Owner', 'Since', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Command finds jobs using all parameters" {
        BeforeAll {
            $null = New-DbaAgentJob -SqlInstance $script:instance2 -Job 'dbatoolsci_testjob' -OwnerLogin 'sa'
            $null = New-DbaAgentJobStep -SqlInstance $script:instance2 -Job 'dbatoolsci_testjob' -StepId 1 -StepName 'dbatoolsci Failed' -Subsystem TransactSql -SubsystemServer $script:instance2 -Command "RAISERROR (15600,-1,-1, 'dbatools_error');" -CmdExecSuccessCode 0 -OnSuccessAction QuitWithSuccess -OnFailAction QuitWithFailure -Database master -DatabaseUser sa -RetryAttempts 1 -RetryInterval 2
            $null = Start-DbaAgentJob -SqlInstance $script:instance2 -Job 'dbatoolsci_testjob'
            $null = New-DbaAgentJobCategory -SqlInstance $script:instance2 -Category 'dbatoolsci_job_category' -CategoryType LocalJob
            $null = New-DbaAgentJob -SqlInstance $script:instance2 -Job 'dbatoolsci_testjob_disabled' -Category 'dbatoolsci_job_category' -Disabled
            $null = New-DbaAgentJobStep -SqlInstance $script:instance2 -Job 'dbatoolsci_testjob_disabled' -StepId 1 -StepName 'dbatoolsci Test Step' -Subsystem TransactSql -SubsystemServer $script:instance2 -Command 'SELECT * FROM master.sys.all_columns' -CmdExecSuccessCode 0 -OnSuccessAction QuitWithSuccess -OnFailAction QuitWithFailure -Database master -DatabaseUser sa -RetryAttempts 1 -RetryInterval 2
        }
        AfterAll {
            $null = Remove-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_testjob, dbatoolsci_testjob_disabled
            $null = Remove-DbaAgentJobCategory -SqlInstance $script:instance2 -Category 'dbatoolsci_job_category'
        }

        $results = Find-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_testjob
        It "Should find a specific job" {
            $results.name | Should Be "dbatoolsci_testjob"
        }
        $results = Find-DbaAgentJob -SqlInstance $script:instance2 -Job *dbatoolsci* -Exclude dbatoolsci_testjob_disabled
        It "Should find a specific job but not an excldued job" {
            $results.name | Should Not Be "dbatoolsci_testjob_disabled"
        }
        $results = Find-DbaAgentJob -SqlInstance $script:instance2 -StepName 'dbatoolsci Test Step'
        It "Should find a specific job with a specific step" {
            $results.name | Should Be "dbatoolsci_testjob_disabled"
        }
        $results = Find-DbaAgentJob -SqlInstance $script:instance2 -LastUsed 10
        It "Should find jobs not used in the last 10 days" {
            $results | Should not be null
        }
        $results = Find-DbaAgentJob -SqlInstance $script:instance2 -IsDisabled
        It "Should find jobs disabled from running" {
            $results.name | Should be "dbatoolsci_testjob_disabled"
        }
        $results = Find-DbaAgentJob -SqlInstance $script:instance2 -IsNotScheduled
        It "Should find jobs that have not been scheduled" {
            $results | Should not be null
        }
        $results = Find-DbaAgentJob -SqlInstance $script:instance2 -IsNoEmailNotification
        It "Should find jobs that have no email notification" {
            $results | Should not be null
        }
        $results = Find-DbaAgentJob -SqlInstance $script:instance2 -Category 'dbatoolsci_job_category'
        It "Should find jobs that have a category of dbatoolsci_job_category" {
            $results.name | Should be "dbatoolsci_testjob_disabled"
        }
        $results = Find-DbaAgentJob -SqlInstance $script:instance2 -Owner 'sa'
        It "Should find jobs that are owned by sa" {
            $results | Should not be null
        }
        $results = Find-DbaAgentJob -SqlInstance $script:instance2 -IsFailed -Since '2016-07-01 10:47:00'
        It "Should find jobs that have been failed since July of 2016" {
            $results | Should not be null
        }
    }
}