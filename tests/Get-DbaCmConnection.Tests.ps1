param($ModuleName = 'dbatools')

Describe "Get-DbaCmConnection" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaCmConnection
        }
        $params = @(
            "ComputerName",
            "UserName",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
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
