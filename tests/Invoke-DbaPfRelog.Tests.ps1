param($ModuleName = 'dbatools')

Describe "Invoke-DbaPfRelog Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Invoke-DbaPfRelog
        }
        It "Should have Path as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Path
        }
        It "Should have Destination as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Destination
        }
        It "Should have Type as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Type
        }
        It "Should have Append as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Append
        }
        It "Should have AllowClobber as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter AllowClobber
        }
        It "Should have PerformanceCounter as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter PerformanceCounter
        }
        It "Should have PerformanceCounterPath as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter PerformanceCounterPath
        }
        It "Should have Interval as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Interval
        }
        It "Should have BeginTime as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter BeginTime
        }
        It "Should have EndTime as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter EndTime
        }
        It "Should have ConfigPath as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ConfigPath
        }
        It "Should have Summary as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Summary
        }
        It "Should have InputObject as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have Multithread as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Multithread
        }
        It "Should have AllTime as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter AllTime
        }
        It "Should have Raw as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Raw
        }
        It "Should have EnableException as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

# Integration tests can be added below this line
# Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests for more guidance.
