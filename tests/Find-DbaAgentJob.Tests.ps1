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

    }
}