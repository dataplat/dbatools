param($ModuleName = 'dbatools')

Describe "Set-DbaErrorLogConfig" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaErrorLogConfig
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "LogCount",
                "LogSize",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $logfiles = $server.NumberOfLogFiles
            $logsize = $server.ErrorLogSizeKb

            $server.NumberOfLogFiles = 4
            $server.ErrorLogSizeKb = 1024
            $server.Alter()

            $server = Connect-DbaInstance -SqlInstance $global:instance1
            $logfiles2 = $server.NumberOfLogFiles
            $logsize2 = $server.ErrorLogSizeKb

            $server.NumberOfLogFiles = 4
            $server.Alter()
        }
        AfterAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance1
            $server.NumberOfLogFiles = $logfiles2
            $server.Alter()

            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $server.NumberOfLogFiles = $logfiles
            $server.ErrorLogSizeKb = $logsize
            $server.Alter()
        }

        Context "Apply LogCount to multiple instances" {
            BeforeAll {
                $results = Set-DbaErrorLogConfig -SqlInstance $global:instance2, $global:instance1 -LogCount 8
            }
            It 'Returns LogCount set to 8 for each instance' {
                foreach ($result in $results) {
                    $result.LogCount | Should -Be 8
                }
            }
        }
        Context "Apply LogSize to multiple instances" {
            BeforeAll {
                $results = Set-DbaErrorLogConfig -SqlInstance $global:instance2, $global:instance1 -LogSize 100 -WarningAction SilentlyContinue -WarningVariable warn2
            }
            It 'Returns LogSize set to 100 for each instance' {
                foreach ($result in $results) {
                    $result.LogSize.Kilobyte | Should -Be 100
                }
            }
        }
    }
}
