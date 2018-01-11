$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $logins = "thor", "thorsmomma"
        $plaintext = "BigOlPassword!"
        $password = ConvertTo-SecureString $plaintext -AsPlainText -Force
        # Add user
        foreach ($login in $logins) {
            $null = net user $login $plaintext /add *>&1
        }
        # remove old credentials
        foreach ($Credential in (Get-DbaCredential -SqlInstance $script:instance1)) {
            $Credential.Drop()
        }
        foreach ($Credential in (Get-DbaCredential -SqlInstance $script:instance2)) {
            $Credential.Drop()
        }
    }
    AfterAll {
        foreach ($Credential in (Get-DbaCredential -SqlInstance $script:instance1)) {
            $Credential.Drop()
        }
        foreach ($Credential in (Get-DbaCredential -SqlInstance $script:instance2)) {
            $Credential.Drop()
        }
        foreach ($login in $logins) {
            $null = net user $login /delete *>&1
        }
    }

    Context "Create a new credential" {
        It "Should create new credentials with the proper properties" {
            $results = New-DbaCredential -SqlInstance $script:instance1 -Name thorcred -CredentialIdentity thor -Password $password
            $results.Name | Should Be "thorcred"
            $results.Identity | Should Be "thor"

            $results = New-DbaCredential -SqlInstance $script:instance1 -CredentialIdentity thorsmomma -Password $password
            $results | Should Not Be $null
        }
    }
}