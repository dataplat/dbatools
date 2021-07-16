$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'ComputerName', 'Credential', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Can stop an external process" {
        BeforeAll {
            $null = Invoke-DbaQuery -SqlInstance $script:instance1 -Query "
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
            GO"
            $query = @"
            xp_cmdshell 'powershell -command ""sleep 20""'
"@
            Start-Process -FilePath sqlcmd -ArgumentList "-S $script:instance1 -Q `"$query`"" -NoNewWindow -RedirectStandardOutput null
        }

        It "returns results" {
            $results = Get-DbaExternalProcess -ComputerName localhost | Stop-DbaExternalProcess
            $results.ComputerName | Should -Be "localhost"
            $results.Name | Should -Be "cmd.exe"
            $results.ProcessId | Should -Not -Be $null
            $results.Status | Should -Be "Stopped"
        }
    }
}