#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Test-FunctionInterrupt",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Private caller interruption latch" {
    BeforeAll {
        $interruptModule = Get-Module dbatools | Where-Object ModuleType -eq Script

        function Invoke-InterruptFixture {
            param($Fixture)
            $fixtureData = $Fixture.Clone()
            foreach ($fixtureKey in @("CallerHasLatch", "ParentHasLatch", "Reread")) {
                if (-not $fixtureData.ContainsKey($fixtureKey)) { $fixtureData[$fixtureKey] = $false }
            }
            foreach ($fixtureValueKey in @("CallerValue", "ParentValue")) {
                if (-not $fixtureData.ContainsKey($fixtureValueKey)) { $fixtureData[$fixtureValueKey] = $null }
            }
            $fixtureState = @{
                ReachedAfter       = $false
                ReachedAfterFirst  = $false
                Termination        = $null
                Errors             = @()
                CallerUnchanged    = $false
                ParentUnchanged    = $false
                ContainerUnchanged = $false
                CleanupVerified    = $false
            }
            $fixtureStreams = @(& $interruptModule {
                param($containerCase, $containerState)
                $ErrorActionPreference = "Continue"
                $containerLatch = "__dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r"
                $splatContainerRead = @{
                    Name        = $containerLatch
                    Scope       = "Local"
                    ErrorAction = "Ignore"
                }
                $containerBefore = Get-Variable @splatContainerRead
                $containerValue = if ($null -ne $containerBefore) { $containerBefore.Value } else { $null }
                if (Get-Item Function:Invoke-InterruptParentFixture -ErrorAction Ignore) { throw "Fixture function already exists" }
                function Invoke-InterruptParentFixture {
                    param($parentCase, $parentState, $parentLatch)
                    $splatParentRead = @{
                        Name        = $parentLatch
                        Scope       = "Local"
                        ErrorAction = "Ignore"
                    }
                    if ($parentCase.ParentHasLatch) {
                        $splatParentWrite = @{
                            Name  = $parentLatch
                            Scope = "Local"
                            Value = $parentCase.ParentValue
                        }
                        Set-Variable @splatParentWrite
                    }
                    $parentBefore = Get-Variable @splatParentRead
                    $parentValue = if ($null -ne $parentBefore) { $parentBefore.Value } else { $null }
                    function Invoke-InterruptCallerFixture {
                        param($callerCase, $callerState, $callerLatch)
                        $splatCallerRead = @{
                            Name        = $callerLatch
                            Scope       = "Local"
                            ErrorAction = "Ignore"
                        }
                        if ($callerCase.CallerHasLatch) {
                            $splatCallerWrite = @{
                                Name  = $callerLatch
                                Scope = "Local"
                                Value = $callerCase.CallerValue
                            }
                            Set-Variable @splatCallerWrite
                        }
                        $callerBefore = Get-Variable @splatCallerRead
                        $callerValue = if ($null -ne $callerBefore) { $callerBefore.Value } else { $null }
                        $callerErrors = @()
                        try {
                            Test-FunctionInterrupt -ErrorVariable +callerErrors
                            $callerState.ReachedAfterFirst = $true
                            if ($callerCase.Reread) {
                                $splatCallerRemove = @{
                                    Name        = $callerLatch
                                    Scope       = "Local"
                                    ErrorAction = "Stop"
                                }
                                Remove-Variable @splatCallerRemove
                                Test-FunctionInterrupt -ErrorVariable +callerErrors
                            }
                            $callerState.ReachedAfter = $true
                        } catch { $callerState.Termination = $PSItem }
                        finally {
                            $callerState.Errors = @($callerErrors)
                            $callerAfter = Get-Variable @splatCallerRead
                            $callerAfterValue = if ($null -ne $callerAfter) { $callerAfter.Value } else { $null }
                            if ($callerCase.Reread -and $callerState.ReachedAfterFirst) { $callerState.CallerUnchanged = $null -eq $callerAfter }
                            else { $callerState.CallerUnchanged = [object]::ReferenceEquals($callerBefore, $callerAfter) -and [object]::Equals($callerValue, $callerAfterValue) }
                        }
                    }
                    $splatCaller = @{
                        callerCase  = $parentCase
                        callerState = $parentState
                        callerLatch = $parentLatch
                    }
                    Invoke-InterruptCallerFixture @splatCaller
                    $parentAfter = Get-Variable @splatParentRead
                    $parentAfterValue = if ($null -ne $parentAfter) { $parentAfter.Value } else { $null }
                    $parentState.ParentUnchanged = [object]::ReferenceEquals($parentBefore, $parentAfter) -and [object]::Equals($parentValue, $parentAfterValue)
                }
                try {
                    $splatParent = @{
                        parentCase  = $containerCase
                        parentState = $containerState
                        parentLatch = $containerLatch
                    }
                    Invoke-InterruptParentFixture @splatParent
                } finally {
                    Remove-Item Function:Invoke-InterruptParentFixture -ErrorAction Stop
                    $containerAfter = Get-Variable @splatContainerRead
                    $containerAfterValue = if ($null -ne $containerAfter) { $containerAfter.Value } else { $null }
                    $containerState.ContainerUnchanged = [object]::ReferenceEquals($containerBefore, $containerAfter) -and [object]::Equals($containerValue, $containerAfterValue)
                    $containerState.CleanupVerified = $null -eq (Get-Item Function:Invoke-InterruptParentFixture -ErrorAction Ignore)
                }
            } $fixtureData $fixtureState 6>&1 5>&1 4>&1 3>&1 2>&1)
            [pscustomobject]@{
                Streams = $fixtureStreams
                State   = $fixtureState
            }
        }
    }

    It "retains private parameterless Boolean metadata" {
        $interruptCommand = & $interruptModule { Get-Command Test-FunctionInterrupt }
        $interruptCommand.CommandType | Should -Be "Cmdlet"
        $interruptCommand.ImplementingType.FullName | Should -BeExactly "Dataplat.Dbatools.Commands.TestFunctionInterruptCommand"
        $interruptCommand.ImplementingType.Assembly | Should -Be ([Dataplat.Dbatools.Commands.DbaBaseCmdlet].Assembly)
        Compare-Object @([Management.Automation.PSCmdlet]::CommonParameters) @($interruptCommand.Parameters.Keys) | Should -BeNullOrEmpty
        @($interruptCommand.OutputType).Count | Should -Be 1
        $interruptCommand.OutputType[0].Name | Should -BeExactly "System.Boolean"
        # The pinned test helper intentionally reimports the psm1 to expose private commands.
        $interruptManifest = Import-PowerShellDataFile (Join-Path $interruptModule.ModuleBase "dbatools.psd1")
        $interruptManifest.CmdletsToExport | Should -Not -Contain "Test-FunctionInterrupt"
        $interruptManifest.CmdletsToExport | Should -Not -Contain "*"
    }

    It "preserves the observed scalar truth conversion" {
        foreach ($scalarCase in @(
            @{ CallerHasLatch = $false; Expected = $false },
            @{ CallerHasLatch = $true; CallerValue = $false; Expected = $false },
            @{ CallerHasLatch = $true; CallerValue = $true; Expected = $true },
            @{ CallerHasLatch = $true; CallerValue = 0; Expected = $false },
            @{ CallerHasLatch = $true; CallerValue = "False"; Expected = $true }
        )) {
            $scalarResult = Invoke-InterruptFixture $scalarCase
            $scalarResult.Streams.Count | Should -Be 1
            $scalarResult.Streams[0] | Should -BeOfType System.Boolean
            $scalarResult.Streams[0] | Should -Be $scalarCase.Expected
            $scalarResult.State.Errors.Count | Should -Be 0
            $scalarResult.State.Termination | Should -BeNullOrEmpty
            foreach ($scalarFlag in @("ReachedAfter", "CallerUnchanged", "ParentUnchanged", "ContainerUnchanged", "CleanupVerified")) { $scalarResult.State[$scalarFlag] | Should -BeTrue }
        }
    }

    It "reads only the immediate caller latch without inheriting an ancestor latch" {
        foreach ($scopeCase in @(
            @{ ParentHasLatch = $true; ParentValue = $true; CallerHasLatch = $false; Expected = $false },
            @{ ParentHasLatch = $true; ParentValue = $true; CallerHasLatch = $true; CallerValue = $false; Expected = $false },
            @{ ParentHasLatch = $true; ParentValue = $false; CallerHasLatch = $true; CallerValue = $true; Expected = $true }
        )) {
            $scopeResult = Invoke-InterruptFixture $scopeCase
            $scopeResult.Streams.Count | Should -Be 1
            $scopeResult.Streams[0] | Should -BeOfType System.Boolean
            $scopeResult.Streams[0] | Should -Be $scopeCase.Expected
            $scopeResult.State.Errors.Count | Should -Be 0
            $scopeResult.State.Termination | Should -BeNullOrEmpty
            foreach ($scopeFlag in @("ReachedAfter", "CallerUnchanged", "ParentUnchanged", "ContainerUnchanged", "CleanupVerified")) { $scopeResult.State[$scopeFlag] | Should -BeTrue }
        }
    }

    It "re-reads the same caller after its local latch is removed" {
        $rereadResult = Invoke-InterruptFixture @{ CallerHasLatch = $true; CallerValue = $true; Reread = $true }
        $rereadResult.Streams.Count | Should -Be 2
        $rereadResult.Streams[0] | Should -BeOfType System.Boolean
        $rereadResult.Streams[1] | Should -BeOfType System.Boolean
        $rereadResult.Streams[0] | Should -BeTrue
        $rereadResult.Streams[1] | Should -BeFalse
        $rereadResult.State.Errors.Count | Should -Be 0
        $rereadResult.State.Termination | Should -BeNullOrEmpty
        foreach ($rereadFlag in @("ReachedAfterFirst", "ReachedAfter", "CallerUnchanged", "ParentUnchanged", "ContainerUnchanged", "CleanupVerified")) { $rereadResult.State[$rereadFlag] | Should -BeTrue }
    }
}
