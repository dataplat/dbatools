#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaAgentJobStep",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Job",
                "StepName",
                "NewName",
                "Subsystem",
                "SubsystemServer",
                "Command",
                "CmdExecSuccessCode",
                "OnSuccessAction",
                "OnSuccessStepId",
                "OnFailAction",
                "OnFailStepId",
                "Database",
                "DatabaseUser",
                "RetryAttempts",
                "RetryInterval",
                "OutputFileName",
                "Flag",
                "ProxyName",
                "EnableException",
                "InputObject",
                "Force"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $random = Get-Random
        $job1instance3 = New-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 -Job "dbatoolsci_job_1_$random"
        $job1InstanceSingle = New-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti1 -Job "dbatoolsci_job_1_$random"
        $null = New-DbaAgentJobStep -SqlInstance $TestConfig.InstanceMulti2 -Job $job1instance3 -StepName "Step 1" -OnFailAction QuitWithFailure -OnSuccessAction QuitWithSuccess
        $null = New-DbaAgentJobStep -SqlInstance $TestConfig.InstanceMulti1 -Job $job1InstanceSingle -StepName "Step 1" -OnFailAction QuitWithFailure -OnSuccessAction QuitWithSuccess

        $instance3 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti2
        $InstanceSingle = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1

        $login = "db$random"
        $plaintext = "BigOlPassword!"
        $password = ConvertTo-SecureString $plaintext -AsPlainText -Force

        $computerName = Resolve-DbaComputerName -ComputerName $TestConfig.InstanceMulti1 -Property ComputerName
        $splatInvoke = @{
            ComputerName = $computerName
            ScriptBlock  = { New-LocalUser -Name $args[0] -Password $args[1] -Disabled:$false }
            ArgumentList = $login, $password
        }
        Invoke-Command2 @splatInvoke

        $credential = New-DbaCredential -SqlInstance $TestConfig.InstanceMulti1 -Name "dbatoolsci_$random" -Identity "$computerName\$login" -Password $password

        $agentProxyInstanceSingle = New-DbaAgentProxy -SqlInstance $InstanceSingle -Name "dbatoolsci_proxy_1_$random" -ProxyCredential "dbatoolsci_$random" -Subsystem PowerShell

        $newDbName = "dbatoolsci_newdb_$random"
        $newDb = New-DbaDatabase -SqlInstance $InstanceSingle -Name $newDbName

        $userName = "user_$random"
        $password = "MyV3ry`$ecur3P@ssw0rd"
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        $newDBLogin = New-DbaLogin -SqlInstance $InstanceSingle -Login $userName -Password $securePassword -Force
        $null = New-DbaDbUser -SqlInstance $InstanceSingle -Database $newDbName -Login $userName

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaDatabase -SqlInstance $InstanceSingle -Database "dbatoolsci_newdb_$random"
        Remove-DbaLogin -SqlInstance $InstanceSingle -Login "user_$random"
        Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti2 -Job "dbatoolsci_job_1_$random"
        Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti1 -Job "dbatoolsci_job_1_$random"

        $splatInvoke = @{
            ComputerName = $computerName
            ScriptBlock  = { Remove-LocalUser -Name $args[0] -ErrorAction SilentlyContinue }
            ArgumentList = $login
        }
        Invoke-Command2 @splatInvoke
        $credential.Drop()
        $agentProxyInstanceSingle.Drop()

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    Context "command works" {
        It "Change the job step name" {
            $results = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti1 -Job $job1InstanceSingle
            $results.JobSteps | Where-Object Id -eq 1 | Select-Object -ExpandProperty Name | Should -Be "Step 1"

            $jobStep = Set-DbaAgentJobStep -SqlInstance $TestConfig.InstanceMulti1 -Job $job1InstanceSingle -StepName "Step 1" -NewName "Step 1 updated"
            $results = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti1 -Job $job1InstanceSingle
            $results.JobSteps | Where-Object Id -eq 1 | Select-Object -ExpandProperty Name | Should -Be "Step 1 updated"

            $jobStep = Set-DbaAgentJobStep -SqlInstance $TestConfig.InstanceMulti1 -Job $job1InstanceSingle -StepName "Step 1 updated" -NewName "Step 1"
        }

        It "pipeline input of pre-connected servers" {
            $jobSteps = $instance3, $InstanceSingle | Set-DbaAgentJobStep -Job "dbatoolsci_job_1_$random" -StepName "Step 1" -NewName "Step 1 updated"

            (Get-DbaAgentJob -SqlInstance $instance3 -Job "dbatoolsci_job_1_$random").JobSteps | Where-Object Id -eq 1 | Select-Object -ExpandProperty Name | Should -Be "Step 1 updated"
            (Get-DbaAgentJob -SqlInstance $InstanceSingle -Job "dbatoolsci_job_1_$random").JobSteps | Where-Object Id -eq 1 | Select-Object -ExpandProperty Name | Should -Be "Step 1 updated"

            $jobSteps = $instance3, $InstanceSingle | Set-DbaAgentJobStep -Job "dbatoolsci_job_1_$random" -StepName "Step 1 updated" -NewName "Step 1"
        }

        It "use the -Force to add a new step" {
            $jobStep = Set-DbaAgentJobStep -SqlInstance $TestConfig.InstanceMulti1 -Job $job1InstanceSingle -StepName "Step 2" -Force
            $results = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti1 -Job $job1InstanceSingle
            $results.JobSteps | Where-Object Id -eq 1 | Select-Object -ExpandProperty Name | Should -Be "Step 1"
            $results.JobSteps | Where-Object Id -eq 2 | Select-Object -ExpandProperty Name | Should -Be "Step 2"
        }

        <#
            The subsystem tests below are done separately because there is variation in which parameters are supported and values (e.g. for the Flag param)
        #>

        It "set a step with all attributes for Subsystem=PowerShell" {
            $splatJobStep = @{
                SqlInstance        = $TestConfig.InstanceMulti1
                Job                = $job1InstanceSingle
                StepName           = "Step 3"
                Subsystem          = "PowerShell"
                Command            = "Get-Random"
                CmdExecSuccessCode = 1
                OnSuccessAction    = "GoToStep"
                OnSuccessStepId    = 1
                OnFailAction       = "GoToStep"
                OnFailStepId       = 1
                Database           = $newDbName
                RetryAttempts      = 2
                RetryInterval      = 5
                OutputFileName     = "logPowerShell.txt"
                Flag               = [Microsoft.SqlServer.Management.Smo.Agent.JobStepFlags]::AppendAllCmdExecOutputToJobHistory
                ProxyName          = "dbatoolsci_proxy_1_$random"
                Force              = $true
            }

            $results = Set-DbaAgentJobStep @splatJobStep

            $results = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti1 -Job $job1InstanceSingle

            $newJobStep = $results.JobSteps | Where-Object Id -eq 3
            $newJobStep.Name | Should -Be "Step 3"
            $newJobStep.Subsystem | Should -Be "PowerShell"
            $newJobStep.Command | Should -Be "Get-Random"
            $newJobStep.DatabaseName | Should -Be $newDbName
            $newJobStep.RetryAttempts | Should -Be 2
            $newJobStep.RetryInterval | Should -Be 5
            $newJobStep.OutputFileName | Should -Be "logPowerShell.txt"
            $newJobStep.CommandExecutionSuccessCode | Should -Be 1
            $newJobStep.OnSuccessAction | Should -Be GoToStep
            $newJobStep.OnSuccessStep | Should -Be 1
            $newJobStep.OnFailAction | Should -Be GoToStep
            $newJobStep.OnFailStep | Should -Be 1
            $newJobStep.JobStepFlags | Should -Be AppendAllCmdExecOutputToJobHistory
            $newJobStep.ProxyName | Should -Be "dbatoolsci_proxy_1_$random"
        }

        It "set a step with all attributes for Subsystem=TransactSql" {
            $splatJobStep = @{
                SqlInstance        = $TestConfig.InstanceMulti1
                Job                = $job1InstanceSingle
                StepName           = "Step 4"
                Subsystem          = "TransactSql"
                Command            = "SELECT @@VERSION"
                CmdExecSuccessCode = 2
                OnSuccessAction    = "GoToStep"
                OnSuccessStepId    = 2
                OnFailAction       = "GoToStep"
                OnFailStepId       = 2
                Database           = $newDbName
                DatabaseUser       = $userName
                RetryAttempts      = 3
                RetryInterval      = 6
                OutputFileName     = "logSql.txt"
                Flag               = [Microsoft.SqlServer.Management.Smo.Agent.JobStepFlags]::AppendToJobHistory
                Force              = $true
            }

            $results = Set-DbaAgentJobStep @splatJobStep

            $results = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti1 -Job $job1InstanceSingle

            $newJobStep = $results.JobSteps | Where-Object Id -eq 4
            $newJobStep.Name | Should -Be "Step 4"
            $newJobStep.Subsystem | Should -Be "TransactSql"
            $newJobStep.Command | Should -Be "SELECT @@VERSION"
            $newJobStep.DatabaseName | Should -Be $newDbName
            $newJobStep.DatabaseUserName | Should -Be $userName
            $newJobStep.RetryAttempts | Should -Be 3
            $newJobStep.RetryInterval | Should -Be 6
            $newJobStep.OutputFileName | Should -Be "logSql.txt"
            $newJobStep.CommandExecutionSuccessCode | Should -Be 2
            $newJobStep.OnSuccessAction | Should -Be GoToStep
            $newJobStep.OnSuccessStep | Should -Be 2
            $newJobStep.OnFailAction | Should -Be GoToStep
            $newJobStep.OnFailStep | Should -Be 2
            $newJobStep.JobStepFlags | Should -Be AppendToJobHistory
        }

        It "set a step with all attributes for Subsystem=AnalysisCommand" {
            $splatJobStep = @{
                SqlInstance        = $TestConfig.InstanceMulti1
                Job                = $job1InstanceSingle
                StepName           = "Step 5"
                Subsystem          = "AnalysisCommand"
                SubsystemServer    = $InstanceSingle.Name
                Command            = "AnalysisCommand"
                CmdExecSuccessCode = 3
                OnSuccessAction    = "GoToStep"
                OnSuccessStepId    = 3
                OnFailAction       = "GoToStep"
                OnFailStepId       = 3
                Database           = $newDbName
                RetryAttempts      = 4
                RetryInterval      = 7
                OutputFileName     = "logAnalysisCommand.txt"
                Flag               = [Microsoft.SqlServer.Management.Smo.Agent.JobStepFlags]::LogToTableWithOverwrite
                Force              = $true
            }

            $results = Set-DbaAgentJobStep @splatJobStep

            $results = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti1 -Job $job1InstanceSingle

            $newJobStep = $results.JobSteps | Where-Object Id -eq 5
            $newJobStep.Name | Should -Be "Step 5"
            $newJobStep.Subsystem | Should -Be "AnalysisCommand"
            $newJobStep.Server | Should -Be $InstanceSingle.Name
            $newJobStep.Command | Should -Be "AnalysisCommand"
            $newJobStep.DatabaseName | Should -Be $newDbName
            $newJobStep.RetryAttempts | Should -Be 4
            $newJobStep.RetryInterval | Should -Be 7
            $newJobStep.OutputFileName | Should -Be "logAnalysisCommand.txt"
            $newJobStep.CommandExecutionSuccessCode | Should -Be 3
            $newJobStep.OnSuccessAction | Should -Be GoToStep
            $newJobStep.OnSuccessStep | Should -Be 3
            $newJobStep.OnFailAction | Should -Be GoToStep
            $newJobStep.OnFailStep | Should -Be 3
            $newJobStep.JobStepFlags | Should -Be LogToTableWithOverwrite
        }

        It "set a step with all attributes for Subsystem=AnalysisQuery" {
            $splatJobStep = @{
                SqlInstance        = $TestConfig.InstanceMulti1
                Job                = $job1InstanceSingle
                StepName           = "Step 6"
                Subsystem          = "AnalysisQuery"
                SubsystemServer    = $InstanceSingle.Name
                Command            = "AnalysisQuery"
                CmdExecSuccessCode = 4
                OnSuccessAction    = "GoToStep"
                OnSuccessStepId    = 4
                OnFailAction       = "GoToStep"
                OnFailStepId       = 4
                Database           = $newDbName
                RetryAttempts      = 5
                RetryInterval      = 8
                OutputFileName     = "logAnalysisQuery.txt"
                Flag               = [Microsoft.SqlServer.Management.Smo.Agent.JobStepFlags]::None
                Force              = $true
            }

            $results = Set-DbaAgentJobStep @splatJobStep

            $results = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti1 -Job $job1InstanceSingle

            $newJobStep = $results.JobSteps | Where-Object Id -eq 6
            $newJobStep.Name | Should -Be "Step 6"
            $newJobStep.Subsystem | Should -Be "AnalysisQuery"
            $newJobStep.Server | Should -Be $InstanceSingle.Name
            $newJobStep.Command | Should -Be "AnalysisQuery"
            $newJobStep.DatabaseName | Should -Be $newDbName
            $newJobStep.RetryAttempts | Should -Be 5
            $newJobStep.RetryInterval | Should -Be 8
            $newJobStep.OutputFileName | Should -Be "logAnalysisQuery.txt"
            $newJobStep.CommandExecutionSuccessCode | Should -Be 4
            $newJobStep.OnSuccessAction | Should -Be GoToStep
            $newJobStep.OnSuccessStep | Should -Be 4
            $newJobStep.OnFailAction | Should -Be GoToStep
            $newJobStep.OnFailStep | Should -Be 4
            $newJobStep.JobStepFlags | Should -Be None
        }

        It "set a step with all attributes for Subsystem=CmdExec" {
            $splatJobStep = @{
                SqlInstance        = $TestConfig.InstanceMulti1
                Job                = $job1InstanceSingle
                StepName           = "Step 7"
                Subsystem          = "CmdExec"
                SubsystemServer    = $InstanceSingle.Name
                Command            = "CmdExec"
                CmdExecSuccessCode = 5
                OnSuccessAction    = "GoToStep"
                OnSuccessStepId    = 5
                OnFailAction       = "GoToStep"
                OnFailStepId       = 5
                RetryAttempts      = 6
                RetryInterval      = 9
                OutputFileName     = "logCmdExec.txt"
                Flag               = [Microsoft.SqlServer.Management.Smo.Agent.JobStepFlags]::ProvideStopProcessEvent
                Force              = $true
            }

            $results = Set-DbaAgentJobStep @splatJobStep

            $results = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti1 -Job $job1InstanceSingle

            $newJobStep = $results.JobSteps | Where-Object Id -eq 7
            $newJobStep.Name | Should -Be "Step 7"
            $newJobStep.Subsystem | Should -Be "CmdExec"
            $newJobStep.Server | Should -Be $InstanceSingle.Name
            $newJobStep.Command | Should -Be "CmdExec"
            $newJobStep.RetryAttempts | Should -Be 6
            $newJobStep.RetryInterval | Should -Be 9
            $newJobStep.OutputFileName | Should -Be "logCmdExec.txt"
            $newJobStep.CommandExecutionSuccessCode | Should -Be 5
            $newJobStep.OnSuccessAction | Should -Be GoToStep
            $newJobStep.OnSuccessStep | Should -Be 5
            $newJobStep.OnFailAction | Should -Be GoToStep
            $newJobStep.OnFailStep | Should -Be 5
            $newJobStep.JobStepFlags | Should -Be ProvideStopProcessEvent
        }

        It "set a step with all attributes for Subsystem=Distribution" {
            $splatJobStep = @{
                SqlInstance        = $TestConfig.InstanceMulti1
                Job                = $job1InstanceSingle
                StepName           = "Step 8"
                Subsystem          = "Distribution"
                Command            = "Distribution"
                CmdExecSuccessCode = 6
                OnSuccessAction    = "GoToStep"
                OnSuccessStepId    = 6
                OnFailAction       = "GoToStep"
                OnFailStepId       = 6
                Database           = $newDbName
                RetryAttempts      = 7
                RetryInterval      = 10
                Flag               = [Microsoft.SqlServer.Management.Smo.Agent.JobStepFlags]::None
                Force              = $true
            }

            $results = Set-DbaAgentJobStep @splatJobStep

            $results = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti1 -Job $job1InstanceSingle

            $newJobStep = $results.JobSteps | Where-Object Id -eq 8
            $newJobStep.Name | Should -Be "Step 8"
            $newJobStep.Subsystem | Should -Be "Distribution"
            $newJobStep.Command | Should -Be "Distribution"
            $newJobStep.DatabaseName | Should -Be $newDbName
            $newJobStep.RetryAttempts | Should -Be 7
            $newJobStep.RetryInterval | Should -Be 10
            $newJobStep.CommandExecutionSuccessCode | Should -Be 6
            $newJobStep.OnSuccessAction | Should -Be GoToStep
            $newJobStep.OnSuccessStep | Should -Be 6
            $newJobStep.OnFailAction | Should -Be GoToStep
            $newJobStep.OnFailStep | Should -Be 6
            $newJobStep.JobStepFlags | Should -Be None
        }

        It "set a step with all attributes for Subsystem=LogReader" {
            $splatJobStep = @{
                SqlInstance        = $TestConfig.InstanceMulti1
                Job                = $job1InstanceSingle
                StepName           = "Step 9"
                Subsystem          = "LogReader"
                Command            = "LogReader"
                CmdExecSuccessCode = 7
                OnSuccessAction    = "GoToStep"
                OnSuccessStepId    = 7
                OnFailAction       = "GoToStep"
                OnFailStepId       = 7
                Database           = $newDbName
                RetryAttempts      = 8
                RetryInterval      = 11
                Flag               = [Microsoft.SqlServer.Management.Smo.Agent.JobStepFlags]::AppendAllCmdExecOutputToJobHistory
                Force              = $true
            }

            $results = Set-DbaAgentJobStep @splatJobStep

            $results = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti1 -Job $job1InstanceSingle

            $newJobStep = $results.JobSteps | Where-Object Id -eq 9
            $newJobStep.Name | Should -Be "Step 9"
            $newJobStep.Subsystem | Should -Be "LogReader"
            $newJobStep.Command | Should -Be "LogReader"
            $newJobStep.DatabaseName | Should -Be $newDbName
            $newJobStep.RetryAttempts | Should -Be 8
            $newJobStep.RetryInterval | Should -Be 11
            $newJobStep.CommandExecutionSuccessCode | Should -Be 7
            $newJobStep.OnSuccessAction | Should -Be GoToStep
            $newJobStep.OnSuccessStep | Should -Be 7
            $newJobStep.OnFailAction | Should -Be GoToStep
            $newJobStep.OnFailStep | Should -Be 7
            $newJobStep.JobStepFlags | Should -Be AppendAllCmdExecOutputToJobHistory
        }

        It "set a step with all attributes for Subsystem=Merge" {
            $splatJobStep = @{
                SqlInstance        = $TestConfig.InstanceMulti1
                Job                = $job1InstanceSingle
                StepName           = "Step 10"
                Subsystem          = "Merge"
                Command            = "Merge"
                CmdExecSuccessCode = 8
                OnSuccessAction    = "GoToStep"
                OnSuccessStepId    = 8
                OnFailAction       = "GoToStep"
                OnFailStepId       = 8
                Database           = $newDbName
                RetryAttempts      = 9
                RetryInterval      = 12
                Flag               = [Microsoft.SqlServer.Management.Smo.Agent.JobStepFlags]::AppendAllCmdExecOutputToJobHistory
                Force              = $true
            }

            $results = Set-DbaAgentJobStep @splatJobStep

            $results = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti1 -Job $job1InstanceSingle

            $newJobStep = $results.JobSteps | Where-Object Id -eq 10
            $newJobStep.Name | Should -Be "Step 10"
            $newJobStep.Subsystem | Should -Be "Merge"
            $newJobStep.Command | Should -Be "Merge"
            $newJobStep.DatabaseName | Should -Be $newDbName
            $newJobStep.RetryAttempts | Should -Be 9
            $newJobStep.RetryInterval | Should -Be 12
            $newJobStep.CommandExecutionSuccessCode | Should -Be 8
            $newJobStep.OnSuccessAction | Should -Be GoToStep
            $newJobStep.OnSuccessStep | Should -Be 8
            $newJobStep.OnFailAction | Should -Be GoToStep
            $newJobStep.OnFailStep | Should -Be 8
            $newJobStep.JobStepFlags | Should -Be AppendAllCmdExecOutputToJobHistory
        }

        It "set a step with all attributes for Subsystem=QueueReader" {
            $splatJobStep = @{
                SqlInstance        = $TestConfig.InstanceMulti1
                Job                = $job1InstanceSingle
                StepName           = "Step 11"
                Subsystem          = "QueueReader"
                Command            = "QueueReader"
                CmdExecSuccessCode = 9
                OnSuccessAction    = "GoToStep"
                OnSuccessStepId    = 9
                OnFailAction       = "GoToStep"
                OnFailStepId       = 9
                Database           = $newDbName
                RetryAttempts      = 10
                RetryInterval      = 13
                Flag               = [Microsoft.SqlServer.Management.Smo.Agent.JobStepFlags]::AppendAllCmdExecOutputToJobHistory
                Force              = $true
            }

            $results = Set-DbaAgentJobStep @splatJobStep

            $results = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti1 -Job $job1InstanceSingle

            $newJobStep = $results.JobSteps | Where-Object Id -eq 11
            $newJobStep.Name | Should -Be "Step 11"
            $newJobStep.Subsystem | Should -Be "QueueReader"
            $newJobStep.Command | Should -Be "QueueReader"
            $newJobStep.DatabaseName | Should -Be $newDbName
            $newJobStep.RetryAttempts | Should -Be 10
            $newJobStep.RetryInterval | Should -Be 13
            $newJobStep.CommandExecutionSuccessCode | Should -Be 9
            $newJobStep.OnSuccessAction | Should -Be GoToStep
            $newJobStep.OnSuccessStep | Should -Be 9
            $newJobStep.OnFailAction | Should -Be GoToStep
            $newJobStep.OnFailStep | Should -Be 9
            $newJobStep.JobStepFlags | Should -Be AppendAllCmdExecOutputToJobHistory
        }

        It "set a step with all attributes for Subsystem=Snapshot" {
            $splatJobStep = @{
                SqlInstance        = $TestConfig.InstanceMulti1
                Job                = $job1InstanceSingle
                StepName           = "Step 12"
                Subsystem          = "Snapshot"
                Command            = "Snapshot"
                CmdExecSuccessCode = 10
                OnSuccessAction    = "GoToStep"
                OnSuccessStepId    = 10
                OnFailAction       = "GoToStep"
                OnFailStepId       = 10
                Database           = $newDbName
                RetryAttempts      = 11
                RetryInterval      = 14
                Flag               = [Microsoft.SqlServer.Management.Smo.Agent.JobStepFlags]::AppendAllCmdExecOutputToJobHistory
                Force              = $true
            }

            $results = Set-DbaAgentJobStep @splatJobStep

            $results = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti1 -Job $job1InstanceSingle

            $newJobStep = $results.JobSteps | Where-Object Id -eq 12
            $newJobStep.Name | Should -Be "Step 12"
            $newJobStep.Subsystem | Should -Be "Snapshot"
            $newJobStep.Command | Should -Be "Snapshot"
            $newJobStep.DatabaseName | Should -Be $newDbName
            $newJobStep.RetryAttempts | Should -Be 11
            $newJobStep.RetryInterval | Should -Be 14
            $newJobStep.CommandExecutionSuccessCode | Should -Be 10
            $newJobStep.OnSuccessAction | Should -Be GoToStep
            $newJobStep.OnSuccessStep | Should -Be 10
            $newJobStep.OnFailAction | Should -Be GoToStep
            $newJobStep.OnFailStep | Should -Be 10
            $newJobStep.JobStepFlags | Should -Be AppendAllCmdExecOutputToJobHistory
        }

        It "set a step with all attributes for Subsystem=SSIS" {
            $splatJobStep = @{
                SqlInstance        = $TestConfig.InstanceMulti1
                Job                = $job1InstanceSingle
                StepName           = "Step 13"
                Subsystem          = "SSIS"
                Command            = "SSIS"
                CmdExecSuccessCode = 11
                OnSuccessAction    = "QuitWithSuccess"
                OnFailAction       = "GoToStep"
                OnFailStepId       = 11
                Database           = $newDbName
                RetryAttempts      = 12
                RetryInterval      = 15
                Flag               = [Microsoft.SqlServer.Management.Smo.Agent.JobStepFlags]::AppendAllCmdExecOutputToJobHistory
                Force              = $true
            }

            $results = Set-DbaAgentJobStep @splatJobStep

            $results = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti1 -Job $job1InstanceSingle

            $newJobStep = $results.JobSteps | Where-Object Id -eq 13
            $newJobStep.Name | Should -Be "Step 13"
            $newJobStep.Subsystem | Should -Be "SSIS"
            $newJobStep.Command | Should -Be "SSIS"
            $newJobStep.DatabaseName | Should -Be $newDbName
            $newJobStep.RetryAttempts | Should -Be 12
            $newJobStep.RetryInterval | Should -Be 15
            $newJobStep.CommandExecutionSuccessCode | Should -Be 11
            $newJobStep.OnSuccessAction | Should -Be QuitWithSuccess
            $newJobStep.OnFailAction | Should -Be GoToStep
            $newJobStep.OnFailStep | Should -Be 11
            $newJobStep.JobStepFlags | Should -Be AppendAllCmdExecOutputToJobHistory
        }
    }

    Context "Output validation" {
        BeforeAll {
            $outputJobName = "dbatoolsci_outputjob_$(Get-Random)"
            $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti1 -Job $outputJobName -EnableException
            $null = New-DbaAgentJobStep -SqlInstance $TestConfig.InstanceMulti1 -Job $outputJobName -StepName "OutputStep1" -OnFailAction QuitWithFailure -OnSuccessAction QuitWithSuccess -EnableException
            $result = Set-DbaAgentJobStep -SqlInstance $TestConfig.InstanceMulti1 -Job $outputJobName -StepName "OutputStep1" -NewName "OutputStep1Updated"
        }

        AfterAll {
            Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceMulti1 -Job $outputJobName -Confirm:$false -ErrorAction SilentlyContinue
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.Agent.JobStep"
        }

        It "Has the correct properties on the output object" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].PSObject.Properties.Name | Should -Contain "Name"
            $result[0].PSObject.Properties.Name | Should -Contain "Subsystem"
            $result[0].PSObject.Properties.Name | Should -Contain "Command"
            $result[0].PSObject.Properties.Name | Should -Contain "DatabaseName"
            $result[0].PSObject.Properties.Name | Should -Contain "OnSuccessAction"
            $result[0].PSObject.Properties.Name | Should -Contain "OnFailAction"
        }
    }
}