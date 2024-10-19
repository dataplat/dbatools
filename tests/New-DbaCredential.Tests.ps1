param($ModuleName = 'dbatools')

Describe 'New-DbaCredential' -Tag 'UnitTests', 'IntegrationTests' {

    BeforeAll {
        $CommandName = 'New-DbaCredential'
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
        . "$PSScriptRoot\..\private\functions\Invoke-Command2.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command -Name $CommandName
        }
        It "Accepts SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter -Name 'SqlInstance'
        }
        It "Accepts SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter -Name 'SqlCredential'
        }
        It "Accepts Name as a parameter" {
            $CommandUnderTest | Should -HaveParameter -Name 'Name'
        }
        It "Accepts Identity as a parameter" {
            $CommandUnderTest | Should -HaveParameter -Name 'Identity'
        }
        It "Accepts SecurePassword as a parameter" {
            $CommandUnderTest | Should -HaveParameter -Name 'SecurePassword'
        }
        It "Accepts MappedClassType as a parameter" {
            $CommandUnderTest | Should -HaveParameter -Name 'MappedClassType'
        }
        It "Accepts ProviderName as a parameter" {
            $CommandUnderTest | Should -HaveParameter -Name 'ProviderName'
        }
        It "Accepts Force as a parameter" {
            $CommandUnderTest | Should -HaveParameter -Name 'Force'
        }
        It "Accepts EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter -Name 'EnableException'
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            $logins   = "dbatoolsci_thor", "dbatoolsci_thorsmomma"
            $plaintext = "BigOlPassword!"
            $password  = ConvertTo-SecureString $plaintext -AsPlainText -Force

            # Add users
            foreach ($login in $logins) {
                $null = Invoke-Command2 -ScriptBlock { net user $using:login $using:plaintext /add *>&1 } -ComputerName $global:instance2
            }
        }

        AfterAll {
            try {
                (Get-DbaCredential -SqlInstance $global:instance2 -Identity dbatoolsci_thor, dbatoolsci_thorsmomma -ErrorAction Stop -WarningAction SilentlyContinue) | ForEach-Object { $_.Drop() }
                (Get-DbaCredential -SqlInstance $global:instance2 -Name "https://mystorageaccount.blob.core.windows.net/mycontainer" -ErrorAction Stop -WarningAction SilentlyContinue).Drop()
            } catch { }

            foreach ($login in $logins) {
                $null = Invoke-Command2 -ScriptBlock { net user $using:login /delete *>&1 } -ComputerName $global:instance2
            }
        }

        Context "Create a new credential" {
            It "Should create new credentials with the proper properties" {
                $results = New-DbaCredential -SqlInstance $global:instance2 -Name dbatoolsci_thorcred -Identity dbatoolsci_thor -Password $password
                $results.Name     | Should -Be "dbatoolsci_thorcred"
                $results.Identity | Should -Be "dbatoolsci_thor"

                $results = New-DbaCredential -SqlInstance $global:instance2 -Identity dbatoolsci_thorsmomma -Password $password
                $results | Should -Not -Be $null
            }
            It "Gets the newly created credential" {
                $results = Get-DbaCredential -SqlInstance $global:instance2 -Identity dbatoolsci_thorsmomma
                $results.Name     | Should -Be "dbatoolsci_thorsmomma"
                $results.Identity | Should -Be "dbatoolsci_thorsmomma"
            }
        }

        Context "Create a new credential without password" {
            It "Should create new credentials with the proper properties but without password" {
                $credentialParams = @{
                    SqlInstance = $global:instance2
                    Name        = "https://mystorageaccount.blob.core.windows.net/mycontainer"
                    Identity    = 'Managed Identity'
                }
                $results = New-DbaCredential @credentialParams
                $results.Name     | Should -Be "https://mystorageaccount.blob.core.windows.net/mycontainer"
                $results.Identity | Should -Be "Managed Identity"
            }
            It "Gets the newly created credential that doesn't have password" {
                $results = Get-DbaCredential -SqlInstance $global:instance2 -Identity "Managed Identity"
                $results.Name     | Should -Be "https://mystorageaccount.blob.core.windows.net/mycontainer"
                $results.Identity | Should -Be "Managed Identity"
            }
        }
    }
}
