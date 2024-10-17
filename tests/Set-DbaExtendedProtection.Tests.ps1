param($ModuleName = 'dbatools')

Describe "Set-DbaExtendedProtection" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaExtendedProtection
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential
        }
        It "Should have Value as a parameter" {
            $CommandUnderTest | Should -HaveParameter Value -Type Object
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }

    Context "Command actually works" {
        It "Default set and returns '0 - Off'" {
            $results = Set-DbaExtendedProtection -SqlInstance $script:instance1 -EnableException *>$null
            $results.ExtendedProtection | Should -Be "0 - Off"
        }
    }

    Context "Command works when passed different values" {
        BeforeAll {
            Mock Test-ShouldProcess { $false } -ModuleName dbatools
            Mock Invoke-ManagedComputerCommand -MockWith {
                param (
                    $ComputerName,
                    $Credential,
                    $ScriptBlock,
                    $EnableException
                )
                $server = [DbaInstanceParameter[]]$script:instance1
                @{
                    DisplayName        = "SQL Server ($($instance.InstanceName))"
                    AdvancedProperties = @(
                        @{
                            Name  = 'REGROOT'
                            Value = 'Software\Microsoft\Microsoft SQL Server\MSSQL10_50.SQL2008R2SP2'
                        }
                    )
                }
            } -ModuleName dbatools
        }

        It "Set explicitly to '0 - Off' using text" {
            $results = Set-DbaExtendedProtection -SqlInstance $script:instance1 -Value Off -EnableException -Verbose 4>&1
            $results[-1] | Should -Be 'Value: 0'
        }

        It "Set explicitly to '0 - Off' using number" {
            $results = Set-DbaExtendedProtection -SqlInstance $script:instance1 -Value 0 -EnableException -Verbose 4>&1
            $results[-1] | Should -Be 'Value: 0'
        }

        It "Set explicitly to '1 - Allowed' using text" {
            $results = Set-DbaExtendedProtection -SqlInstance $script:instance1 -Value Allowed -EnableException -Verbose 4>&1
            $results[-1] | Should -Be 'Value: 1'
        }

        It "Set explicitly to '1 - Allowed' using number" {
            $results = Set-DbaExtendedProtection -SqlInstance $script:instance1 -Value 1 -EnableException -Verbose 4>&1
            $results[-1] | Should -Be 'Value: 1'
        }

        It "Set explicitly to '2 - Required' using text" {
            $results = Set-DbaExtendedProtection -SqlInstance $script:instance1 -Value Required -EnableException -Verbose 4>&1
            $results[-1] | Should -Be 'Value: 2'
        }

        It "Set explicitly to '2 - Required' using number" {
            $results = Set-DbaExtendedProtection -SqlInstance $script:instance1 -Value 2 -EnableException -Verbose 4>&1
            $results[-1] | Should -Be 'Value: 2'
        }
    }
}
