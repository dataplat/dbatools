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
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Credential",
                "ExcludeCredential",
                "Identity",
                "ExcludeIdentity",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
