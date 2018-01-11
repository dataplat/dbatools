$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
. "$PSScriptRoot\..\internal\functions\Stop-Function.ps1"

Describe "$commandname Unit Tests" -Tag 'UnitTests' {
    Context "Testing non-EnableException: Explicit call" {
        try {
            $warning = Stop-Function -Message "Nonsilent Foo" -EnableException $false -Category InvalidResult -FunctionName "Invoke-Pester" -Target "Bar" -ErrorAction Stop 3>&1
            $record = $Error[0]
            $failed = $false
        }
        catch {
            $record = $null
            $failed = $true
        }

        It "Should not have failed to execute without an exception!" {
            $failed | Should Be $false
        }

        It "Should have written the test warning 'Nonsilent Foo'" {
            $warning[0] | Should BeLike "*Nonsilent Foo"
        }

        It "Should have created an error record with the correct exception" {
            $record.Exception.Message | Should Be "Nonsilent Foo"
        }

        It "Should have created an error record with the caegory 'InvalidResult'" {
            $record.CategoryInfo.Category | Should BeLike "InvalidResult"
        }

        It "Should have created an error record with the targetobject 'Bar'" {
            $record.TargetObject | Should Be "Bar"
        }

        It "Should have created an error record with the ErrorID 'dbatools_Invoke-Pester'" {
            $record.FullyQualifiedErrorId | Should Be "dbatools_Invoke-Pester,Stop-Function"
        }
    }

    Context "Testing non-EnableException: In try/catch" {
        try {
            try {
                $null.GetType()
            }
            catch {
                $warning = Stop-Function -Message "Nonsilent Foo" -EnableException $false -InnerErrorRecord $_ -FunctionName "Invoke-Pester" -Target "Bar" -ErrorAction Stop 3>&1
                $record = $Error[0]
                $failed = $false
            }
        }
        catch {
            $record = $null
            $failed = $true
        }

        It "Should not have failed to execute without an exception!" {
            $failed | Should Be $false
        }

        It "Should have written the test warning 'Nonsilent Foo | '" {
            $warning[0] | Should BeLike "*Nonsilent Foo | *"
        }

        It "Should have created an error record with the correct exception" {
            $record.Exception.InnerException.GetType().FullName | Should Be "System.Management.Automation.RuntimeException"
        }

        It "Should have created an error record with the category 'InvalidOperation'" {
            $record.CategoryInfo.Category | Should BeLike "InvalidOperation"
        }

        It "Should have created an error record with the targetobject 'Bar'" {
            $record.TargetObject | Should Be "Bar"
        }

        It "Should have created an error record with the ErrorID 'dbatools_Invoke-Pester'" {
            $record.FullyQualifiedErrorId | Should Be "dbatools_Invoke-Pester,Stop-Function"
        }

        It "Should have created an error record with the an inner NULL-invocation exception" {
            try {
                $ExceptionName = $record.Exception.InnerException.GetType().FullName
            }
            catch {
                $ExceptionName = "Meeep!"
            }

            $ExceptionName | Should Be "System.Management.Automation.RuntimeException"
        }
    }

    Context "Testing non-EnableException: Continue & ContinueLabel" {
        Mock -CommandName "Write-Warning" -MockWith { Param ($Message) }

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
        }
        catch {
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
        }
        catch {
            $failed2 = $true
        }
        #endregion Run Tests

        #region Evaluate Results
        It "Should not have failed to execute without an exception when testing Continue without a label!" {
            $failed | Should Be $false
        }

        It "Should not have failed to execute without an exception when testing Continue with a label!" {
            $failed2 | Should Be $false
        }

        It "Should have incremented the first counter when calling continue without a label" {
            $a | Should Be 3
        }

        It "Should not have incremented the second counter when calling continue without a label" {
            $b | Should Be 0
        }

        It "Should have incremented the first two counters thrice, but skipped the other two when calling continue with a label" {
            [int[]]$result = @($c, $d, $e, $f)
            [int[]]$reference = @(3, 3, 0, 0)
            $result | Should Be $reference
        }
        #endregion Evaluate Results
    }

    Context "Testing silent: Explicit call" {
        try {
            Stop-Function -Message "Nonsilent Foo" -EnableException $true -Category InvalidResult -FunctionName "Invoke-Pester" -Target "Bar" -ErrorAction Stop
            $record = $null
            $failed = $false
        }
        catch {
            $record = $_
            $failed = $true
        }

        It "Should not have failed to terminate with an exception!" {
            $failed | Should Be $true
        }

        It "Should have created an error record with the correct exception" {
            $record.Exception.Message | Should Be "Nonsilent Foo"
        }

        It "Should have created an error record with the caegory 'InvalidResult'" {
            $record.CategoryInfo.Category | Should BeLike "InvalidResult"
        }

        It "Should have created an error record with the targetobject 'Bar'" {
            $record.TargetObject | Should Be "Bar"
        }

        It "Should have created an error record with the ErrorID 'dbatools_Invoke-Pester,Stop-Function'" {
            $record.FullyQualifiedErrorId | Should Be "dbatools_Invoke-Pester"
        }
    }

    Context "Testing silent: In try/catch" {
        try {
            try {
                $null.GetType()
            }
            catch {
                Stop-Function -Message "Nonsilent Foo" -EnableException $true -InnerErrorRecord $_ -FunctionName "Invoke-Pester" -Target "Bar" -ErrorAction Stop
                $record = $null
                $failed = $false
            }
        }
        catch {
            $record = $_
            $failed = $true
        }

        It "Should not have failed to terminate with an exception!" {
            $failed | Should Be $true
        }

        It "Should have created an error record with the correct exception" {
            $record.Exception.InnerException.GetType().FullName | Should Be "System.Management.Automation.RuntimeException"
        }

        It "Should have created an error record with the caegory 'InvalidOperation'" {
            $record.CategoryInfo.Category | Should BeLike "InvalidOperation"
        }

        It "Should have created an error record with the targetobject 'Bar'" {
            $record.TargetObject | Should Be "Bar"
        }

        It "Should have created an error record with the ErrorID 'dbatools_Invoke-Pester'" {
            $record.FullyQualifiedErrorId | Should Be "dbatools_Invoke-Pester"
        }
    }

    Context "Testing silent: Continue & ContinueLabel" {
        Mock -CommandName "Write-Error" -MockWith { Param ($Message) }

        #region Run Tests
        try {
            $failed = $false
            $a = 0
            $b = 0
            foreach ($number in (1 .. 3)) {
                $a++
                Stop-Function -Message "Nonsilent Foo" -EnableException $true -Category InvalidOperation -SilentlyContinue -ErrorAction Stop
                $b++
            }
        }
        catch {
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
                    Stop-Function -Message "Nonsilent Foo" -EnableException $true -Category InvalidOperation -SilentlyContinue -ContinueLabel "main" -ErrorAction Stop
                    $e++
                }
                $f++
            }
        }
        catch {
            $failed2 = $true
        }
        #endregion Run Tests

        #region Evaluate Results
        It "Should not have failed to execute without an exception when testing Continue without a label!" {
            $failed | Should Be $false
        }

        It "Should not have failed to execute without an exception when testing Continue with a label!" {
            $failed2 | Should Be $false
        }

        It "Should have incremented the first counter when calling continue without a label" {
            $a | Should Be 3
        }

        It "Should not have incremented the second counter when calling continue without a label" {
            $b | Should Be 0
        }

        It "Should have incremented the first two counters thrice, but skipped the other two when calling continue with a label" {
            [int[]]$result = @($c, $d, $e, $f)
            [int[]]$reference = @(3, 3, 0, 0)
            $result | Should Be $reference
        }
        #endregion Evaluate Results
    }
}
