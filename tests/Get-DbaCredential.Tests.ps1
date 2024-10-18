param($ModuleName = 'dbatools')

Describe "Get-DbaCredential" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
        . "$PSScriptRoot\..\private\functions\Invoke-Command2.ps1"

        $logins = "dbatoolsci_thor", "dbatoolsci_thorsmomma"
        $plaintext = "BigOlPassword!"
        $password = ConvertTo-SecureString $plaintext -AsPlainText -Force

        # Add user
        foreach ($login in $logins) {
            $null = Invoke-Command2 -ScriptBlock { net user $args[0] $args[1] /add *>&1 } -ArgumentList $login, $plaintext -ComputerName $global:instance2
        }

        $results = New-DbaCredential -SqlInstance $global:instance2 -Name dbatoolsci_thorcred -Identity dbatoolsci_thor -Password $password
        $results = New-DbaCredential -SqlInstance $global:instance2 -Identity dbatoolsci_thorsmomma -Password $password
    }

    AfterAll {
        try {
            (Get-DbaCredential -SqlInstance $global:instance2 -Identity dbatoolsci_thor, dbatoolsci_thorsmomma -ErrorAction Stop -WarningAction SilentlyContinue).Drop()
        } catch { }

        foreach ($login in $logins) {
            $null = Invoke-Command2 -ScriptBlock { net user $args /delete *>&1 } -ArgumentList $login -ComputerName $global:instance2
            $null = Invoke-Command2 -ScriptBlock { net user $args /delete *>&1 } -ArgumentList $login -ComputerName $global:instance2
        }
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaCredential
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type System.String[]
        }
        It "Should have ExcludeCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeCredential -Type System.String[]
        }
        It "Should have Identity as a parameter" {
            $CommandUnderTest | Should -HaveParameter Identity -Type System.String[]
        }
        It "Should have ExcludeIdentity as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeIdentity -Type System.String[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
    }

    Context "Get credentials" {
        It "Should get just one credential with the proper properties when using Identity" {
            $results = Get-DbaCredential -SqlInstance $global:instance2 -Identity dbatoolsci_thorsmomma
            $results.Name | Should -Be "dbatoolsci_thorsmomma"
            $results.Identity | Should -Be "dbatoolsci_thorsmomma"
        }
        It "Should get just one credential with the proper properties when using Name" {
            $results = Get-DbaCredential -SqlInstance $global:instance2 -Name dbatoolsci_thorsmomma
            $results.Name | Should -Be "dbatoolsci_thorsmomma"
            $results.Identity | Should -Be "dbatoolsci_thorsmomma"
        }
        It "gets more than one credential" {
            $results = Get-DbaCredential -SqlInstance $global:instance2 -Identity dbatoolsci_thor, dbatoolsci_thorsmomma
            $results.count | Should -BeGreaterThan 1
        }
    }
}
