#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Find-DbaAgentJob",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "JobName",
                "ExcludeJobName",
                "StepName",
                "LastUsed",
                "IsDisabled",
                "IsFailed",
                "IsNotScheduled",
                "IsNoEmailNotification",
                "Category",
                "Owner",
                "Since",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        #subsystemServer needs the real underlying name, and it doesn't work if targeting something like localhost\namedinstance
        # the typical error would be WARNING: [17:19:26][New-DbaAgentJobStep] Something went wrong creating the job step | The specified '@server' is
        #invalid (valid values are returned by sp_helpserver).
        $srvName = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query "select @@servername as sn" -as PSObject

        # Create test jobs
        $splatTestJob = @{
            SqlInstance = $TestConfig.instance2
            Job         = "dbatoolsci_testjob"
            OwnerLogin  = "sa"
        }
        $null = New-DbaAgentJob @splatTestJob

        $splatTestJobStep = @{
            SqlInstance        = $TestConfig.instance2
            Job                = "dbatoolsci_testjob"
            StepId             = 1
            StepName           = "dbatoolsci Failed"
            Subsystem          = "TransactSql"
            SubsystemServer    = $srvName.sn
            Command            = "RAISERROR (15600,-1,-1, 'dbatools_error');"
            CmdExecSuccessCode = 0
            OnSuccessAction    = "QuitWithSuccess"
            OnFailAction       = "QuitWithFailure"
            Database           = "master"
            RetryAttempts      = 1
            RetryInterval      = 2
        }
        $null = New-DbaAgentJobStep @splatTestJobStep

        $null = Start-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job "dbatoolsci_testjob"

        $splatRegrJob = @{
            SqlInstance = $TestConfig.instance2
            Job         = "dbatoolsregr_testjob"
            OwnerLogin  = "sa"
        }
        $null = New-DbaAgentJob @splatRegrJob

        $splatRegrJobStep = @{
            SqlInstance        = $TestConfig.instance2
            Job                = "dbatoolsregr_testjob"
            StepId             = 1
            StepName           = "dbatoolsci Failed"
            Subsystem          = "TransactSql"
            SubsystemServer    = $srvName.sn
            Command            = "RAISERROR (15600,-1,-1, 'dbatools_error');"
            CmdExecSuccessCode = 0
            OnSuccessAction    = "QuitWithSuccess"
            OnFailAction       = "QuitWithFailure"
            Database           = "master"
            RetryAttempts      = 1
            RetryInterval      = 2
        }
        $null = New-DbaAgentJobStep @splatRegrJobStep

        $null = New-DbaAgentJobCategory -SqlInstance $TestConfig.instance2 -Category "dbatoolsci_job_category" -CategoryType LocalJob

        $splatDisabledJob = @{
            SqlInstance = $TestConfig.instance2
            Job         = "dbatoolsci_testjob_disabled"
            Category    = "dbatoolsci_job_category"
            Disabled    = $true
        }
        $null = New-DbaAgentJob @splatDisabledJob

        $splatDisabledJobStep = @{
            SqlInstance        = $TestConfig.instance2
            Job                = "dbatoolsci_testjob_disabled"
            StepId             = 1
            StepName           = "dbatoolsci Test Step"
            Subsystem          = "TransactSql"
            SubsystemServer    = $srvName.sn
            Command            = "SELECT * FROM master.sys.all_columns"
            CmdExecSuccessCode = 0
            OnSuccessAction    = "QuitWithSuccess"
            OnFailAction       = "QuitWithFailure"
            Database           = "master"
            RetryAttempts      = 1
            RetryInterval      = 2
        }
        $null = New-DbaAgentJobStep @splatDisabledJobStep

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        $splatRemoveJobs = @{
            SqlInstance = $TestConfig.instance2
            Job         = @("dbatoolsci_testjob", "dbatoolsregr_testjob", "dbatoolsci_testjob_disabled")
            Confirm     = $false
        }
        $null = Remove-DbaAgentJob @splatRemoveJobs

        $null = Remove-DbaAgentJobCategory -SqlInstance $TestConfig.instance2 -Category "dbatoolsci_job_category" -Confirm $false

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Command finds jobs using all parameters" {
        BeforeAll {
            $testJobResult = Find-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job dbatoolsci_testjob
            $excludedJobResult = Find-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job *dbatoolsci* -ExcludeJobName dbatoolsci_testjob_disabled
            $stepNameResult = Find-DbaAgentJob -SqlInstance $TestConfig.instance2 -StepName "dbatoolsci Test Step"
            $lastUsedResult = Find-DbaAgentJob -SqlInstance $TestConfig.instance2 -LastUsed 10
            $disabledResult = Find-DbaAgentJob -SqlInstance $TestConfig.instance2 -IsDisabled
            $notScheduledResult = Find-DbaAgentJob -SqlInstance $TestConfig.instance2 -IsNotScheduled
            $notScheduledWildcardResult = Find-DbaAgentJob -SqlInstance $TestConfig.instance2 -IsNotScheduled -Job *dbatoolsci*
            $noEmailResult = Find-DbaAgentJob -SqlInstance $TestConfig.instance2 -IsNoEmailNotification
            $categoryResult = Find-DbaAgentJob -SqlInstance $TestConfig.instance2 -Category "dbatoolsci_job_category"
            $ownerResult = Find-DbaAgentJob -SqlInstance $TestConfig.instance2 -Owner "sa"
            $failedResult = Find-DbaAgentJob -SqlInstance $TestConfig.instance2 -IsFailed -Since "2016-07-01 10:47:00"
            $multiWildcardResult = Find-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job *dbatoolsci*, *dbatoolsregr* -ExcludeJobName dbatoolsci_testjob_disabled
        }

        It "Should find a specific job" {
            $testJobResult.name | Should -Be "dbatoolsci_testjob"
        }

        It "Should find a specific job but not an excluded job" {
            $excludedJobResult.name | Should -Not -Be "dbatoolsci_testjob_disabled"
        }

        It "Should find a specific job with a specific step" {
            $stepNameResult.name | Should -Be "dbatoolsci_testjob_disabled"
        }

        It "Should find jobs not used in the last 10 days" {
            $lastUsedResult | Should -Not -BeNullOrEmpty
        }

        It "Should find jobs disabled from running" {
            $disabledResult.name | Should -Be "dbatoolsci_testjob_disabled"
        }

        It "Should find 1 job disabled from running" {
            $disabledResult.Status.Count | Should -Be 1
        }

        It "Should find jobs that have not been scheduled" {
            $notScheduledResult | Should -Not -BeNullOrEmpty
        }

        It "Should find 2 jobs that have no schedule" {
            $notScheduledWildcardResult.Status.Count | Should -Be 2
        }

        It "Should find jobs that have no email notification" {
            $noEmailResult | Should -Not -BeNullOrEmpty
        }

        It "Should find jobs that have a category of dbatoolsci_job_category" {
            $categoryResult.name | Should -Be "dbatoolsci_testjob_disabled"
        }

        It "Should find jobs that are owned by sa" {
            $ownerResult | Should -Not -BeNullOrEmpty
        }

        It "Should find jobs that have been failed since July of 2016" {
            $failedResult | Should -Not -BeNullOrEmpty
        }

        It "Should work with multiple wildcard passed in (see #9572)" {
            $multiWildcardResult.Status.Count | Should -Be 2
        }
    }
}