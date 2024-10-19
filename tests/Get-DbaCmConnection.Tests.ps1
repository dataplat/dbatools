param($ModuleName = 'dbatools')

Describe "Get-DbaCmConnection" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaCmConnection
        }
        It "Should have ComputerName as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName
        }
        It "Should have UserName as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter UserName
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command usage" {
        BeforeAll {
            New-DbaCmConnection -ComputerName $env:COMPUTERNAME
        }
        AfterAll {
            Remove-DbaCmConnection -ComputerName $env:COMPUTERNAME -Confirm:$false
        }
        It "Returns DbaCmConnection" {
            $Results = Get-DbaCMConnection -ComputerName $env:COMPUTERNAME
            $Results | Should -Not -BeNullOrEmpty
        }
        It "Returns DbaCmConnection for User" {
            $Results = Get-DbaCMConnection -ComputerName $env:COMPUTERNAME -UserName *
            $Results | Should -Not -BeNullOrEmpty
        }
    }
}
