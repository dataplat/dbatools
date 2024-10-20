param($ModuleName = 'dbatools')

Describe "Get-DbaExternalProcess" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaExternalProcess
        }

        It "has the required parameter: <_>" -ForEach @(
            "ComputerName",
            "Credential",
            "EnableException"
        ) {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Integration Tests" -Tag "IntegrationTests" {
        BeforeAll {
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
            Start-Sleep -Seconds 1
        }

        It "returns a process" {
            $results = Get-DbaExternalProcess -ComputerName localhost | Select-Object -First 1
            $results.ComputerName | Should -Be "localhost"
            $results.Name | Should -Be "cmd.exe"
            $results.ProcessId | Should -Not -BeNullOrEmpty
        }
    }
}
