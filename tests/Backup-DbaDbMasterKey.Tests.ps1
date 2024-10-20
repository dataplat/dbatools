param($ModuleName = 'dbatools')

Describe "Backup-DbaDbMasterKey" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Backup-DbaDbMasterKey
        }

        It "has all the required parameters" {
            $params = @(
                "SqlInstance",
                "SqlCredential",
                "Credential",
                "Database",
                "ExcludeDatabase",
                "SecurePassword",
                "Path",
                "InputObject",
                "EnableException",
                "WhatIf",
                "Confirm"
            )
            It "has the required parameter: <_>" -ForEach $params {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        BeforeAll {
            $password = ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force
            $server = Connect-DbaInstance -SqlInstance $global:instance1
            if (-not (Get-DbaDbMasterKey -SqlInstance $server -Database tempdb)) {
                $null = New-DbaDbMasterKey -SqlInstance $server -Database tempdb -Password $password -Confirm:$false
            }
        }

        AfterAll {
            $null = Get-DbaDbMasterKey -SqlInstance $server -Database tempdb | Remove-DbaDbMasterKey -Confirm:$false
        }

        It "backs up the db master key" {
            $results = Backup-DbaDbMasterKey -SqlInstance $server -Database tempdb -Password $password -Confirm:$false
            $null = Remove-Item -Path $results.Path -ErrorAction SilentlyContinue -Confirm:$false

            $results.Database | Should -Be 'tempdb'
            $results.Status | Should -Be "Success"
        }

        It "returns the correct Database ID" {
            $results = Backup-DbaDbMasterKey -SqlInstance $server -Database tempdb -Password $password -Confirm:$false
            $null = Remove-Item -Path $results.Path -ErrorAction SilentlyContinue -Confirm:$false

            $results.DatabaseID | Should -Be (Get-DbaDatabase -SqlInstance $server -Database tempdb).ID
        }
    }
}
