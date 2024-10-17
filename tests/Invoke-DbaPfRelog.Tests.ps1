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
        It "Should have Path as a non-mandatory String[] parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type String[] -Mandatory:$false
        }
        It "Should have Destination as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Destination -Type String -Mandatory:$false
        }
        It "Should have Type as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Type -Type String -Mandatory:$false
        }
        It "Should have Append as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter Append -Type Switch -Mandatory:$false
        }
        It "Should have AllowClobber as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter AllowClobber -Type Switch -Mandatory:$false
        }
        It "Should have PerformanceCounter as a non-mandatory String[] parameter" {
            $CommandUnderTest | Should -HaveParameter PerformanceCounter -Type String[] -Mandatory:$false
        }
        It "Should have PerformanceCounterPath as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter PerformanceCounterPath -Type String -Mandatory:$false
        }
        It "Should have Interval as a non-mandatory Int32 parameter" {
            $CommandUnderTest | Should -HaveParameter Interval -Type Int32 -Mandatory:$false
        }
        It "Should have BeginTime as a non-mandatory DateTime parameter" {
            $CommandUnderTest | Should -HaveParameter BeginTime -Type DateTime -Mandatory:$false
        }
        It "Should have EndTime as a non-mandatory DateTime parameter" {
            $CommandUnderTest | Should -HaveParameter EndTime -Type DateTime -Mandatory:$false
        }
        It "Should have ConfigPath as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter ConfigPath -Type String -Mandatory:$false
        }
        It "Should have Summary as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter Summary -Type Switch -Mandatory:$false
        }
        It "Should have InputObject as a non-mandatory Object[] parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Object[] -Mandatory:$false
        }
        It "Should have Multithread as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter Multithread -Type Switch -Mandatory:$false
        }
        It "Should have AllTime as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter AllTime -Type Switch -Mandatory:$false
        }
        It "Should have Raw as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter Raw -Type Switch -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
    }
}

# Integration tests can be added below this line
# Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests for more guidance.
