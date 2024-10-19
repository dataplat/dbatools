param($ModuleName = 'dbatools')

Describe "Test-PSRemoting" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
        . "$PSScriptRoot\..\private\functions\Test-PSRemoting.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-PSRemoting
        }
        It "Should have ComputerName as a non-mandatory parameter of type Dataplat.Dbatools.Parameter.DbaInstanceParameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName
        }
        It "Should have Credential as a non-mandatory parameter of type System.Object" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Function Behavior" {
        It "Returns false when failing" {
            $result = Test-PSRemoting -ComputerName "funny"
            $result | Should -Be $false
        }

        It "Returns true when succeeding with localhost" {
            $result = Test-PSRemoting -ComputerName localhost
            $result | Should -Be $true
        }

        It "Handles an instance, using just the computername" {
            $result = Test-PSRemoting -ComputerName $global:instance1
            $result | Should -Be $true
        }
    }
}
