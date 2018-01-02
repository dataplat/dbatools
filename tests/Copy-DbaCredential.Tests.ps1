$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

if (-not $env:appveyor) {
    Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
        BeforeAll {
            $logins = "thor", "thorsmomma"
            $plaintext = "BigOlPassword!"
            $password = ConvertTo-SecureString $plaintext -AsPlainText -Force

            # Add user
            foreach ($login in $logins) {
                $null = net user $login $plaintext /add *>&1
            }

            $results = New-DbaCredential -SqlInstance $script:instance1 -Name thorcred -CredentialIdentity thor -Password $password
            $results = New-DbaCredential -SqlInstance $script:instance1 -CredentialIdentity thorsmomma -Password $password
        }
        AfterAll {
            try {
                (Get-DbaCredential -SqlInstance $script:instance1 -CredentialIdentity thor -ErrorAction SilentlyContinue -WarningAction SilentlyContinue).Drop()
                (Get-DbaCredential -SqlInstance $script:instance2 -CredentialIdentity thor -ErrorAction SilentlyContinue -WarningAction SilentlyContinue).Drop()
            }
            catch { }

            foreach ($login in $logins) {
                $null = net user $login /delete *>&1
            }
        }

        if ($bail) { return }

        Context "Create new credential" {
            It "Should create new credentials with the proper properties" {
                $results = New-DbaCredential -SqlInstance $script:instance1 -Name thorcred -CredentialIdentity thor -Password $password
                $results.Name | Should Be "thorcred"
                $results.Identity | Should Be "thor"

                $results = New-DbaCredential -SqlInstance $script:instance1 -CredentialIdentity thorsmomma -Password $password
                $results.Name | Should Be "thorsmomma"
                $results.Identity | Should Be "thorsmomma"
            }
        }

        Context "Copy Credential with the same properties." {
            It "Should copy successfully" {
                $results = Copy-DbaCredential -Source $script:instance1 -Destination $script:instance2 -CredentialIdentity thorcred
                $results.Status | Should Be "Successful"
            }

            It "Should retain its same properties" {

                $Credential1 = Get-DbaCredential -SqlInstance $script:instance1 -CredentialIdentity thor -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
                $Credential2 = Get-DbaCredential -SqlInstance $script:instance2 -CredentialIdentity thor -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

                # Compare its value
                $Credential1.Name | Should Be $Credential2.Name
                $Credential1.CredentialIdentity | Should Be $Credential2.CredentialIdentity
            }
        }

        Context "No overwrite" {
            $results = Copy-DbaCredential -Source $script:instance1 -Destination $script:instance2 -CredentialIdentity thorcred
            $results.Status | Should Be "Skipped"
        }
    }
}