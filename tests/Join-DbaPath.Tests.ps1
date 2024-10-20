param($ModuleName = 'dbatools')

Describe "Join-DbaPath" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Join-DbaPath
        }

        $params = @(
            "Path",
            "SqlInstance",
            "Child"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command usage" {
        It "Should join paths correctly" {
            $result = Join-DbaPath -Path "C:\Test" -Child "Subfolder", "file.txt"
            $result | Should -Be "C:\Test\Subfolder\file.txt"
        }

        It "Should handle UNC paths" {
            $result = Join-DbaPath -Path "\\server\share" -Child "folder", "subfolder", "file.txt"
            $result | Should -Be "\\server\share\folder\subfolder\file.txt"
        }

        It "Should work with SqlInstance parameter" {
            Mock Get-SqlDefaultPaths -ModuleName $ModuleName -MockWith {
                return @{
                    Data = "C:\SQLData"
                    Log  = "D:\SQLLogs"
                    Backup = "E:\SQLBackups"
                }
            }

            $result = Join-DbaPath -SqlInstance "TestInstance" -Child "MyDatabase.mdf"
            $result | Should -Be "C:\SQLData\MyDatabase.mdf"
        }
    }
}
