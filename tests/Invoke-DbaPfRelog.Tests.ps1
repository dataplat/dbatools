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
        It "Should have Path as a non-mandatory System.String[] parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type System.String[] -Mandatory:$false
        }
        It "Should have Destination as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter Destination -Type System.String -Mandatory:$false
        }
        It "Should have Type as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter Type -Type System.String -Mandatory:$false
        }
        It "Should have Append as a non-mandatory System.Management.Automation.Switch parameter" {
            $CommandUnderTest | Should -HaveParameter Append -Type System.Management.Automation.Switch -Mandatory:$false
        }
        It "Should have AllowClobber as a non-mandatory System.Management.Automation.Switch parameter" {
            $CommandUnderTest | Should -HaveParameter AllowClobber -Type System.Management.Automation.Switch -Mandatory:$false
        }
        It "Should have PerformanceCounter as a non-mandatory System.String[] parameter" {
            $CommandUnderTest | Should -HaveParameter PerformanceCounter -Type System.String[] -Mandatory:$false
        }
        It "Should have PerformanceCounterPath as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter PerformanceCounterPath -Type System.String -Mandatory:$false
        }
        It "Should have Interval as a non-mandatory System.Int32 parameter" {
            $CommandUnderTest | Should -HaveParameter Interval -Type System.Int32 -Mandatory:$false
        }
        It "Should have BeginTime as a non-mandatory System.DateTime parameter" {
            $CommandUnderTest | Should -HaveParameter BeginTime -Type System.DateTime -Mandatory:$false
        }
        It "Should have EndTime as a non-mandatory System.DateTime parameter" {
            $CommandUnderTest | Should -HaveParameter EndTime -Type System.DateTime -Mandatory:$false
        }
        It "Should have ConfigPath as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter ConfigPath -Type System.String -Mandatory:$false
        }
        It "Should have Summary as a non-mandatory System.Management.Automation.Switch parameter" {
            $CommandUnderTest | Should -HaveParameter Summary -Type System.Management.Automation.Switch -Mandatory:$false
        }
        It "Should have InputObject as a non-mandatory System.Object[] parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type System.Object[] -Mandatory:$false
        }
        It "Should have Multithread as a non-mandatory System.Management.Automation.Switch parameter" {
            $CommandUnderTest | Should -HaveParameter Multithread -Type System.Management.Automation.Switch -Mandatory:$false
        }
        It "Should have AllTime as a non-mandatory System.Management.Automation.Switch parameter" {
            $CommandUnderTest | Should -HaveParameter AllTime -Type System.Management.Automation.Switch -Mandatory:$false
        }
        It "Should have Raw as a non-mandatory System.Management.Automation.Switch parameter" {
            $CommandUnderTest | Should -HaveParameter Raw -Type System.Management.Automation.Switch -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory System.Management.Automation.Switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.Switch -Mandatory:$false
        }
    }
}

# Integration tests can be added below this line
# Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests for more guidance.
