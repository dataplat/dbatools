$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

$global:instance1 = $script:instance1

#InModuleScope -ModuleName 'dbatools' {
    Context "$commandname Unit Tests" -Tag 'UnitTests' {
        Mock -ModuleName dbatools Invoke-Command -ParameterFilter { $ComputerName -eq 'Mocked' } { $true }

        It "Errors when it can't connect to the instance" {
            Mock -ModuleName dbatools Connect-SqlInstance -Verifiable -ParameterFilter { [string]$SqlInstance -eq 'MadeUpServer' } {
                throw
            }

            { Set-DbaBackupPath -SqlInstance 'MadeUpServer' -Path 'Q:\Backups' -EnableException } | Should Throw

            Assert-VerifiableMock
        }

        Mock -ModuleName dbatools Connect-SqlInstance -Verifiable {
            [PSCustomObject]@{
                NetName            = 'Mocked'
                ServiceName        = 'Mocked'
                DomainInstanceName = 'Mocked'
                BackupDirectory    = 'C:\MockedBackupDirectory'
            }
        }

        Mock -ModuleName dbatools Test-SqlSa -Verifiable { $true }
        Mock -ModuleName dbatools Test-ShouldProcess -Verifiable { $false }

        It "Accepts servers from the pipeline" {
            $results = 'server1', 'server2' | Set-DbaBackupPath -Path 'Q:\Backups' -EnableException
            $results.Count | Should Be 2

            Assert-VerifiableMock
        }

        It "Errors if the user doesn't have access to set the backup directory" {
            Mock -ModuleName dbatools Test-SqlSa -Verifiable { $false }

            { Set-DbaBackupPath -SqlInstance 'server1' -Path 'Q:\Backups' -EnableException } | Should Throw

            Assert-VerifiableMock
        }
    }

    Context "$commandname Integration Tests" -Tag "IntegrationTests" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance1

            $login = 'dbatoolsci_setdbabackuppath'

            $securePassword = $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force)
            $null = New-DbaLogin -SqlInstance $server -Login $login -Password $securePassword

            $sqlCred = New-Object System.Management.Automation.PSCredential ($login, $securePassword)

            $oldBackupPath = $server.BackupDirectory

            $random = Get-Random
            $newBackupPath = "C:\$random"
        }

        AfterAll {
            $null = Get-DbaProcess -SqlInstance $global:instance1 -Login $login | Stop-DbaProcess
            $null = Remove-DbaLogin -SqlInstance $global:instance1 -Login $login -Confirm:$false

            # reset backup directory
            try {
                $server.BackupDirectory = $oldBackupPath
                $server.Alter()
            }
            catch {
                Write-Host "Could not change backup directory back to $oldBackupPath"
            }

            # clean up backup directories
            try {
                Invoke-Command -ComputerName $server.NetName {
                    param ($Path)

                    Remove-Item $Path -Force
                } -ArgumentList $newBackupPath
            }
            catch {
                Write-Warning "Could not cleanup from test"
            }
        }

        Mock -ModuleName dbatools Test-ShouldProcess { $true }

        It "Errors if it can't actually be applied" {
            Mock -ModuleName dbatools Test-SqlSa -Verifiable { $true }

            { Set-DbaBackupPath -SqlInstance $global:instance1 -Path 'C:\Backups' -SqlCredential $sqlCred -EnableException } | Should Throw

            Assert-VerifiableMock
        }

        $result = Set-DbaBackupPath -SqlInstance $server -Path $newBackupPath -EnableException

        It "Creates the path if it doesn't exist" {
            Invoke-Command -ComputerName $server.NetName -ScriptBlock {
                param ($Path)

                Test-Path -Path $Path
            } -ArgumentList $newBackupPath | Should Be $true
        }

        It "Grants access to the instance account if it doesn't have access" {
            $accounts = Invoke-Command -ComputerName $server.NetName -ScriptBlock {
                param ($ServiceAccount, $Path)

                $acl = Get-Acl -Path $Path
                $acl.Access.IdentityReference.Value | Select -Unique
            } -ArgumentList $server.ServiceAccount, $newBackupPath

            $server.ServiceAccount | Should BeIn $accounts
        }

        It "Sets the path" {
            $result.BackupPath -eq $newBackupPath | Should Be $true
        }
    }
#}