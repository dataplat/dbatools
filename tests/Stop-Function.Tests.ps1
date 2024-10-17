param($ModuleName = 'dbatools')

Describe "Stop-Function" {
    BeforeAll {
        . "$PSScriptRoot\..\private\functions\flowcontrol\Stop-Function.ps1"
        $PSDefaultParameterValues.Remove('*:WarningAction')
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Stop-Function
        }
        It "Should have Message as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Message -Type String -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory Boolean parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Boolean -Not -Mandatory
        }
        It "Should have Category as a non-mandatory ErrorCategory parameter" {
            $CommandUnderTest | Should -HaveParameter Category -Type ErrorCategory -Not -Mandatory
        }
        It "Should have ErrorRecord as a non-mandatory ErrorRecord[] parameter" {
            $CommandUnderTest | Should -HaveParameter ErrorRecord -Type ErrorRecord[] -Not -Mandatory
        }
        It "Should have Tag as a non-mandatory String[] parameter" {
            $CommandUnderTest | Should -HaveParameter Tag -Type String[] -Not -Mandatory
        }
        It "Should have FunctionName as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter FunctionName -Type String -Not -Mandatory
        }
        It "Should have File as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter File -Type String -Not -Mandatory
        }
        It "Should have Line as a non-mandatory Int32 parameter" {
            $CommandUnderTest | Should -HaveParameter Line -Type Int32 -Not -Mandatory
        }
        It "Should have Target as a non-mandatory Object parameter" {
            $CommandUnderTest | Should -HaveParameter Target -Type Object -Not -Mandatory
        }
        It "Should have Exception as a non-mandatory Exception parameter" {
            $CommandUnderTest | Should -HaveParameter Exception -Type Exception -Not -Mandatory
        }
        It "Should have OverrideExceptionMessage as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter OverrideExceptionMessage -Type Switch -Not -Mandatory
        }
        It "Should have Continue as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter Continue -Type Switch -Not -Mandatory
        }
        It "Should have SilentlyContinue as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter SilentlyContinue -Type Switch -Not -Mandatory
        }
        It "Should have ContinueLabel as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter ContinueLabel -Type String -Not -Mandatory
        }
    }

    Context "Testing non-EnableException: Explicit call" {
        BeforeAll {
            $warning = $null
            $record = $null
            $failed = $false

            try {
                $warning = Stop-Function -WarningAction Continue -Message "Nonsilent Foo" -EnableException $false -Category InvalidResult -FunctionName "Invoke-Pester" -Target "Bar" -ErrorAction Stop 3>&1
                $record = $Error[0]
            } catch {
                $failed = $true
            }
        }

        It "Should not have failed to execute without an exception." {
            $failed | Should -Be $false
        }

        It "Should have written the test warning 'Nonsilent Foo'" {
            $warning[0] | Should -BeLike "*Nonsilent Foo"
        }

        It "Should have created an error record with the correct exception" {
            $record.Exception.Message | Should -Be "Nonsilent Foo"
        }

        It "Should have created an error record with the category 'InvalidResult'" {
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
            $warning = $null
            $record = $null
            $failed = $false

            try {
                try {
                    $null.GetType()
                } catch {
                    $warning = Stop-Function -WarningAction Continue -Message "Nonsilent Foo" -EnableException $false -ErrorRecord $_ -FunctionName "Invoke-Pester" -Target "Bar" -ErrorAction Stop 3>&1
                    $record = $Error[0]
                }
            } catch {
                $failed = $true
            }
        }

        It "Should not have failed to execute without an exception." {
            $failed | Should -Be $false
        }

        It "Should have written the test warning 'Nonsilent Foo | '" {
            $warning[0] | Should -BeLike "*Nonsilent Foo | *"
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
            $record.Exception.InnerException.GetType().FullName | Should -Be "System.Management.Automation.RuntimeException"
        }
    }

    Context "Testing non-EnableException: Continue & ContinueLabel" {
        BeforeAll {
            Mock Write-Warning { }

            $failed = $false
            $a = 0
            $b = 0
            foreach ($number in (1 .. 3)) {
                $a++
                Stop-Function -Message "Nonsilent Foo" -EnableException $false -Category InvalidOperation -Continue -ErrorAction Stop 3>&1
                $b++
            }

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
        }

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
    }

    Context "Testing silent: Explicit call" {
        BeforeAll {
            $record = $null
            $failed = $false

            try {
                Stop-Function -Message "Nonsilent Foo" -EnableException $true -Category InvalidResult -FunctionName "Invoke-Pester" -Target "Bar" -ErrorAction Stop
            } catch {
                $record = $_
                $failed = $true
            }
        }

        It "Should have failed to terminate with an exception." {
            $failed | Should -Be $true
        }

        It "Should have created an error record with the correct exception" {
            $record.Exception.Message | Should -Be "Nonsilent Foo"
        }

        It "Should have created an error record with the category 'InvalidResult'" {
            $record.CategoryInfo.Category | Should -BeLike "InvalidResult"
        }

        It "Should have created an error record with the targetobject 'Bar'" {
            $record.TargetObject | Should -Be "Bar"
        }

        It "Should have created an error record with the ErrorID 'dbatools_Invoke-Pester'" {
            $record.FullyQualifiedErrorId | Should -Be "dbatools_Invoke-Pester"
        }
    }

    Context "Testing silent: In try/catch" {
        BeforeAll {
            $record = $null
            $failed = $false

            try {
                try {
                    $null.GetType()
                } catch {
                    Stop-Function -Message "Nonsilent Foo" -EnableException $true -ErrorRecord $_ -FunctionName "Invoke-Pester" -Target "Bar" -ErrorAction Stop
                }
            } catch {
                $record = $_
                $failed = $true
            }
        }

        It "Should have failed to terminate with an exception." {
            $failed | Should -Be $true
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
            $record.FullyQualifiedErrorId | Should -Be "dbatools_Invoke-Pester"
        }
    }

    Context "Testing silent: Continue & ContinueLabel" {
        BeforeAll {
            Mock Write-Error { }

            $failed = $false
            $a = 0
            $b = 0
            foreach ($number in (1 .. 3)) {
                $a++
                Stop-Function -Message "Nonsilent Foo" -EnableException $true -Category InvalidOperation -SilentlyContinue -ErrorAction Stop
                $b++
            }

            $failed2 = $false
            $c = 0
            $d = 0
            $e = 0
            $f = 0

            :main foreach ($number in (1 .. 3)) {
                $c++
                foreach ($Counter in (1 .. 3)) {
                    $d++
                    Stop-Function -Message "Nonsilent Foo" -EnableException $true -Category InvalidOperation -SilentlyContinue -ContinueLabel "main" -ErrorAction Stop
                    $e++
                }
                $f++
            }
        }

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
    }
}

$PSDefaultParameterValues['*:WarningAction'] = 'SilentlyContinue'
