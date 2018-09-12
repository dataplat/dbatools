$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
. "$PSScriptRoot\..\internal\functions\Invoke-Command2.ps1"

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $logins = "dbatoolsci_thor", "dbatoolsci_thorsmomma"
        $plaintext = "BigOlPassword!"
        $password = ConvertTo-SecureString $plaintext -AsPlainText -Force
        
        # Add user
        foreach ($login in $logins) {
            $null = Invoke-Command2 -ScriptBlock { net user $args[0] $args[1] /add *>&1 } -ArgumentList $login, $plaintext -ComputerName $script:instance2
            $null = Invoke-Command2 -ScriptBlock { net user $args[0] $args[1] /add *>&1 } -ArgumentList $login, $plaintext -ComputerName $script:instance3
        }
    }
    AfterAll {
        (Get-DbaCredential -SqlInstance $script:instance2 -Identity dbatoolsci_thor, dbatoolsci_thorsmomma -ErrorAction Stop -WarningAction SilentlyContinue).Drop()
        (Get-DbaCredential -SqlInstance $script:instance3 -Identity dbatoolsci_thor, dbatoolsci_thorsmomma -ErrorAction Stop -WarningAction SilentlyContinue).Drop()

        foreach ($login in $logins) {
            $null = Invoke-Command2 -ScriptBlock { net user $args /delete *>&1 } -ArgumentList $login -ComputerName $script:instance2
            $null = Invoke-Command2 -ScriptBlock { net user $args /delete *>&1 } -ArgumentList $login -ComputerName $script:instance3
        }
    }
    
    Context "Create new credential" {
        It "Should create new credentials with the proper properties" {
            $results = New-DbaCredential -SqlInstance $script:instance2 -Name dbatoolsci_thorcred -Identity dbatoolsci_thor -Password $password
            $results.Name | Should Be "dbatoolsci_thorcred"
            $results.Identity | Should Be "dbatoolsci_thor"
            
            $results = New-DbaCredential -SqlInstance $script:instance2 -Identity dbatoolsci_thorsmomma -Password $password
            $results.Name | Should Be "dbatoolsci_thorsmomma"
            $results.Identity | Should Be "dbatoolsci_thorsmomma"
        }
    }
    
    Context "Copy Credential with the same properties." {
        It "Should copy successfully" {
            $results = Copy-DbaCredential -Source $script:instance2 -Destination $script:instance3 -Name dbatoolsci_thorcred
            $results.Status | Should Be "Successful"
        }
        
        It "Should retain its same properties" {
            $Credential1 = Get-DbaCredential -SqlInstance $script:instance2 -Name dbatoolsci_thor -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            $Credential2 = Get-DbaCredential -SqlInstance $script:instance3 -Name dbatoolsci_thor -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            
            # Compare its value
            $Credential1.Name | Should Be $Credential2.Name
            $Credential1.Identity | Should Be $Credential2.Identity
        }
    }
    
    Context "No overwrite" {
        It "does not overwrite without force" {
            $results = Copy-DbaCredential -Source $script:instance2 -Destination $script:instance3 -Name dbatoolsci_thorcred
            $results.Status | Should Be "Skipping"
        }
    }
}