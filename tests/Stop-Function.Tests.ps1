#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Stop-Function",
    $PSDefaultParameterValues = $TestConfig.Defaults
)
. "$PSScriptRoot\..\private\functions\flowcontrol\Stop-Function.ps1"

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
                $global:warning = Stop-Function -WarningAction Continue -Message "Nonsilent Foo" -EnableException $false -Category InvalidResult -FunctionName "Invoke-Pester" -Target "Bar" -ErrorAction Stop 3>&1
                $global:record = $Error[0]
                $global:failed = $false
            } catch {
                $global:record = $null
                $global:failed = $true
            }
        }

        It "Should not have failed to execute without an exception." {
            $global:failed | Should -Be $false
        }

        It "Should have written the test warning 'Nonsilent Foo'" {
            $global:warning[0] | Should -BeLike "*Nonsilent Foo"
        }

        It "Should have created an error record with the correct exception" {
            $global:record.Exception.Message | Should -Be "Nonsilent Foo"
        }

        It "Should have created an error record with the caegory 'InvalidResult'" {
            $global:record.CategoryInfo.Category | Should -BeLike "InvalidResult"
        }

        It "Should have created an error record with the targetobject 'Bar'" {
            $global:record.TargetObject | Should -Be "Bar"
        }

        It "Should have created an error record with the ErrorID 'dbatools_Invoke-Pester'" {
            $global:record.FullyQualifiedErrorId | Should -Be "dbatools_Invoke-Pester,Stop-Function"
        }
    }

    Context "Testing non-EnableException: In try/catch" {
        BeforeAll {
            try {
                try {
                    $null.GetType()
                } catch {
                    $global:warning = Stop-Function -WarningAction Continue -Message "Nonsilent Foo" -EnableException $false -ErrorRecord $PSItem -FunctionName "Invoke-Pester" -Target "Bar" -ErrorAction Stop 3>&1
                    $global:record = $Error[0]
                    $global:failed = $false
                }
            } catch {
                $global:record = $null
                $global:failed = $true
            }
        }

        It "Should not have failed to execute without an exception." {
            $global:failed | Should -Be $false
        }

        It "Should have written the test warning 'Nonsilent Foo | '" {
            $global:warning[0] | Should -BeLike "*Nonsilent Foo | *"
        }

        It "Should have created an error record with the correct exception" {
            $global:record.Exception.InnerException.GetType().FullName | Should -Be "System.Management.Automation.RuntimeException"
        }

        It "Should have created an error record with the category 'InvalidOperation'" {
            $global:record.CategoryInfo.Category | Should -BeLike "InvalidOperation"
        }

        It "Should have created an error record with the targetobject 'Bar'" {
            $global:record.TargetObject | Should -Be "Bar"
        }

        It "Should have created an error record with the ErrorID 'dbatools_Invoke-Pester'" {
            $global:record.FullyQualifiedErrorId | Should -Be "dbatools_Invoke-Pester,Stop-Function"
        }

        It "Should have created an error record with the an inner NULL-invocation exception" {
            try {
                $ExceptionName = $global:record.Exception.InnerException.GetType().FullName
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
                $global:failed = $false
                $global:a = 0
                $global:b = 0
                foreach ($number in (1 .. 3)) {
                    $global:a++
                    Stop-Function -Message "Nonsilent Foo" -EnableException $false -Category InvalidOperation -Continue -ErrorAction Stop 3>&1
                    $global:b++
                }
            } catch {
                $global:failed = $true
            }

            try {
                $global:failed2 = $false
                $global:c = 0
                $global:d = 0
                $global:e = 0
                $global:f = 0

                :main foreach ($number in (1 .. 3)) {
                    $global:c++
                    foreach ($Counter in (1 .. 3)) {
                        $global:d++
                        Stop-Function -Message "Nonsilent Foo" -EnableException $false -Category InvalidOperation -Continue -ContinueLabel "main" -ErrorAction Stop 3>&1
                        $global:e++
                    }
                    $global:f++
                }
            } catch {
                $global:failed2 = $true
            }
            #endregion Run Tests
        }

        #region Evaluate Results
        It "Should not have failed to execute without an exception when testing Continue without a label." {
            $global:failed | Should -Be $false
        }

        It "Should not have failed to execute without an exception when testing Continue with a label." {
            $global:failed2 | Should -Be $false
        }

        It "Should have incremented the first counter when calling continue without a label" {
            $global:a | Should -Be 3
        }

        It "Should not have incremented the second counter when calling continue without a label" {
            $global:b | Should -Be 0
        }

        It "Should have incremented the first two counters thrice, but skipped the other two when calling continue with a label" {
            [int[]]$result = @($global:c, $global:d, $global:e, $global:f)
            [int[]]$reference = @(3, 3, 0, 0)
            $result | Should -Be $reference
        }
        #endregion Evaluate Results
    }

    Context "Testing silent: Explicit call" {
        BeforeAll {
            try {
                Stop-Function -Message "Nonsilent Foo" -EnableException $true -Category InvalidResult -FunctionName "Invoke-Pester" -Target "Bar" -ErrorAction Stop
                $global:record = $null
                $global:failed = $false
            } catch {
                $global:record = $PSItem
                $global:failed = $true
            }
        }

        It "Should not have failed to terminate with an exception." {
            $global:failed | Should -Be $true
        }

        It "Should have created an error record with the correct exception" {
            $global:record.Exception.Message | Should -Be "Nonsilent Foo"
        }

        It "Should have created an error record with the caegory 'InvalidResult'" {
            $global:record.CategoryInfo.Category | Should -BeLike "InvalidResult"
        }

        It "Should have created an error record with the targetobject 'Bar'" {
            $global:record.TargetObject | Should -Be "Bar"
        }

        It "Should have created an error record with the ErrorID 'dbatools_Invoke-Pester,Stop-Function'" {
            $global:record.FullyQualifiedErrorId | Should -Be "dbatools_Invoke-Pester"
        }
    }

    Context "Testing silent: In try/catch" {
        BeforeAll {
            try {
                try {
                    $null.GetType()
                } catch {
                    Stop-Function -Message "Nonsilent Foo" -EnableException $true -ErrorRecord $PSItem -FunctionName "Invoke-Pester" -Target "Bar" -ErrorAction Stop
                    $global:record = $null
                    $global:failed = $false
                }
            } catch {
                $global:record = $PSItem
                $global:failed = $true
            }
        }

        It "Should not have failed to terminate with an exception." {
            $global:failed | Should -Be $true
        }

        It "Should have created an error record with the correct exception" {
            $global:record.Exception.InnerException.GetType().FullName | Should -Be "System.Management.Automation.RuntimeException"
        }

        It "Should have created an error record with the caegory 'InvalidOperation'" {
            $global:record.CategoryInfo.Category | Should -BeLike "InvalidOperation"
        }

        It "Should have created an error record with the targetobject 'Bar'" {
            $global:record.TargetObject | Should -Be "Bar"
        }

        It "Should have created an error record with the ErrorID 'dbatools_Invoke-Pester'" {
            $global:record.FullyQualifiedErrorId | Should -Be "dbatools_Invoke-Pester"
        }
    }

    Context "Testing silent: Continue & ContinueLabel" {
        BeforeAll {
            Mock -CommandName "Write-Error" -MockWith { param ($Message) }

            #region Run Tests
            try {
                $global:failed = $false
                $global:a = 0
                $global:b = 0
                foreach ($number in (1 .. 3)) {
                    $global:a++
                    Stop-Function -Message "Nonsilent Foo" -EnableException $true -Category InvalidOperation -SilentlyContinue -ErrorAction Stop
                    $global:b++
                }
            } catch {
                $global:failed = $true
            }

            try {
                $global:failed2 = $false
                $global:c = 0
                $global:d = 0
                $global:e = 0
                $global:f = 0

                :main foreach ($number in (1 .. 3)) {
                    $global:c++
                    foreach ($Counter in (1 .. 3)) {
                        $global:d++
                        Stop-Function -Message "Nonsilent Foo" -EnableException $true -Category InvalidOperation -SilentlyContinue -ContinueLabel "main" -ErrorAction Stop
                        $global:e++
                    }
                    $global:f++
                }
            } catch {
                $global:failed2 = $true
            }
            #endregion Run Tests
        }

        #region Evaluate Results
        It "Should not have failed to execute without an exception when testing Continue without a label." {
            $global:failed | Should -Be $false
        }

        It "Should not have failed to execute without an exception when testing Continue with a label." {
            $global:failed2 | Should -Be $false
        }

        It "Should have incremented the first counter when calling continue without a label" {
            $global:a | Should -Be 3
        }

        It "Should not have incremented the second counter when calling continue without a label" {
            $global:b | Should -Be 0
        }

        It "Should have incremented the first two counters thrice, but skipped the other two when calling continue with a label" {
            [int[]]$result = @($global:c, $global:d, $global:e, $global:f)
            [int[]]$reference = @(3, 3, 0, 0)
            $result | Should -Be $reference
        }
        #endregion Evaluate Results
    }
}