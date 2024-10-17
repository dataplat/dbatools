param($ModuleName = 'dbatools')

Describe "Test-DbaDiskAllocation" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaDiskAllocation
        }
        It "Should have ComputerName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type Object[] -Mandatory:$false
        }
        It "Should have NoSqlCheck as a parameter" {
            $CommandUnderTest | Should -HaveParameter NoSqlCheck -Type Switch -Mandatory:$false
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential -Mandatory:$false
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
    }

    Context "Command actually works" {
        BeforeDiscovery {
            $global:instance2 = $global:instance2 # Ensure this variable is in scope for discovery
        }
        It "Should return a result" {
            $results = Test-DbaDiskAllocation -ComputerName $global:instance2
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should return a result not using sql" {
            $results = Test-DbaDiskAllocation -NoSqlCheck -ComputerName $global:instance2
            $results | Should -Not -BeNullOrEmpty
        }
    }
}
