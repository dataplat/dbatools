param($ModuleName = 'dbatools')

Describe "Stop-DbaExternalProcess" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Stop-DbaExternalProcess
        }
        $params = @(
            "ComputerName",
            "Credential",
            "ProcessId",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }
}

Describe "Stop-DbaExternalProcess Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"

        $null = Invoke-DbaQuery -SqlInstance $global:instance1 -Query @"
        -- To allow advanced options to be changed.
        EXECUTE sp_configure 'show advanced options', 1;
        GO
        -- To update the currently configured value for advanced options.
        RECONFIGURE;
        GO
        -- To enable the feature.
        EXECUTE sp_configure 'xp_cmdshell', 1;
        GO
        -- To update the currently configured value for this feature.
        RECONFIGURE;
        GO
"@

        $query = "xp_cmdshell 'powershell -command ""sleep 20""'"
        Start-Process -FilePath sqlcmd -ArgumentList "-S $global:instance1 -Q `"$query`"" -NoNewWindow -RedirectStandardOutput null
    }

    Context "Can stop an external process" {
        It "returns results" {
            $results = Get-DbaExternalProcess -ComputerName localhost | Select-Object -First 1 | Stop-DbaExternalProcess -Confirm:$false
            $results.ComputerName | Should -Be "localhost"
            $results.Name | Should -Be "cmd.exe"
            $results.ProcessId | Should -Not -BeNullOrEmpty
            $results.Status | Should -Be "Stopped"
        }
    }
}
