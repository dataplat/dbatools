param($ModuleName = 'dbatools')

Describe "New-DbaXESmartTableWriter" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaXESmartTableWriter
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have Database as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter Database -Type String -Mandatory:$false
        }
        It "Should have Table as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter Table -Type String -Mandatory:$false
        }
        It "Should have AutoCreateTargetTable as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter AutoCreateTargetTable -Type Switch -Mandatory:$false
        }
        It "Should have UploadIntervalSeconds as a non-mandatory parameter of type Int32" {
            $CommandUnderTest | Should -HaveParameter UploadIntervalSeconds -Type Int32 -Mandatory:$false
        }
        It "Should have Event as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Event -Type String[] -Mandatory:$false
        }
        It "Should have OutputColumn as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter OutputColumn -Type String[] -Mandatory:$false
        }
        It "Should have Filter as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter Filter -Type String -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
    }

    Context "Creates a smart object" {
        BeforeAll {
            $results = New-DbaXESmartReplay -SqlInstance $global:instance2 -Database planning
        }
        It "returns the object with all of the correct properties" {
            $results.ServerName | Should -Be $global:instance2
            $results.DatabaseName | Should -Be 'planning'
            $results.Password | Should -BeNullOrEmpty
            $results.DelaySeconds | Should -Be 0
        }
    }
}
