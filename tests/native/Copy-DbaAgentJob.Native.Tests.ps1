#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
# Azure SQL Database does not provide SQL Agent; the native refusal test covers this engine. https://learn.microsoft.com/data-migration/sql-server/database/assessment-rules#sql-agent-jobs
param(
    $ModuleName = "dbatools",
    $CommandName = "Copy-DbaAgentJob",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native Copy-DbaAgentJob" -Tag IntegrationTests {
    BeforeAll {
        $nativeJobSource = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -EnableException
        $nativeJobDestination = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2 -EnableException
        $nativeJobPrefix = "nativecopy_" + [guid]::NewGuid().ToString("N")
        $nativeJobNames = @(($nativeJobPrefix + "_one"), ($nativeJobPrefix + "_two"))
        $nativeJobRename = $nativeJobPrefix + "_O'Reilly"
        $nativeJobLinkName = $nativeJobPrefix + "_linked"
        $nativeJobAlertName = $nativeJobPrefix + "_alert"
        foreach ($nativeJobName in $nativeJobNames) {
            $nativeJob = New-Object Microsoft.SqlServer.Management.Smo.Agent.Job -ArgumentList $nativeJobSource.JobServer, $nativeJobName
            $nativeJob.IsEnabled = $false
            $nativeJob.Create()
            $nativeJob.ApplyToTargetServer([string]::Empty)
            $nativeJob.Refresh()
            $nativeJob.JobType.ToString() | Should -BeExactly 'Local'
        }
        $nativeJobLink = New-Object Microsoft.SqlServer.Management.Smo.Agent.Job -ArgumentList $nativeJobDestination.JobServer, $nativeJobLinkName
        $nativeJobLink.IsEnabled = $false
        $nativeJobLink.Create()
        $nativeJobLink.ApplyToTargetServer([string]::Empty)
        $nativeJobAlert = New-Object Microsoft.SqlServer.Management.Smo.Agent.Alert -ArgumentList $nativeJobDestination.JobServer, $nativeJobAlertName
        $nativeJobAlert.IsEnabled = $false
        $nativeJobAlert.Severity = 12
        $nativeJobAlert.EventDescriptionKeyword = $nativeJobPrefix
        $nativeJobAlert.JobID = $nativeJobLink.JobID
        $nativeJobAlert.Create()
    }

    AfterAll {
        $nativeJobDestination.JobServer.Alerts.Refresh()
        if ($nativeJobDestination.JobServer.Alerts.Contains($nativeJobAlertName)) {
            $nativeJobDestination.JobServer.Alerts[$nativeJobAlertName].Drop()
        }
        foreach ($nativeJobServer in @($nativeJobSource, $nativeJobDestination)) {
            $nativeJobServer.JobServer.Jobs.Refresh()
            foreach ($nativeJobName in @($nativeJobNames) + @($nativeJobRename, $nativeJobLinkName)) {
                if ($nativeJobServer.JobServer.Jobs.Contains($nativeJobName)) {
                    $nativeJobServer.JobServer.Jobs[$nativeJobName].Drop()
                }
            }
        }
    }

    It "refuses an Azure destination and continues to the next destination" -Tag "NativeChecklist:azure-sqldb" {
        $azureJobServer = $null
        $azureJobName = $nativeJobPrefix + "_azure"
        try {
            for ($attempt = 0; $attempt -le 6; $attempt++) {
                try {
                    $azureJobServer = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -Database $TestConfig.AzureSqlDbName -SqlCredential $TestConfig.AzureSqlDbCred -EnableException
                    break
                } catch {
                    $azureError = $_.Exception
                    $isResuming = $false
                    while ($azureError) {
                        if ($azureError.Number -in 40613, -2 -or $azureError -is [System.TimeoutException]) { $isResuming = $true }
                        $azureError = $azureError.InnerException
                    }
                    if (-not $isResuming -or $attempt -eq 6) { throw }
                    Start-Sleep -Seconds 10
                }
            }
            $azureJobServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
            $azureJobWarnings = @()
            @(Copy-DbaAgentJob -Source $nativeJobSource -Destination $azureJobServer -Job $nativeJobNames[0] -Confirm:$false -EnableException:$false -WarningAction SilentlyContinue -WarningVariable azureJobWarnings).Count | Should -Be 0
            ($azureJobWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
            { Copy-DbaAgentJob -Source $nativeJobSource -Destination $azureJobServer -Job $nativeJobNames[0] -Confirm:$false -EnableException } | Should -Throw "*Azure SQL Database not supported*"
            $azureJobContinued = @(Copy-DbaAgentJob -Source $nativeJobSource -Destination @($azureJobServer, $nativeJobDestination) -Job $nativeJobNames[0] -NewName $azureJobName -Confirm:$false -EnableException:$false -WarningAction SilentlyContinue)
            $azureJobContinued.Count | Should -Be 1
            $azureJobContinued[0].Status | Should -BeExactly "Successful"
            $nativeJobDestination.JobServer.Jobs.Refresh()
            $nativeJobDestination.JobServer.Jobs.Contains($azureJobName) | Should -BeTrue
        } finally {
            $nativeJobDestination.JobServer.Jobs.Refresh()
            if ($nativeJobDestination.JobServer.Jobs.Contains($azureJobName)) { $nativeJobDestination.JobServer.Jobs[$azureJobName].Drop() }
            if ($azureJobServer) { $azureJobServer.ConnectionContext.Disconnect() }
        }
    }

    It "copies a job to a quoted new name without executing name text" {
        $nativeJobResult = Copy-DbaAgentJob -Source $nativeJobSource -Destination $nativeJobDestination -Job $nativeJobNames[0] -NewName $nativeJobRename -Confirm:$false -EnableException
        $nativeJobResult.Status | Should -Be "Successful"
        $nativeJobDestination.JobServer.Jobs.Refresh()
        $nativeJobDestination.JobServer.Jobs.Contains($nativeJobRename) | Should -BeTrue
    }

    It "honors documented wildcard inclusion and exclusion filters" {
        $nativeJobResult = @(Copy-DbaAgentJob -Source $nativeJobSource -Destination $nativeJobDestination -Job ($nativeJobPrefix + "_*") -ExcludeJob "*_two" -Confirm:$false -EnableException)
        $nativeJobResult.Count | Should -Be 1
        $nativeJobResult.Name | Should -Be $nativeJobNames[0]
        $nativeJobResult.Status | Should -Be "Successful"
    }

    It "keeps literal wildcard job names exact after source filtering and across pipeline records" {
        $literalJobName = $nativeJobPrefix + '_literal?'
        $matchingJobName = $nativeJobPrefix + '_literal1'
        try {
            foreach ($name in @($literalJobName, $matchingJobName)) {
                $job = New-Object Microsoft.SqlServer.Management.Smo.Agent.Job -ArgumentList $nativeJobSource.JobServer, $name
                $job.IsEnabled = $false
                $job.Create()
                $job.ApplyToTargetServer([string]::Empty)
                $job.Refresh()
                $job.JobType.ToString() | Should -BeExactly 'Local'
            }
            $nativeJobSource.JobServer.Jobs.Refresh()
            $sourceFiltered = @(Copy-DbaAgentJob -Source $nativeJobSource -Destination $nativeJobDestination -Job ($nativeJobPrefix + '_literal*') -ExcludeJob $literalJobName -Confirm:$false -EnableException)
            $sourceFiltered.Count | Should -Be 1
            $sourceFiltered[0].Name | Should -BeExactly $matchingJobName
            $sourceFiltered[0].Status | Should -BeExactly 'Successful'
            $nativeJobDestination.JobServer.Jobs.Refresh()
            $nativeJobDestination.JobServer.Jobs.Contains($literalJobName) | Should -BeFalse
            $nativeJobDestination.JobServer.Jobs[$matchingJobName].Drop()

            $pipelineJobs = @($nativeJobSource.JobServer.Jobs[$matchingJobName], $nativeJobSource.JobServer.Jobs[$literalJobName])
            $included = @($pipelineJobs | Copy-DbaAgentJob -Destination $nativeJobDestination -Job $literalJobName -Confirm:$false -EnableException)
            $included.Count | Should -Be 1
            $included[0].Name | Should -BeExactly $literalJobName
            $included[0].Status | Should -BeExactly 'Successful'
            $nativeJobDestination.JobServer.Jobs.Refresh()
            $nativeJobDestination.JobServer.Jobs.Contains($matchingJobName) | Should -BeFalse
            $nativeJobDestination.JobServer.Jobs[$literalJobName].Drop()

            $excluded = @($pipelineJobs | Copy-DbaAgentJob -Destination $nativeJobDestination -ExcludeJob $literalJobName -Confirm:$false -EnableException)
            $excluded.Count | Should -Be 1
            $excluded[0].Name | Should -BeExactly $matchingJobName
            $excluded[0].Status | Should -BeExactly 'Successful'
            $nativeJobDestination.JobServer.Jobs.Refresh()
            $nativeJobDestination.JobServer.Jobs.Contains($literalJobName) | Should -BeFalse
        } finally {
            foreach ($server in @($nativeJobSource, $nativeJobDestination)) {
                $server.JobServer.Jobs.Refresh()
                foreach ($name in @($literalJobName, $matchingJobName)) {
                    if ($server.JobServer.Jobs.Contains($name)) { $server.JobServer.Jobs[$name].Drop() }
                }
            }
        }
    }

    It "preserves GO lines and Agent tokens in copied step commands" {
        $stepJobName = $nativeJobPrefix + '_command_text'
        $commandText = @('SELECT N''first batch'';', 'GO', 'PRINT N''$(ESCAPE_SQUOTE(JOBNAME))'';') -join [Environment]::NewLine
        try {
            $job = New-Object Microsoft.SqlServer.Management.Smo.Agent.Job -ArgumentList $nativeJobSource.JobServer, $stepJobName
            $job.IsEnabled = $false
            $job.Create()
            $job.ApplyToTargetServer([string]::Empty)
            $step = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobStep -ArgumentList $job, 'text-preservation'
            $step.SubSystem = 'TransactSql'
            $step.DatabaseName = 'master'
            $step.Command = $commandText
            $step.Create()
            $step.Refresh()
            $step.Command | Should -BeExactly $commandText
            $job.Refresh()
            $job.JobType.ToString() | Should -BeExactly 'Local'
            $result = @(Copy-DbaAgentJob -InputObject $job -Destination $nativeJobDestination -Confirm:$false -EnableException)
            $result.Count | Should -Be 1
            $result[0].Status | Should -BeExactly 'Successful'
            $nativeJobDestination.JobServer.Jobs.Refresh()
            $copiedJob = $nativeJobDestination.JobServer.Jobs[$stepJobName]
            $copiedJob.IsEnabled | Should -BeFalse
            $copiedJob.JobSteps.Refresh()
            $copiedJob.JobSteps['text-preservation'].Command | Should -BeExactly $commandText
        } finally {
            foreach ($server in @($nativeJobSource, $nativeJobDestination)) {
                $server.JobServer.Jobs.Refresh()
                if ($server.JobServer.Jobs.Contains($stepJobName)) { $server.JobServer.Jobs[$stepJobName].Drop() }
            }
        }
    }

    It "remaps a step server matching the source with different casing" {
        $caseJobName = $nativeJobPrefix + '_server_case'
        $sourceName = [string]$nativeJobSource.DomainInstanceName
        $differentCase = $sourceName.ToLowerInvariant()
        if ($differentCase -ceq $sourceName) { $differentCase = $sourceName.ToUpperInvariant() }
        $differentCase | Should -Not -BeExactly $sourceName
        try {
            $job = New-Object Microsoft.SqlServer.Management.Smo.Agent.Job -ArgumentList $nativeJobSource.JobServer, $caseJobName
            $job.IsEnabled = $false
            $job.Create()
            $job.ApplyToTargetServer([string]::Empty)
            $step = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobStep -ArgumentList $job, 'server-case'
            $step.SubSystem = 'TransactSql'
            $step.Server = $differentCase
            $step.DatabaseName = 'master'
            $step.Command = 'SELECT 1'
            $step.Create()
            $step.Refresh()
            $step.Server | Should -BeExactly $differentCase
            $job.Refresh()
            $job.JobType.ToString() | Should -BeExactly 'Local'
            $literal = "@server=N'" + $differentCase.Replace("'", "''") + "'"
            ($job.Script() -join [Environment]::NewLine).Contains($literal) | Should -BeTrue
            $result = @(Copy-DbaAgentJob -InputObject $job -Destination $nativeJobDestination -Confirm:$false -EnableException)
            $result.Count | Should -Be 1
            $result[0].Status | Should -BeExactly 'Successful'
            $nativeJobDestination.JobServer.Jobs.Refresh()
            $copied = $nativeJobDestination.JobServer.Jobs[$caseJobName]
            $copied.IsEnabled | Should -BeFalse
            $copied.JobSteps.Refresh()
            $copied.JobSteps['server-case'].Server | Should -BeExactly ([string]$nativeJobDestination.DomainInstanceName)
        } finally {
            foreach ($server in @($nativeJobSource, $nativeJobDestination)) {
                $server.JobServer.Jobs.Refresh()
                if ($server.JobServer.Jobs.Contains($caseJobName)) { $server.JobServer.Jobs[$caseJobName].Drop() }
            }
        }
    }

    It "restores alert links to the renamed destination job when forcing replacement" {
        $nativeJobResult = Copy-DbaAgentJob -Source $nativeJobSource -Destination $nativeJobDestination -Job $nativeJobNames[0] -NewName $nativeJobLinkName -Force -Confirm:$false -EnableException
        $nativeJobResult.Status | Should -Be "Successful"
        $nativeJobDestination.JobServer.Jobs.Refresh()
        $nativeJobDestination.JobServer.Alerts.Refresh()
        $nativeJobDestination.JobServer.Alerts[$nativeJobAlertName].JobID | Should -Be $nativeJobDestination.JobServer.Jobs[$nativeJobLinkName].JobID
    }

    It "preserves multiple pipeline jobs and explicit false switches" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:switch-false" {
        # Establish this test's existing-job precondition even when the wildcard regression fails.
        $nativeJobDestination.JobServer.Jobs.Refresh()
        if (-not $nativeJobDestination.JobServer.Jobs.Contains($nativeJobNames[0])) {
            $nativeJobExisting = New-Object Microsoft.SqlServer.Management.Smo.Agent.Job -ArgumentList $nativeJobDestination.JobServer, $nativeJobNames[0]
            $nativeJobExisting.IsEnabled = $false
            $nativeJobExisting.Create()
            $nativeJobExisting.ApplyToTargetServer([string]::Empty)
        }
        $nativeJobInput = @($nativeJobSource.JobServer.Jobs[$nativeJobNames[0]], $nativeJobSource.JobServer.Jobs[$nativeJobNames[1]])
        $nativeJobResult = @($nativeJobInput | Copy-DbaAgentJob -Destination $nativeJobDestination -Force:$false -DisableOnSource:$false -DisableOnDestination:$false -UseLastModified:$false -Confirm:$false)
        $nativeJobResult.Count | Should -Be 2
        $nativeJobResult.Name | Should -Be $nativeJobNames
        $nativeJobResult.Status | Should -Be @("Skipped", "Successful")
    }

    It "does not recreate or disable jobs with WhatIf and Force" -Tag "NativeChecklist:whatif-confirm" {
        $nativeJobDestination.JobServer.Jobs.Refresh()
        $nativeJobBeforeId = $nativeJobDestination.JobServer.Jobs[$nativeJobNames[0]].JobID
        $nativeJobResult = @(Copy-DbaAgentJob -Source $nativeJobSource -Destination $nativeJobDestination -Job $nativeJobNames[0] -Force -DisableOnSource -DisableOnDestination -WhatIf -Confirm:$false)
        $nativeJobResult.Count | Should -Be 0
        $nativeJobDestination.JobServer.Jobs.Refresh()
        $nativeJobDestination.JobServer.Jobs[$nativeJobNames[0]].JobID | Should -Be $nativeJobBeforeId
    }

    It "continues destination arrays after a connection failure" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception" {
        $nativeJobResult = @(Copy-DbaAgentJob -Source $nativeJobSource -Destination @($nativeJobDestination, "tcp:127.0.0.1,1", $nativeJobDestination) -Job $nativeJobNames[0] -Confirm:$false -EnableException:$false -WarningAction SilentlyContinue -WarningVariable nativeJobWarning)
        $nativeJobResult.Count | Should -Be 2
        $nativeJobResult.Status | Should -Be @("Skipped", "Skipped")
        ($nativeJobWarning -join " ") | Should -BeLike "*Failure*"
    }

    It "preserves the nested source warning and clears explicit input after failed discovery" -Tag "NativeChecklist:enable-exception" {
        # Copy-DbaAgentJob:164-174 omits EnableException; Get-DbaAgentJob:158-161 warns locally.
        foreach ($nativeSourceEnableException in @($false, $true)) {
            $nativeJobSourceWarnings = @()
            $nativeJobSourceErrors = @()
            $nativeJobSourceResult = @(Copy-DbaAgentJob -Source "tcp:127.0.0.1,1" -InputObject $nativeJobSource.JobServer.Jobs[$nativeJobNames[0]] -Destination $nativeJobDestination -Job $nativeJobNames[0] -Confirm:$false -EnableException:$nativeSourceEnableException -WarningAction SilentlyContinue -WarningVariable nativeJobSourceWarnings -ErrorVariable nativeJobSourceErrors)
            $nativeJobSourceResult.Count | Should -Be 0
            $nativeJobSourceErrors.Count | Should -Be 0
            $nativeJobSourceWarnings.Count | Should -Be 1
            $nativeJobSourceWarnings[0].Message | Should -Match '\[Get-DbaAgentJob\] Failure \| The remote computer refused the network connection\.?$'
        }
    }

    It "throws on destination connection failure with exceptions enabled" -Tag "NativeChecklist:enable-exception" {
        { Copy-DbaAgentJob -Source $nativeJobSource -Destination "tcp:127.0.0.1,1" -Job $nativeJobNames[0] -Confirm:$false -EnableException } | Should -Throw "*remote computer refused the network connection*"
    }

    Context "Uncaught source disable faults" {
        BeforeAll {
            $disableLogin = "native_job_reader_" + [guid]::NewGuid().ToString("N")
            $disableNames = @(($disableLogin + "_one"), ($disableLogin + "_two"))
            $disablePassword = "Nj!" + [guid]::NewGuid().ToString("N")
            $disableCredential = New-Object pscredential -ArgumentList $disableLogin, (ConvertTo-SecureString $disablePassword -AsPlainText -Force)
            $disableReader = $null
            $null = $nativeJobSource.ConnectionContext.ExecuteNonQuery("CREATE LOGIN [$disableLogin] WITH PASSWORD = N'$disablePassword', CHECK_POLICY = OFF; GRANT VIEW ANY DEFINITION TO [$disableLogin];")
            $null = $nativeJobSource.ConnectionContext.ExecuteNonQuery("USE msdb; CREATE USER [$disableLogin] FOR LOGIN [$disableLogin]; ALTER ROLE SQLAgentReaderRole ADD MEMBER [$disableLogin]; ALTER ROLE db_datareader ADD MEMBER [$disableLogin];")
            foreach ($name in $disableNames) {
                # No steps or schedules: these enabled fixture jobs cannot execute work.
                $job = New-Object Microsoft.SqlServer.Management.Smo.Agent.Job -ArgumentList $nativeJobSource.JobServer, $name
                $job.IsEnabled = $true
                $job.Create()
                $job.ApplyToTargetServer([string]::Empty)
            }
            $disableReader = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -SqlCredential $disableCredential -NonPooledConnection -EnableException
            $disableReader.JobServer.Jobs.Refresh()
            $deniedJob = $disableReader.JobServer.Jobs[$disableNames[0]]
            $deniedJob | Should -Not -BeNullOrEmpty
            $null = $deniedJob.Script()
            $deniedJob.IsEnabled = $false
            { $deniedJob.Alter() } | Should -Throw
            $deniedJob.Refresh()
            $deniedJob.IsEnabled | Should -BeTrue

            function Invoke-NativeJobDisableFault {
                param([string]$Mode)
                # A direct pipeline in a new runspace has no Pester caller try around it.
                $state = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
                $type = (Get-Command $CommandName -CommandType Cmdlet).ImplementingType
                $entry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList $CommandName, $type, $null
                $state.Commands.Add($entry)
                $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($state)
                $shell = [System.Management.Automation.PowerShell]::Create()
                $output = New-Object "System.Management.Automation.PSDataCollection[psobject]"
                try {
                    $runspace.Open()
                    $shell.Runspace = $runspace
                    $body = {
                        param($Jobs, $Destination, $FaultMode)
                        $ErrorActionPreference = "Continue"
                        $Error.Clear()
                        $global:disableFaultErrors = @()
                        $parameters = @{
                            InputObject = $Jobs
                            Destination = $Destination
                            DisableOnSource = $true
                            Confirm = $false
                            EnableException = ($FaultMode -eq "enable")
                            ErrorAction = $(if ($FaultMode -eq "stop") { "Stop" } elseif ($FaultMode -eq "silent") { "SilentlyContinue" } else { "Continue" })
                            ErrorVariable = "global:disableFaultErrors"
                        }
                        if ($FaultMode -eq "try") {
                            try { Copy-DbaAgentJob @parameters; "not caught" }
                            catch { [pscustomobject]@{ Caught = $PSItem } }
                        } else { Copy-DbaAgentJob @parameters }
                        "next statement"
                    }
                    $null = $shell.AddScript($body.ToString()).AddArgument($disableInput).AddArgument($nativeJobDestination).AddArgument($Mode)
                    $stop = $null
                    try { $null = $shell.Invoke($null, $output) }
                    catch { $stop = $PSItem.Exception.InnerException }
                    [pscustomobject]@{
                        State = $shell.InvocationStateInfo.State.ToString()
                        Output = @($output)
                        Errors = @($shell.Streams.Error)
                        Warnings = @($shell.Streams.Warning)
                        ErrorVariable = @($runspace.SessionStateProxy.GetVariable("disableFaultErrors"))
                        History = @($runspace.SessionStateProxy.GetVariable("Error"))
                        Stop = $stop
                    }
                } finally {
                    $shell.Dispose()
                    $runspace.Dispose()
                }
            }

            function Assert-NativeDisableRecord {
                param($Entry, $Reference, [string]$EntryType = "ErrorRecord")
                $Entry.GetType().FullName | Should -BeExactly "System.Management.Automation.$EntryType"
                $record = $Entry
                if ($Entry -is [System.Management.Automation.IContainsErrorRecord]) { $record = $Entry.ErrorRecord }
                $record.FullyQualifiedErrorId | Should -BeExactly "FailedOperationException,Dataplat.Dbatools.Commands.CopyDbaAgentJobCommand"
                $record.CategoryInfo.Category | Should -Be $Reference.CategoryInfo.Category
                $record.CategoryInfo.Reason | Should -BeExactly $Reference.CategoryInfo.Reason
                $record.CategoryInfo.Activity | Should -BeExactly "Copy-DbaAgentJob"
                $record.CategoryInfo.TargetName | Should -BeExactly $Reference.CategoryInfo.TargetName
                $record.CategoryInfo.TargetType | Should -BeExactly $Reference.CategoryInfo.TargetType
                $record.TargetObject | Should -Be $Reference.TargetObject
                $actualException = $record.Exception
                $expectedException = $Reference.Exception
                while ($expectedException) {
                    $actualException | Should -Not -BeNullOrEmpty
                    $actualException.GetType().FullName | Should -BeExactly $expectedException.GetType().FullName
                    $actualException.Message | Should -BeExactly $expectedException.Message
                    $actualException = $actualException.InnerException
                    $expectedException = $expectedException.InnerException
                }
                $actualException | Should -BeNullOrEmpty
            }

            function Clear-NativeDisableDestination {
                $nativeJobDestination.JobServer.Jobs.Refresh()
                foreach ($name in $disableNames) {
                    if ($nativeJobDestination.JobServer.Jobs.Contains($name)) { $nativeJobDestination.JobServer.Jobs[$name].Drop() }
                }
            }
        }

        BeforeEach {
            $disableReader.JobServer.Jobs.Refresh()
            $disableInput = @($disableReader.JobServer.Jobs[$disableNames[0]], $disableReader.JobServer.Jobs[$disableNames[1]])
            # The same SMO Alter call supplies a live reference for each job's complete fault content.
            $disableReferences = @(foreach ($job in $disableInput) {
                $job.Refresh()
                $job.IsEnabled | Should -BeTrue
                $job.IsEnabled = $false
                try { $job.Alter(); throw "The reader unexpectedly altered an administrator-owned job." }
                catch { $PSItem }
                $job.Refresh()
                $job.IsEnabled | Should -BeTrue
            })
            $disableReferences.Count | Should -Be 2
            foreach ($record in $disableReferences) { $record.FullyQualifiedErrorId | Should -BeExactly "FailedOperationException" }
        }

        AfterEach { Clear-NativeDisableDestination }

        AfterAll {
            if ($disableReader) { $disableReader.ConnectionContext.Disconnect() }
            foreach ($server in @($nativeJobSource, $nativeJobDestination)) {
                $server.JobServer.Jobs.Refresh()
                foreach ($name in $disableNames) {
                    if ($server.JobServer.Jobs.Contains($name)) { $server.JobServer.Jobs[$name].Drop() }
                }
            }
            $null = $nativeJobSource.ConnectionContext.ExecuteNonQuery("USE msdb; IF USER_ID(N'$disableLogin') IS NOT NULL DROP USER [$disableLogin];")
            $null = $nativeJobSource.ConnectionContext.ExecuteNonQuery("IF SUSER_ID(N'$disableLogin') IS NOT NULL DROP LOGIN [$disableLogin];")
        }

        It "preserves source disable fault records and continuation in <Mode> mode" -Tag NativeChecklist:switch-false, NativeChecklist:enable-exception -TestCases @(
            @{ Mode = "plain" }, @{ Mode = "silent" }, @{ Mode = "try" }, @{ Mode = "enable" }, @{ Mode = "stop" }
        ) {
            param($Mode)
            # Measured pin/native on both editions: probe disable-fault-records-20261117.ps1.
            # Engine wrappers/copies follow the installed 2026-11-12 contract; EE and EA Stop
            # follow keep-going point 3. Assert the complete sequences without filtering entries.
            $result = Invoke-NativeJobDisableFault -Mode $Mode
            $continues = $Mode -in @("plain", "silent")
            $result.Warnings.Count | Should -Be 0
            $result.Output[0].Name | Should -BeExactly $disableNames[0]
            $result.Output[0].Status | Should -BeExactly "Successful"
            if ($Mode -eq "stop") {
                $result.State | Should -BeExactly "Failed"
                $result.Stop | Should -Not -BeNullOrEmpty
                Assert-NativeDisableRecord $result.Stop.ErrorRecord $disableReferences[0]
                $result.Output.Count | Should -Be 1
            } else {
                $result.State | Should -BeExactly "Completed"
                $result.Stop | Should -BeNullOrEmpty
                $result.Output[-1] | Should -BeExactly "next statement"
                $result.Output.Count | Should -Be $(if ($Mode -eq "enable") { 2 } else { 3 })
                if ($continues) {
                    $result.Output[1].Name | Should -BeExactly $disableNames[1]
                    $result.Output[1].Status | Should -BeExactly "Successful"
                } elseif ($Mode -eq "try") {
                    Assert-NativeDisableRecord $result.Output[1].Caught $disableReferences[0]
                }
            }
            $result.Errors.Count | Should -Be $(if ($Mode -eq "plain") { 2 } elseif ($Mode -eq "enable") { 1 } else { 0 })
            for ($index = 0; $index -lt $result.Errors.Count; $index++) {
                Assert-NativeDisableRecord $result.Errors[$index] $disableReferences[$index]
            }
            if ($continues) {
                $result.ErrorVariable.Count | Should -Be 2
                $result.History.Count | Should -Be 2
                Assert-NativeDisableRecord $result.ErrorVariable[0] $disableReferences[0]
                Assert-NativeDisableRecord $result.ErrorVariable[1] $disableReferences[1]
                Assert-NativeDisableRecord $result.History[0] $disableReferences[1]
                Assert-NativeDisableRecord $result.History[1] $disableReferences[0]
            } elseif ($Mode -eq "stop") {
                $result.ErrorVariable.Count | Should -Be 1
                $result.History.Count | Should -Be 2
                Assert-NativeDisableRecord $result.ErrorVariable[0] $disableReferences[0] "ActionPreferenceStopException"
                Assert-NativeDisableRecord $result.History[0] $disableReferences[0] "ActionPreferenceStopException"
                Assert-NativeDisableRecord $result.History[1] $disableReferences[0]
            } else {
                $result.ErrorVariable.Count | Should -Be 1
                $result.History.Count | Should -Be 1
                Assert-NativeDisableRecord $result.ErrorVariable[0] $disableReferences[0] "CmdletInvocationException"
                Assert-NativeDisableRecord $result.History[0] $disableReferences[0]
            }
            $nativeJobSource.JobServer.Jobs.Refresh()
            foreach ($name in $disableNames) { $nativeJobSource.JobServer.Jobs[$name].IsEnabled | Should -BeTrue }
            $nativeJobDestination.JobServer.Jobs.Refresh()
            $nativeJobDestination.JobServer.Jobs[$disableNames[0]].IsEnabled | Should -BeTrue
            $nativeJobDestination.JobServer.Jobs.Contains($disableNames[1]) | Should -Be $continues
            if ($continues) { $nativeJobDestination.JobServer.Jobs[$disableNames[1]].IsEnabled | Should -BeTrue }
        }
    }
}
