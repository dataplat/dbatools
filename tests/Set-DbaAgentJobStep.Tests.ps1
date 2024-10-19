$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        # Importing any necessary modules or functions
        # This block is for any setup code needed for all tests in this describe block
    }

    Context "Validate parameters" {
        BeforeDiscovery {
            [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
            $knownParameters = @(
                'SqlInstance', 'SqlCredential', 'Job', 'StepName', 'NewName', 'Subsystem', 'SubsystemServer',
                'Command', 'CmdExecSuccessCode', 'OnSuccessAction', 'OnSuccessStepId', 'OnFailAction', 'OnFailStepId',
                'Database', 'DatabaseUser', 'RetryAttempts', 'RetryInterval', 'OutputFileName', 'Flag', 'ProxyName',
                'EnableException', 'InputObject', 'Force'
            )
            $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        }

        It "Should only contain our specific parameters" {
            @(Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params).Count | Should -Be 0
        }

        It "Should have SqlInstance parameter of type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]" {
            (Get-Command $CommandName).Parameters['SqlInstance'].ParameterType.FullName | Should -Be 'Dataplat.Dbatools.Parameter.DbaInstanceParameter[]'
        }

        It "Should have SqlCredential parameter of type System.Management.Automation.PSCredential" {
            (Get-Command $CommandName).Parameters['SqlCredential'].ParameterType.FullName | Should -Be 'System.Management.Automation.PSCredential'
        }

        # Add similar It blocks for each parameter, checking type
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $random = Get-Random
        $instance1 = Connect-DbaInstance -SqlInstance $global:instance1
        $instance2 = Connect-DbaInstance -SqlInstance $global:instance2

        $job1Instance1 = New-DbaAgentJob -SqlInstance $instance1 -Job "dbatoolsci_job_1_$random"
        $job1Instance2 = New-DbaAgentJob -SqlInstance $instance2 -Job "dbatoolsci_job_1_$random"
        $agentStep1 = New-DbaAgentJobStep -SqlInstance $instance1 -Job $job1Instance1 -StepName "Step 1" -OnFailAction QuitWithFailure -OnSuccessAction QuitWithSuccess
        $agentStep1 = New-DbaAgentJobStep -SqlInstance $instance2 -Job $job1Instance2 -StepName "Step 1" -OnFailAction QuitWithFailure -OnSuccessAction QuitWithSuccess

        $login = "db$random"
        $plaintext = "BigOlPassword!"
        $password = ConvertTo-SecureString $plaintext -AsPlainText -Force

        $null = Invoke-Command2 -ScriptBlock { net user $login $plaintext /add *>&1 } -ComputerName $instance2.ComputerName

        $credential = New-DbaCredential -SqlInstance $instance2 -Name "dbatoolsci_$random" -Identity "$($instance2.ComputerName)\$login" -Password $password

        $agentProxyInstance2 = New-DbaAgentProxy -SqlInstance $instance2 -Name "dbatoolsci_proxy_1_$random" -ProxyCredential "dbatoolsci_$random" -Subsystem PowerShell

        $newDbName = "dbatoolsci_newdb_$random"
        $newDb = New-DbaDatabase -SqlInstance $instance2 -Name $newDbName

        $userName = "user_$random"
        $password = 'MyV3ry$ecur3P@ssw0rd'
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        $newDBLogin = New-DbaLogin -SqlInstance $instance2 -Login $userName -Password $securePassword -Force
        $null = New-DbaDbUser -SqlInstance $instance2 -Database $newDbName -Login $userName
    }

    AfterAll {
        Remove-DbaDatabase -SqlInstance $instance2 -Database "dbatoolsci_newdb_$random" -Confirm:$false
        Remove-DbaLogin -SqlInstance $instance2 -Login "user_$random" -Confirm:$false
        Remove-DbaAgentJob -SqlInstance $instance1 -Job "dbatoolsci_job_1_$random" -Confirm:$false
        Remove-DbaAgentJob -SqlInstance $instance2 -Job "dbatoolsci_job_1_$random" -Confirm:$false
        $null = Invoke-Command2 -ScriptBlock { net user $args /delete *>&1 } -ArgumentList $login -ComputerName $instance2.ComputerName
        $credential.Drop()
        $agentProxyInstance2.Drop()
    }

    Context "Command works" {
        It "Changes the job step name" {
            $results = Get-DbaAgentJob -SqlInstance $instance2 -Job $job1Instance2
            $results.JobSteps | Where-Object Id -eq 1 | Select-Object -ExpandProperty Name | Should -Be "Step 1"

            $jobStep = Set-DbaAgentJobStep -SqlInstance $instance2 -Job $job1Instance2 -StepName "Step 1" -NewName "Step 1 updated"
            $results = Get-DbaAgentJob -SqlInstance $instance2 -Job $job1Instance2
            $results.JobSteps | Where-Object Id -eq 1 | Select-Object -ExpandProperty Name | Should -Be "Step 1 updated"

            $jobStep = Set-DbaAgentJobStep -SqlInstance $instance2 -Job $job1Instance2 -StepName "Step 1 updated" -NewName "Step 1"
        }

        It "Accepts pipeline input of pre-connected servers" {
            $jobSteps = $instance1, $instance2 | Set-DbaAgentJobStep -Job "dbatoolsci_job_1_$random" -StepName "Step 1" -NewName "Step 1 updated"

            (Get-DbaAgentJob -SqlInstance $instance1 -Job "dbatoolsci_job_1_$random").JobSteps | Where-Object Id -eq 1 | Select-Object -ExpandProperty Name | Should -Be "Step 1 updated"
            (Get-DbaAgentJob -SqlInstance $instance2 -Job "dbatoolsci_job_1_$random").JobSteps | Where-Object Id -eq 1 | Select-Object -ExpandProperty Name | Should -Be "Step 1 updated"

            $jobSteps = $instance1, $instance2 | Set-DbaAgentJobStep -Job "dbatoolsci_job_1_$random" -StepName "Step 1 updated" -NewName "Step 1"
        }

        It "Uses the -Force to add a new step" {
            $jobStep = Set-DbaAgentJobStep -SqlInstance $instance2 -Job $job1Instance2 -StepName "Step 2" -Force
            $results = Get-DbaAgentJob -SqlInstance $instance2 -Job $job1Instance2
            $results.JobSteps | Where-Object Id -eq 1 | Select-Object -ExpandProperty Name | Should -Be "Step 1"
            $results.JobSteps | Where-Object Id -eq 2 | Select-Object -ExpandProperty Name | Should -Be "Step 2"
        }

        # The following tests are for different subsystems
        $subsystems = @(
            @{Name = "PowerShell"; Command = "Get-Random"; ProxyName = "dbatoolsci_proxy_1_$random"},
            @{Name = "TransactSql"; Command = "SELECT @@VERSION"; DatabaseUser = $userName},
            @{Name = "ActiveScripting"; Command = "ActiveScripting"},
            @{Name = "AnalysisCommand"; Command = "AnalysisCommand"},
            @{Name = "AnalysisQuery"; Command = "AnalysisQuery"},
            @{Name = "CmdExec"; Command = "CmdExec"},
            @{Name = "Distribution"; Command = "Distribution"},
            @{Name = "LogReader"; Command = "LogReader"},
            @{Name = "Merge"; Command = "Merge"},
            @{Name = "QueueReader"; Command = "QueueReader"},
            @{Name = "Snapshot"; Command = "Snapshot"},
            @{Name = "SSIS"; Command = "SSIS"}
        )

        It "Sets a step with all attributes for Subsystem=<Name>" -TestCases $subsystems {
            param($Name, $Command, $ProxyName, $DatabaseUser)

            $stepId = $subsystems.IndexOf($_) + 3
            $jobStep = @{
                SqlInstance        = $instance2
                Job                = $job1Instance2
                StepName           = "Step $stepId"
                Subsystem          = $Name
                SubsystemServer    = $instance2.Name
                Command            = $Command
                CmdExecSuccessCode = $stepId
                OnSuccessAction    = "GoToStep"
                OnSuccessStepId    = [Math]::Min($stepId, 10)
                OnFailAction       = "GoToStep"
                OnFailStepId       = [Math]::Min($stepId, 10)
                Database           = $newDbName
                DatabaseUser       = $DatabaseUser
                RetryAttempts      = $stepId
                RetryInterval      = $stepId + 3
                OutputFileName     = "log$Name.txt"
                Flag               = [Microsoft.SqlServer.Management.Smo.Agent.JobStepFlags]::AppendAllCmdExecOutputToJobHistory
                ProxyName          = $ProxyName
                Force              = $true
            }

            $results = Set-DbaAgentJobStep @jobStep

            $results = Get-DbaAgentJob -SqlInstance $instance2 -Job $job1Instance2

            $newJobStep = $results.JobSteps | Where-Object Id -eq $stepId
            $newJobStep.Name | Should -Be "Step $stepId"
            $newJobStep.Subsystem | Should -Be $Name
            $newJobStep.Command | Should -Be $Command
            $newJobStep.DatabaseName | Should -Be $newDbName
            if ($DatabaseUser) { $newJobStep.DatabaseUserName | Should -Be $DatabaseUser }
            $newJobStep.RetryAttempts | Should -Be $stepId
            $newJobStep.RetryInterval | Should -Be ($stepId + 3)
            if ($Name -ne "ActiveScripting") { $newJobStep.OutputFileName | Should -Be "log$Name.txt" }
            $newJobStep.CommandExecutionSuccessCode | Should -Be $stepId
            $newJobStep.OnSuccessAction | Should -Be GoToStep
            $newJobStep.OnSuccessStep | Should -Be ([Math]::Min($stepId, 10))
            $newJobStep.OnFailAction | Should -Be GoToStep
            $newJobStep.OnFailStep | Should -Be ([Math]::Min($stepId, 10))
            $newJobStep.JobStepFlags | Should -Be AppendAllCmdExecOutputToJobHistory
            if ($ProxyName) { $newJobStep.ProxyName | Should -Be $ProxyName }
        }
    }
}
