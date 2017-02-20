#Thank you Warren http://ramblingcookiemonster.github.io/Testing-DSC-with-Pester-and-AppVeyor/

if (-not $PSScriptRoot)
{
    $PSScriptRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
}
$Verbose = @{ }
if ($env:APPVEYOR_REPO_BRANCH -and $env:APPVEYOR_REPO_BRANCH -notlike "master")
{
    $Verbose.add("Verbose", $True)
}



$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path).Replace('.Tests.', '.')
. $PSScriptRoot\..\internal\$sut
. $PSScriptRoot\..\internal\Write-Message.ps1
Import-Module PSScriptAnalyzer
## Added PSAvoidUsingPlainTextForPassword as credential is an object and therefore fails. We can ignore any rules here under special circumstances agreed by admins :-)
$Rules = (Get-ScriptAnalyzerRule).Where{ $_.RuleName -notin ('PSAvoidUsingPlainTextForPassword') }
$Name = $sut.Split('.')[0]

Describe 'Script Analyzer Tests' {
    Context "Testing $Name for Standard Processing" {
        foreach ($rule in $rules)
        {
            $i = $rules.IndexOf($rule)
            It "passes the PSScriptAnalyzer Rule number $i - $rule  " {
                (Invoke-ScriptAnalyzer -Path "$PSScriptRoot\..\internal\$sut" -IncludeRule $rule.RuleName).Count | Should Be 0
            }
        }
    }
}

## needs some proper tests for the function here
Describe "$Name Tests"{
    Context "Testing non-silent: Explicit call" {
        try
        {
            $warning = Stop-Function -Message "Nonsilent Foo" -Silent $false -Category InvalidResult -FunctionName "Invoke-Pester" -Target "Bar" -ErrorAction Stop 3>&1
            $record = $Error[0]
            $failed = $false
        }
        catch
        {
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
    
    Context "Testing non-silent: In try/catch" {
        try
        {
            try
            {
                $null.GetType()
            }
            catch
            {
                $warning = Stop-Function -Message "Nonsilent Foo" -Silent $false -InnerErrorRecord $_ -FunctionName "Invoke-Pester" -Target "Bar" -ErrorAction Stop 3>&1
                $record = $Error[0]
                $failed = $false
            }
        }
        catch
        {
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
        
        It "Should have created an error record with the caegory 'InvalidOperation'" {
            $record.CategoryInfo.Category | Should BeLike "InvalidOperation"
        }
        
        It "Should have created an error record with the targetobject 'Bar'" {
            $record.TargetObject | Should Be "Bar"
        }
        
        It "Should have created an error record with the ErrorID 'dbatools_Invoke-Pester'" {
            $record.FullyQualifiedErrorId | Should Be "dbatools_Invoke-Pester,Stop-Function"
        }
        
        It "Should have created an error record with the an inner NULL-invocation exception" {
            try
            {
                $ExceptionName = $record.Exception.InnerException.GetType().FullName
            }
            catch
            {
                $ExceptionName = "Meeep!"
            }
            
            $ExceptionName | Should Be "System.Management.Automation.RuntimeException"
        }
    }
    
    Context "Testing non-silent: Continue & ContinueLabel" {
        Mock -CommandName "Write-Warning" -MockWith { Param ($Message) }
        
        #region Run Tests
        try
        {
            $failed = $false
            $a = 0
            $b = 0
            foreach ($number in (1 .. 3))
            {
                $a++
                Stop-Function -Message "Nonsilent Foo" -Silent $false -Category InvalidOperation -Continue -ErrorAction Stop
                $b++
            }
        }
        catch
        {
            $failed = $true
        }
        
        try
        {
            $failed2 = $false
            $c = 0
            $d = 0
            $e = 0
            $f = 0
            
            :main foreach ($number in (1 .. 3))
            {
                $c++
                foreach ($Counter in (1 .. 3))
                {
                    $d++
                    Stop-Function -Message "Nonsilent Foo" -Silent $false -Category InvalidOperation -Continue -ContinueLabel "main" -ErrorAction Stop
                    $e++
                }
                $f++
            }
        }
        catch
        {
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
        try
        {
            Stop-Function -Message "Nonsilent Foo" -Silent $true -Category InvalidResult -FunctionName "Invoke-Pester" -Target "Bar" -ErrorAction Stop
            $record = $null
            $failed = $false
        }
        catch
        {
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
        
        It "Should have created an error record with the ErrorID 'dbatools_Invoke-Pester'" {
            $record.FullyQualifiedErrorId | Should Be "dbatools_Invoke-Pester"
        }
    }
    
    Context "Testing silent: In try/catch" {
        try
        {
            try
            {
                $null.GetType()
            }
            catch
            {
                Stop-Function -Message "Nonsilent Foo" -Silent $true -InnerErrorRecord $_ -FunctionName "Invoke-Pester" -Target "Bar" -ErrorAction Stop
                $record = $null
                $failed = $false
            }
        }
        catch
        {
            $record = $_
            $failed = $true
        }
        
        It "Should not have failed to terminate with an exception!" {
            $failed | Should Be $true
        }
        
        It "Should have created an error record with the correct exception" {
            $record.Exception.Message | Should Be "Nonsilent Foo"
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
        
        It "Should have created an error record with the an inner NULL-invocation exception" {
            try
            {
                $ExceptionName = $record.Exception.InnerException.GetType().FullName
            }
            catch
            {
                $ExceptionName = "Meeep!"
            }
            
            $ExceptionName | Should Be "System.Management.Automation.RuntimeException"
        }
    }
    
    Context "Testing silent: Continue & ContinueLabel" {
        Mock -CommandName "Write-Error" -MockWith { Param ($Message) }
        
        #region Run Tests
        try
        {
            $failed = $false
            $a = 0
            $b = 0
            foreach ($number in (1 .. 3))
            {
                $a++
                Stop-Function -Message "Nonsilent Foo" -Silent $true -Category InvalidOperation -SilentlyContinue -ErrorAction Stop
                $b++
            }
        }
        catch
        {
            $failed = $true
        }
        
        try
        {
            $failed2 = $false
            $c = 0
            $d = 0
            $e = 0
            $f = 0
            
            :main foreach ($number in (1 .. 3))
            {
                $c++
                foreach ($Counter in (1 .. 3))
                {
                    $d++
                    Stop-Function -Message "Nonsilent Foo" -Silent $true -Category InvalidOperation -SilentlyContinue -ContinueLabel "main" -ErrorAction Stop
                    $e++
                }
                $f++
            }
        }
        catch
        {
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