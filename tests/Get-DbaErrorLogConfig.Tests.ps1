param($ModuleName = 'dbatools')

Describe "Get-DbaErrorLogConfig" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaErrorLogConfig
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Get NumberErrorLog for multiple instances" {
        BeforeAll {
            $results = Get-DbaErrorLogConfig -SqlInstance $global:instance3, $global:instance2
        }

        It 'returns 3 values for each result' {
            foreach ($result in $results) {
                $result.LogCount | Should -Not -BeNullOrEmpty
                $result.LogSize | Should -Not -BeNullOrEmpty
                $result.LogPath | Should -Not -BeNullOrEmpty
            }
        }
    }
}
