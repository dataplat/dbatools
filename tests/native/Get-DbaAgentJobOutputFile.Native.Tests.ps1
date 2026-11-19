#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaAgentJobOutputFile",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- Read-only retrieval; the pinned command does not support ShouldProcess.

# The pinned "Return values" tests replace Connect-DbaInstance InModuleScope with a hashtable server; the compiled
# cmdlet calls no such function. These tests prove the same behaviour with real, uniquely named jobs shaped like the
# pinned mock: Job1 (two steps with output files), Job2 (one of two) and Job3 (none).
Describe "Native Get-DbaAgentJobOutputFile" -Tag IntegrationTests {
    BeforeAll {
        $outInstance = $TestConfig.InstanceSingle
        $outServer = Connect-DbaInstance -SqlInstance $outInstance -EnableException
        $outPrefix = "native_joboutput_" + [Guid]::NewGuid().ToString("N").Substring(0, 12)
        $outJob1 = $outPrefix + "_1"
        $outJob2 = $outPrefix + "_2"
        $outJob3 = $outPrefix + "_3"
        $outOwnJobs = @($outJob1, $outJob2, $outJob3)
        $outBadInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        $outListeners = [Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
        if (@($outListeners | Where-Object Port -eq 1).Count) {
            throw "Output file failure fixture requires no local TCP listener on port 1"
        }

        function New-NativeOutputJob {
            param($Name, [string[]]$OutputFiles)
            $newJob = New-Object Microsoft.SqlServer.Management.Smo.Agent.Job -ArgumentList $outServer.JobServer, $Name
            $newJob.IsEnabled = $false
            $newJob.Create()
            for ($stepNumber = 1; $stepNumber -le $OutputFiles.Count; $stepNumber++) {
                $newStep = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobStep -ArgumentList $newJob, ("Step" + $stepNumber)
                $newStep.SubSystem = [Microsoft.SqlServer.Management.Smo.Agent.AgentSubSystem]::TransactSql
                $newStep.DatabaseName = "master"
                $newStep.Command = "SELECT 1;"
                if ($OutputFiles[$stepNumber - 1]) { $newStep.OutputFileName = $OutputFiles[$stepNumber - 1] }
                $newStep.Create()
            }
        }

        New-NativeOutputJob -Name $outJob1 -OutputFiles "Job1Output1", "Job1Output2"
        New-NativeOutputJob -Name $outJob2 -OutputFiles "Job2Output1", ""
        New-NativeOutputJob -Name $outJob3 -OutputFiles "", ""
        $outRemoteHost = ($outServer.ComputerName -split "\\")[0]
    }

    AfterAll {
        if ($outServer -and $outOwnJobs) {
            $outServer.JobServer.Jobs.Refresh()
            foreach ($outCleanupName in $outOwnJobs) {
                $outCleanup = $outServer.JobServer.Jobs[$outCleanupName]
                if ($null -ne $outCleanup) { $outCleanup.Drop() }
            }
        }
    }

    Context "Pinned output file behaviour" {
        It "returns only the steps that have an output file, with remote paths and the pinned default view" {
            $outRows = @(Get-DbaAgentJobOutputFile -SqlInstance $outInstance -EnableException | Where-Object Job -in $outOwnJobs)
            $outRows.Count | Should -Be 3
            (@($outRows | ForEach-Object { $PSItem.Job + "|" + $PSItem.JobStep + "|" + $PSItem.StepId + "|" + $PSItem.OutputFileName }) -join ",") | Should -BeExactly ($outJob1 + "|Step1|1|Job1Output1," + $outJob1 + "|Step2|2|Job1Output2," + $outJob2 + "|Step1|1|Job2Output1")
            foreach ($row in $outRows) {
                $expectedRemote = if ($IsLinux -or $IsMacOS) { $row.OutputFileName } else { "\\" + $outRemoteHost + "\" + $row.OutputFileName }
                $row.RemoteOutputFileName | Should -BeExactly $expectedRemote
                $row.ComputerName | Should -BeExactly $outServer.ComputerName
                $row.InstanceName | Should -BeExactly $outServer.ServiceName
                $row.SqlInstance | Should -BeExactly $outServer.DomainInstanceName
                (@($row.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames) -join ",") | Should -BeExactly "ComputerName,InstanceName,Job,JobStep,OutputFileName,RemoteOutputFileName,SqlInstance"
            }
        }

        It "honors the Job parameter" {
            $jobRows = @(Get-DbaAgentJobOutputFile -SqlInstance $outInstance -Job $outJob1 -EnableException)
            $jobRows.Count | Should -Be 2
            @($jobRows | Where-Object Job -ne $outJob1).Count | Should -Be 0
            ($jobRows.OutputFileName -join ",") | Should -BeExactly "Job1Output1,Job1Output2"
        }

        It "honors the ExcludeJob parameter" {
            $excludeRows = @(Get-DbaAgentJobOutputFile -SqlInstance $outInstance -ExcludeJob $outJob1 -EnableException | Where-Object Job -in $outOwnJobs)
            $excludeRows.Count | Should -Be 1
            $excludeRows[0].Job | Should -BeExactly $outJob2
            $excludeRows[0].OutputFileName | Should -BeExactly "Job2Output1"
            $excludeRows[0].StepId | Should -Be 1
        }

        # The pinned :117 "Does not return even with a specific job without outputfiles" runs against a mocked server; a
        # compiled cmdlet gets zero rows there only because the literal host SQLServerName cannot connect. This proves the
        # behaviour on a connected instance: the job exists with two steps and no output files, the call connects (no
        # warning; -EnableException would throw on a failed connect) and returns nothing, while the same call on a
        # fixture job with an output file returns its row.
        It "returns nothing for -Job on a connected fixture job without output files, while a fixture job with one returns rows" {
            $outServer.JobServer.Jobs.Refresh()
            $noFileJob = $outServer.JobServer.Jobs[$outJob3]
            $noFileJob | Should -Not -BeNullOrEmpty
            $noFileJob.JobSteps.Refresh()
            @($noFileJob.JobSteps).Count | Should -Be 2
            @($noFileJob.JobSteps | Where-Object OutputFileName).Count | Should -Be 0

            $noFileWarnings = @()
            $noFileRows = @(Get-DbaAgentJobOutputFile -SqlInstance $outInstance -Job $outJob3 -EnableException -WarningVariable noFileWarnings)
            $noFileRows.Count | Should -Be 0
            $noFileWarnings.Count | Should -Be 0

            $controlWarnings = @()
            $controlRows = @(Get-DbaAgentJobOutputFile -SqlInstance $outInstance -Job $outJob2 -EnableException -WarningVariable controlWarnings)
            $controlWarnings.Count | Should -Be 0
            $controlRows.Count | Should -Be 1
            $controlRows[0].Job | Should -BeExactly $outJob2
            $controlRows[0].OutputFileName | Should -BeExactly "Job2Output1"

            $bothRows = @(Get-DbaAgentJobOutputFile -SqlInstance $outInstance -Job $outJob3, $outJob2 -EnableException)
            (@($bothRows | ForEach-Object { $PSItem.Job + "|" + $PSItem.OutputFileName }) -join ",") | Should -BeExactly ($outJob2 + "|Job2Output1")
        }
    }

    Context "Pipeline, failures and errors" {
        It "returns the output files of each piped instance" -Tag "NativeChecklist:pipeline-multiple" {
            $twice = @($outInstance, $outInstance | Get-DbaAgentJobOutputFile -Job $outJob1 -EnableException)
            $twice.Count | Should -Be 4
        }

        It "warns and continues past an instance that cannot be reached" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:switch-false", "NativeChecklist:pipeline-multiple" {
            $connectWarnings = @()
            $continued = @(@($outBadInstance, $outInstance) | Get-DbaAgentJobOutputFile -Job $outJob1 -EnableException:$false -WarningAction SilentlyContinue -WarningVariable connectWarnings)
            $continued.Count | Should -Be 2
            ($connectWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "throws a connection error with EnableException" -Tag "NativeChecklist:enable-exception" {
            $connectFailure = $null
            try {
                $null = Get-DbaAgentJobOutputFile -SqlInstance $outBadInstance -Job $outJob1 -EnableException
            } catch {
                $connectFailure = $PSItem
            }
            $connectFailure | Should -Not -BeNullOrEmpty
            $connectFailure.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaAgentJobOutputFile*"
            $connectFailure.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }

    Context "Upstream corrections" {
        # NativeChecklist: azure-sqldb -- SQL Server Agent jobs and msdb do not exist in Azure SQL Database (https://learn.microsoft.com/azure/azure-sql/database/transact-sql-tsql-differences-sql-server, "SQL Server Agent: Syntax that relies upon the SQL Server Agent or the msdb database"); the command refuses it as Connect-DbaInstance -AzureUnsupported does.
        It "refuses Azure SQL Database as Connect-DbaInstance -AzureUnsupported does" -Tag "NativeChecklist:azure-sqldb" {
            $azure = $null
            for ($attempt = 0; $attempt -lt 6; $attempt++) {
                try {
                    $azure = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -SqlCredential $TestConfig.AzureSqlDbCred -Database $TestConfig.AzureSqlDbName -EnableException
                    break
                } catch {
                    $transient = $false
                    for ($failure = $PSItem.Exception; $failure; $failure = $failure.InnerException) {
                        if ($failure.Number -in @(-2, 40613) -or $failure.Message -match "timed out|timeout") { $transient = $true }
                    }
                    if (-not $transient -or $attempt -eq 5) { throw }
                    Start-Sleep -Seconds 10
                }
            }
            $azure.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
            $azureWarnings = @()
            @(Get-DbaAgentJobOutputFile -SqlInstance $azure -EnableException:$false -WarningAction SilentlyContinue -WarningVariable azureWarnings).Count | Should -Be 0
            ($azureWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
            { Get-DbaAgentJobOutputFile -SqlInstance $azure -EnableException } | Should -Throw "*Azure SQL Database not supported*"
        }
    }
}

Describe "Native Get-DbaAgentJobOutputFile over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            # Unique per leg and run: the instance is shared.
            $loginJobName = "native_joboutput_sqllogin_" + [Guid]::NewGuid().ToString("N")
            $loginJob = New-Object Microsoft.SqlServer.Management.Smo.Agent.Job -ArgumentList $loginServer.JobServer, $loginJobName
            $loginJob.IsEnabled = $false
            $loginJob.Create()
            $loginStep = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobStep -ArgumentList $loginJob, "native_step_sqllogin"
            $loginStep.SubSystem = [Microsoft.SqlServer.Management.Smo.Agent.AgentSubSystem]::TransactSql
            $loginStep.DatabaseName = "master"
            $loginStep.Command = "SELECT 1;"
            $loginStep.OutputFileName = "native_sqllogin_output.txt"
            $loginStep.Create()
        }
        AfterAll {
            if ($loginServer -and $loginJobName) {
                $loginServer.JobServer.Jobs.Refresh()
                $loginCleanup = $loginServer.JobServer.Jobs[$loginJobName]
                if ($null -ne $loginCleanup) { $loginCleanup.Drop() }
            }
        }

        It "works with -SqlCredential" {
            $splatLoginOutput = @{
                SqlInstance     = $loginInstance
                SqlCredential   = $loginCred
                Job             = $loginJobName
                EnableException = $true
            }
            $loginRows = @(Get-DbaAgentJobOutputFile @splatLoginOutput)
            $loginRows.Count | Should -Be 1
            $loginRows[0].Job | Should -BeExactly $loginJobName
            $loginRows[0].OutputFileName | Should -BeExactly "native_sqllogin_output.txt"
        }

        # Pin public/Get-DbaAgentJobOutputFile.ps1:113-118 (refs/pins/dbatools-2026-10-22), verbatim:
        #         foreach ($instance in $SqlInstance) {
        #             try {
        #                 $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        #             } catch {
        #                 Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        #             }
        # Connect-DbaInstance forces its own EnableException, so a failed login throws into this catch: a warning and no
        # output by default, a terminating error under -EnableException. No commit can run the pinned function: the base
        # ships the compiled cmdlet and the pin predates src/, so these assertions follow this excerpt (watchman 49f13ebb).
        It "fails cleanly without the credential: a warning and no output" {
            $loginWarnings = @()
            $splatLoginNoCredential = @{
                SqlInstance     = $loginInstance
                Job             = $loginJobName
                WarningAction   = "SilentlyContinue"
                WarningVariable = "loginWarnings"
            }
            $loginResult = @(Get-DbaAgentJobOutputFile @splatLoginNoCredential)
            $loginResult.Count | Should -Be 0
            ($loginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "fails cleanly without the credential: -EnableException throws a connection error" {
            $loginCaught = $null
            try {
                $null = Get-DbaAgentJobOutputFile -SqlInstance $loginInstance -Job $loginJobName -EnableException
            } catch {
                $loginCaught = $PSItem
            }
            $loginCaught | Should -Not -BeNullOrEmpty
            $loginCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }
}
