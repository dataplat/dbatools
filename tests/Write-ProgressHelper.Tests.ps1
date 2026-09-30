#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Write-ProgressHelper",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    BeforeAll {
        # The helper runs in a runspace of its own, created by the PowerShell API without a host. There the
        # real Write-Progress sends every record into Streams.Progress, with its own parameter validation,
        # whatever $ProgressPreference or console host the test run itself has. Nothing is mocked.
        $testModulePath = (Get-Module -Name $ModuleName | Select-Object -First 1).Path
        $testRunspace = [runspacefactory]::CreateRunspace()
        $testRunspace.Open()
        $importShell = [powershell]::Create()
        $importShell.Runspace = $testRunspace
        $importedModule = $importShell.AddCommand("Import-Module").AddParameter("Name", $testModulePath).AddParameter("PassThru").Invoke() | Select-Object -First 1
        $importShell.Dispose()
        # Get-Module can return more than one module named dbatools there, so the scripts use this one
        $testRunspace.SessionStateProxy.SetVariable("progressTestModule", $importedModule)

        # Runs the scriptblock inside the dbatools module in the test runspace, or outside of it with -OutsideModule,
        # and returns its output, errors and progress records
        function Invoke-ProgressScript ([scriptblock]$ScriptBlock, [switch]$OutsideModule) {
            $shell = [powershell]::Create()
            $shell.Runspace = $testRunspace
            if ($OutsideModule) {
                $null = $shell.AddScript($ScriptBlock.ToString())
            } else {
                $null = $shell.AddScript("& `$progressTestModule { $($ScriptBlock.ToString()) }")
            }
            $thrown = $output = $null
            try {
                $output = $shell.Invoke()
            } catch {
                $thrown = $PSItem.Exception.InnerException
            }
            [PSCustomObject]@{
                Output  = @($output)
                Records = @($shell.Streams.Progress)
                Errors  = @($shell.Streams.Error) + @($thrown | Where-Object { $PSItem })
            }
            $shell.Dispose()
        }
    }

    AfterAll {
        $testRunspace.Dispose()
    }

    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Invoke-ProgressScript -ScriptBlock { (Get-Command Write-ProgressHelper).Parameters.Keys }).Output
            $expectedParameters = @(
                "StepNumber",
                "Activity",
                "Message",
                "TotalSteps",
                "ExcludePercent",
                "Id",
                "ParentId",
                "Completed"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Owned bars" {
        It "Completes the child bar it owns and leaves the parent bar running" {
            $result = Invoke-ProgressScript -ScriptBlock {
                Write-ProgressHelper -Id 1 -Activity "Parent" -StepNumber 1 -TotalSteps 2 -Message "Parent step"
                Write-ProgressHelper -Id 2 -ParentId 1 -Activity "Child" -StepNumber 1 -TotalSteps 2 -Message "Child step"
                Write-ProgressHelper -Id 2 -Activity "Child" -Completed
            }
            $result.Errors | Should -BeNullOrEmpty
            $childRecord = $result.Records | Where-Object ActivityId -eq 2 | Select-Object -First 1
            $childRecord.ParentActivityId | Should -Be 1
            $completedIds = ($result.Records | Where-Object RecordType -eq "Completed").ActivityId
            $completedIds | Should -Be @(2)
        }

        It "Completes the bar of its Id, whatever Activity text the completion carries" {
            $result = Invoke-ProgressScript -ScriptBlock {
                Write-ProgressHelper -Id 3 -Activity "Started with this text" -StepNumber 1 -TotalSteps 2 -Message "Step"
                Write-ProgressHelper -Id 3 -Completed
            }
            $result.Errors | Should -BeNullOrEmpty
            $completedRecord = $result.Records | Where-Object RecordType -eq "Completed"
            $completedRecord.ActivityId | Should -Be 3
        }
    }

    Context "Values Write-Progress refuses" {
        It "Caps the percentage at 100 when the step number outruns the total" {
            $result = Invoke-ProgressScript -ScriptBlock { Write-ProgressHelper -StepNumber 150 -TotalSteps 100 -Message "Too far" }
            $result.Errors | Should -BeNullOrEmpty
            $result.Records[0].PercentComplete | Should -Be 100
        }

        It "Writes the bar when the message is empty" {
            $result = Invoke-ProgressScript -ScriptBlock {
                Write-ProgressHelper -Activity "Empty message" -StepNumber 1 -TotalSteps 2 -Message ""
                Write-ProgressHelper -Activity "Empty message" -ExcludePercent -Message ""
            }
            $result.Errors | Should -BeNullOrEmpty
            $result.Records.Count | Should -Be 2
        }
    }

    Context "Activity and total steps from the caller" {
        It "Uses the activity text of the caller once" {
            $result = Invoke-ProgressScript -ScriptBlock {
                function Invoke-DbaDbLogShipRecovery {
                    Write-ProgressHelper -StepNumber 1 -TotalSteps 2 -Message "Step"
                }
                Invoke-DbaDbLogShipRecovery
            }
            $result.Errors | Should -BeNullOrEmpty
            $result.Records[0].Activity | Should -BeExactly "Performing log shipping recovery"
        }

        It "Counts only the calls of the caller that report a step" {
            # Defined inside the module, so the helper finds it as a dbatools command and counts its calls
            $result = Invoke-ProgressScript -ScriptBlock {
                function Invoke-ProgressHelperStepCaller {
                    Write-ProgressHelper -StepNumber 1 -Message "First step"
                    Write-ProgressHelper -StepNumber 2 -Message "Second step"
                    Write-ProgressHelper -Completed
                }
                Invoke-ProgressHelperStepCaller
            }
            $result.Errors | Should -BeNullOrEmpty
            $result.Records[0].PercentComplete | Should -Be 50
            $result.Records[1].PercentComplete | Should -Be 100
        }

        It "Writes the bar without a percentage when the caller is not a dbatools command" {
            # Defined outside the module, so Get-Command -Module dbatools cannot find it
            $result = Invoke-ProgressScript -OutsideModule -ScriptBlock {
                function Invoke-ProgressHelperForeignCaller {
                    & $progressTestModule Write-ProgressHelper -StepNumber 1 -Message "Step"
                }
                Invoke-ProgressHelperForeignCaller
            }
            $result.Errors | Should -BeNullOrEmpty
            $result.Records[0].PercentComplete | Should -Be 0
        }
    }
}
