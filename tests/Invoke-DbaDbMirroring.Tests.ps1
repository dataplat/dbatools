param($ModuleName = 'dbatools')

Describe "Invoke-DbaDbMirroring" {
    BeforeAll {
        $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Invoke-DbaDbMirroring
        }

        $params = @(
            "Primary",
            "PrimarySqlCredential",
            "Mirror",
            "MirrorSqlCredential",
            "Witness",
            "WitnessSqlCredential",
            "Database",
            "EndpointEncryption",
            "EncryptionAlgorithm",
            "SharedPath",
            "InputObject",
            "UseLastBackup",
            "Force",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command usage" {
        BeforeAll {
            $null = Get-DbaProcess -SqlInstance $global:instance2 | Where-Object Program -Match dbatools | Stop-DbaProcess -Confirm:$false -WarningAction SilentlyContinue
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $db1 = "dbatoolsci_mirroring"

            Remove-DbaDbMirror -SqlInstance $global:instance2 -Database $db1 -Confirm:$false
            Remove-DbaDatabase -SqlInstance $global:instance2 -Database $db1 -Confirm:$false
            $null = Get-DbaDatabase -SqlInstance $global:instance2 -Database $db1 | Remove-DbaDatabase -Confirm:$false
            $null = $server.Query("CREATE DATABASE $db1")

            Get-DbaEndpoint -SqlInstance $global:instance2 -Type DatabaseMirroring | Remove-DbaEndpoint -Confirm:$false
            New-DbaEndpoint -SqlInstance $global:instance2 -Name dbatoolsci_MirroringEndpoint -Type DatabaseMirroring -Port 5022 -Owner sa
            Get-DbaEndpoint -SqlInstance $global:instance3 -Type DatabaseMirroring | Remove-DbaEndpoint -Confirm:$false
            New-DbaEndpoint -SqlInstance $global:instance3 -Name dbatoolsci_MirroringEndpoint -Type DatabaseMirroring -Port 5023 -Owner sa
        }

        AfterAll {
            $null = Remove-DbaDbMirror -SqlInstance $global:instance2, $global:instance3 -Database $db1 -Confirm:$false
            $null = Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance2, $global:instance3 -Database $db1 -ErrorAction SilentlyContinue
        }

        It "returns success" {
            $results = Invoke-DbaDbMirroring -Primary $global:instance2 -Mirror $global:instance3 -Database $db1 -Confirm:$false -Force -SharedPath C:\temp -WarningVariable warn
            $warn | Should -BeNullOrEmpty
            $results.Status | Should -Be 'Success'
        }
    }
}
