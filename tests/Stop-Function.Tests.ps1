#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Stop-Function",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    BeforeAll {
        $PSDefaultParameterValues.Remove("*:WarningAction")
    }

    AfterAll {
        $PSDefaultParameterValues["*:WarningAction"] = "SilentlyContinue"
    }

    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Message",
                "Category",
                "ErrorRecord",
                "Tag",
                "FunctionName",
                "File",
                "Line",
                "Target",
                "Exception",
                "OverrideExceptionMessage",
                "Continue",
                "SilentlyContinue",
                "ContinueLabel",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Testing non-EnableException: Explicit call" {
        BeforeAll {
            try {
                $result = Stop-Function -WarningAction Continue -Message "Nonsilent Foo" -EnableException $false -Category InvalidResult -FunctionName "Invoke-Pester" -Target "Bar" -ErrorAction Stop 3>&1
                $record = $Error[0]
                $failed = $false
            } catch {
                $record = $null
                $failed = $true
            }
        }

        It "Should not have failed to execute without an exception." {
            $failed | Should -Be $false
        }

        It "Should have written the test warning 'Nonsilent Foo'" {
            $result[0] | Should -BeLike "*Nonsilent Foo"
        }

        It "Should have created an error record with the correct exception" {
            $record.Exception.Message | Should -Be "Nonsilent Foo"
        }

        It "Should have created an error record with the caegory 'InvalidResult'" {
            $record.CategoryInfo.Category | Should -BeLike "InvalidResult"
        }

        It "Should have created an error record with the targetobject 'Bar'" {
            $record.TargetObject | Should -Be "Bar"
        }

        It "Should have created an error record with the ErrorID 'dbatools_Invoke-Pester'" {
            $record.FullyQualifiedErrorId | Should -Be "dbatools_Invoke-Pester,Stop-Function"
        }
    }

    Context "Testing non-EnableException: In try/catch" {
        BeforeAll {
            try {
                try {
                    $null.GetType()
                } catch {
                    $result = Stop-Function -WarningAction Continue -Message "Nonsilent Foo" -EnableException $false -ErrorRecord $PSItem -FunctionName "Invoke-Pester" -Target "Bar" -ErrorAction Stop 3>&1
                    $record = $Error[0]
                    $failed = $false
                }
            } catch {
                $record = $null
                $failed = $true
            }
        }

        It "Should not have failed to execute without an exception." {
            $failed | Should -Be $false
        }

        It "Should have written the test warning 'Nonsilent Foo | '" {
            $result[0] | Should -BeLike "*Nonsilent Foo | *"
        }

        It "Should have created an error record with the correct exception" {
            $record.Exception.InnerException.GetType().FullName | Should -Be "System.Management.Automation.RuntimeException"
        }

        It "Should have created an error record with the category 'InvalidOperation'" {
            $record.CategoryInfo.Category | Should -BeLike "InvalidOperation"
        }

        It "Should have created an error record with the targetobject 'Bar'" {
            $record.TargetObject | Should -Be "Bar"
        }

        It "Should have created an error record with the ErrorID 'dbatools_Invoke-Pester'" {
            $record.FullyQualifiedErrorId | Should -Be "dbatools_Invoke-Pester,Stop-Function"
        }

        It "Should have created an error record with the an inner NULL-invocation exception" {
            try {
                $ExceptionName = $record.Exception.InnerException.GetType().FullName
            } catch {
                $ExceptionName = "Meeep."
            }

            $ExceptionName | Should -Be "System.Management.Automation.RuntimeException"
        }
    }

    Context "Testing non-EnableException: Continue & ContinueLabel" {
        BeforeAll {
            Mock -CommandName "Write-Warning" -MockWith { param ($Message) }

            #region Run Tests
            try {
                $failed = $false
                $a = 0
                $b = 0
                foreach ($number in (1 .. 3)) {
                    $a++
                    Stop-Function -Message "Nonsilent Foo" -EnableException $false -Category InvalidOperation -Continue -ErrorAction Stop 3>&1
                    $b++
                }
            } catch {
                $failed = $true
            }

            try {
                $failed2 = $false
                $c = 0
                $d = 0
                $e = 0
                $f = 0

                :main foreach ($number in (1 .. 3)) {
                    $c++
                    foreach ($Counter in (1 .. 3)) {
                        $d++
                        Stop-Function -Message "Nonsilent Foo" -EnableException $false -Category InvalidOperation -Continue -ContinueLabel "main" -ErrorAction Stop 3>&1
                        $e++
                    }
                    $f++
                }
            } catch {
                $failed2 = $true
            }
            #endregion Run Tests
        }

        #region Evaluate Results
        It "Should not have failed to execute without an exception when testing Continue without a label." {
            $failed | Should -Be $false
        }

        It "Should not have failed to execute without an exception when testing Continue with a label." {
            $failed2 | Should -Be $false
        }

        It "Should have incremented the first counter when calling continue without a label" {
            $a | Should -Be 3
        }

        It "Should not have incremented the second counter when calling continue without a label" {
            $b | Should -Be 0
        }

        It "Should have incremented the first two counters thrice, but skipped the other two when calling continue with a label" {
            [int[]]$result = @($c, $d, $e, $f)
            [int[]]$reference = @(3, 3, 0, 0)
            $result | Should -Be $reference
        }
        #endregion Evaluate Results
    }

    Context "Nested command interrupt beacon" -Tag InterruptBeacon {
        It "Records a direct hard stop from a parameterized command scope" {
            $beacon = @{
                Interrupted              = $false
                CallerCommand            = $null
                CallerHasBoundParameters = $false
                CommandName              = "Invoke-DirectNestedStop"
            }
            $module = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1

            $result = & $module {
                param($beacon)
                Set-Variable -Name "__dbatools_nested_interrupt_beacon_q7N4v2" -Scope Script -Value $beacon -Force
                try {
                    function Invoke-DirectNestedStop {
                        [CmdletBinding()]
                        param()
                        Stop-Function -Message "nested stop" -FunctionName Invoke-DirectNestedStop -EnableException $false -WarningAction SilentlyContinue
                    }
                    Invoke-DirectNestedStop
                    $beacon
                } finally {
                    Remove-Variable -Name "__dbatools_nested_interrupt_beacon_q7N4v2" -Scope Script -Force -ErrorAction Ignore
                }
            } $beacon

            $result.Interrupted | Should -BeTrue
            $result.CallerCommand | Should -Be "Invoke-DirectNestedStop"
            $result.CallerHasBoundParameters | Should -BeTrue
        }

        It "Does not record a -Continue stop" {
            $beacon = @{
                Interrupted              = $false
                CallerCommand            = $null
                CallerHasBoundParameters = $false
                CommandName              = "Invoke-ContinueNestedStop"
            }
            $module = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1

            $result = & $module {
                param($beacon)
                Set-Variable -Name "__dbatools_nested_interrupt_beacon_q7N4v2" -Scope Script -Value $beacon -Force
                try {
                    function Invoke-ContinueNestedStop {
                        [CmdletBinding()]
                        param()
                        foreach ($item in 1) {
                            Stop-Function -Message "nested continue" -FunctionName Invoke-ContinueNestedStop -EnableException $false -Continue -WarningAction SilentlyContinue
                        }
                    }
                    Invoke-ContinueNestedStop
                    $beacon
                } finally {
                    Remove-Variable -Name "__dbatools_nested_interrupt_beacon_q7N4v2" -Scope Script -Force -ErrorAction Ignore
                }
            } $beacon

            $result.Interrupted | Should -BeFalse
            $result.CallerHasBoundParameters | Should -BeFalse
        }

        It "Rejects a stop attributed through a named helper" {
            $beacon = @{
                Interrupted              = $false
                CallerCommand            = $null
                CallerHasBoundParameters = $false
                CommandName              = "Invoke-OuterNestedStop"
            }
            $module = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1

            $result = & $module {
                param($beacon)
                Set-Variable -Name "__dbatools_nested_interrupt_beacon_q7N4v2" -Scope Script -Value $beacon -Force
                try {
                    function Invoke-NamedStopHelper {
                        [CmdletBinding()]
                        param()
                        Stop-Function -Message "helper stop" -FunctionName Invoke-OuterNestedStop -EnableException $false -WarningAction SilentlyContinue
                    }
                    function Invoke-OuterNestedStop {
                        [CmdletBinding()]
                        param()
                        Invoke-NamedStopHelper
                    }
                    Invoke-OuterNestedStop
                    $beacon
                } finally {
                    Remove-Variable -Name "__dbatools_nested_interrupt_beacon_q7N4v2" -Scope Script -Force -ErrorAction Ignore
                }
            } $beacon

            $result.Interrupted | Should -BeTrue
            $result.CallerCommand | Should -Be "Invoke-NamedStopHelper"
            ($result.CallerCommand -eq $result.CommandName) | Should -BeFalse
        }

        It "Keeps nested beacons independent and restores the outer positive control" {
            $outer = @{
                Interrupted              = $false
                CallerCommand            = $null
                CallerHasBoundParameters = $false
                CommandName              = "Invoke-OuterBeaconStop"
            }
            $inner = @{
                Interrupted              = $false
                CallerCommand            = $null
                CallerHasBoundParameters = $false
                CommandName              = "Invoke-InnerBeaconStop"
            }
            $module = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1

            $result = & $module {
                param($outer, $inner)
                function Invoke-OuterBeaconStop {
                    [CmdletBinding()]
                    param()
                    Stop-Function -Message "outer stop" -FunctionName Invoke-OuterBeaconStop -EnableException $false -WarningAction SilentlyContinue
                }
                function Invoke-InnerBeaconStop {
                    [CmdletBinding()]
                    param()
                    Stop-Function -Message "inner stop" -FunctionName Invoke-InnerBeaconStop -EnableException $false -WarningAction SilentlyContinue
                }

                Set-Variable -Name "__dbatools_nested_interrupt_beacon_q7N4v2" -Scope Script -Value $outer -Force
                try {
                    Set-Variable -Name "__dbatools_nested_interrupt_beacon_q7N4v2" -Scope Script -Value $inner -Force
                    Invoke-InnerBeaconStop
                    $outerBefore = $outer.Interrupted
                    Set-Variable -Name "__dbatools_nested_interrupt_beacon_q7N4v2" -Scope Script -Value $outer -Force
                    Invoke-OuterBeaconStop
                    [pscustomobject]@{
                        InnerInterrupted = $inner.Interrupted
                        OuterBefore       = $outerBefore
                        OuterAfter        = $outer.Interrupted
                    }
                } finally {
                    Remove-Variable -Name "__dbatools_nested_interrupt_beacon_q7N4v2" -Scope Script -Force -ErrorAction Ignore
                }
            } $outer $inner

            $result.InnerInterrupted | Should -BeTrue
            $result.OuterBefore | Should -BeFalse
            $result.OuterAfter | Should -BeTrue
        }

        It "Leaves an unported call inert when no beacon is installed" {
            $module = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
            {
                & $module {
                    Remove-Variable -Name "__dbatools_nested_interrupt_beacon_q7N4v2" -Scope Script -Force -ErrorAction Ignore
                    function Invoke-UnportedStop {
                        [CmdletBinding()]
                        param()
                        Stop-Function -Message "unported stop" -FunctionName Invoke-UnportedStop -EnableException $false -WarningAction SilentlyContinue
                    }
                    Invoke-UnportedStop
                }
            } | Should -Not -Throw
        }
    }

    Context "Testing silent: Explicit call" {
        BeforeAll {
            try {
                Stop-Function -Message "Nonsilent Foo" -EnableException $true -Category InvalidResult -FunctionName "Invoke-Pester" -Target "Bar" -ErrorAction Stop
                $record = $null
                $failed = $false
            } catch {
                $record = $PSItem
                $failed = $true
            }
        }

        It "Should not have failed to terminate with an exception." {
            $failed | Should -Be $true
        }

        It "Should have created an error record with the correct exception" {
            $record.Exception.Message | Should -Be "Nonsilent Foo"
        }

        It "Should have created an error record with the caegory 'InvalidResult'" {
            $record.CategoryInfo.Category | Should -BeLike "InvalidResult"
        }

        It "Should have created an error record with the targetobject 'Bar'" {
            $record.TargetObject | Should -Be "Bar"
        }

        It "Should have created an error record with the ErrorID 'dbatools_Invoke-Pester,Stop-Function'" {
            $record.FullyQualifiedErrorId | Should -Be "dbatools_Invoke-Pester"
        }
    }

    Context "Testing silent: In try/catch" {
        BeforeAll {
            try {
                try {
                    $null.GetType()
                } catch {
                    Stop-Function -Message "Nonsilent Foo" -EnableException $true -ErrorRecord $PSItem -FunctionName "Invoke-Pester" -Target "Bar" -ErrorAction Stop
                    $record = $null
                    $failed = $false
                }
            } catch {
                $record = $PSItem
                $failed = $true
            }
        }

        It "Should not have failed to terminate with an exception." {
            $failed | Should -Be $true
        }

        It "Should have created an error record with the correct exception" {
            $record.Exception.InnerException.GetType().FullName | Should -Be "System.Management.Automation.RuntimeException"
        }

        It "Should have created an error record with the caegory 'InvalidOperation'" {
            $record.CategoryInfo.Category | Should -BeLike "InvalidOperation"
        }

        It "Should have created an error record with the targetobject 'Bar'" {
            $record.TargetObject | Should -Be "Bar"
        }

        It "Should have created an error record with the ErrorID 'dbatools_Invoke-Pester'" {
            $record.FullyQualifiedErrorId | Should -Be "dbatools_Invoke-Pester"
        }
    }

    Context "Testing silent: Continue & ContinueLabel" {
        BeforeAll {
            Mock -CommandName "Write-Error" -MockWith { param ($Message) }

            #region Run Tests
            try {
                $failed = $false
                $a = 0
                $b = 0
                foreach ($number in (1 .. 3)) {
                    $a++
                    Stop-Function -Message "Nonsilent Foo" -EnableException $true -Category InvalidOperation -SilentlyContinue -ErrorAction Stop 2>&1
                    $b++
                }
            } catch {
                $failed = $true
            }

            try {
                $failed2 = $false
                $c = 0
                $d = 0
                $e = 0
                $f = 0

                :main foreach ($number in (1 .. 3)) {
                    $c++
                    foreach ($Counter in (1 .. 3)) {
                        $d++
                        Stop-Function -Message "Nonsilent Foo" -EnableException $true -Category InvalidOperation -SilentlyContinue -ContinueLabel "main" -ErrorAction Stop 2>&1
                        $e++
                    }
                    $f++
                }
            } catch {
                $failed2 = $true
            }
            #endregion Run Tests
        }

        #region Evaluate Results
        It "Should not have failed to execute without an exception when testing Continue without a label." {
            $failed | Should -Be $false
        }

        It "Should not have failed to execute without an exception when testing Continue with a label." {
            $failed2 | Should -Be $false
        }

        It "Should have incremented the first counter when calling continue without a label" {
            $a | Should -Be 3
        }

        It "Should not have incremented the second counter when calling continue without a label" {
            $b | Should -Be 0
        }

        It "Should have incremented the first two counters thrice, but skipped the other two when calling continue with a label" {
            [int[]]$result = @($c, $d, $e, $f)
            [int[]]$reference = @(3, 3, 0, 0)
            $result | Should -Be $reference
        }
        #endregion Evaluate Results
    }
}
