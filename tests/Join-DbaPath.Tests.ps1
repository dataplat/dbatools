param($ModuleName = 'dbatools')

Describe "Join-DbaPath" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Join-DbaPath
        }
        It "Should have Path as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type String -Not -Mandatory
        }
        It "Should have SqlInstance as a non-mandatory DbaInstanceParameter parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter -Not -Mandatory
        }
        It "Should have Child as a non-mandatory String[] parameter" {
            $CommandUnderTest | Should -HaveParameter Child -Type String[] -Not -Mandatory
        }
        It "Should have Verbose as a non-mandatory SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter Verbose -Type SwitchParameter -Not -Mandatory
        }
        It "Should have Debug as a non-mandatory SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter Debug -Type SwitchParameter -Not -Mandatory
        }
        It "Should have ErrorAction as a non-mandatory ActionPreference parameter" {
            $CommandUnderTest | Should -HaveParameter ErrorAction -Type ActionPreference -Not -Mandatory
        }
        It "Should have WarningAction as a non-mandatory ActionPreference parameter" {
            $CommandUnderTest | Should -HaveParameter WarningAction -Type ActionPreference -Not -Mandatory
        }
        It "Should have InformationAction as a non-mandatory ActionPreference parameter" {
            $CommandUnderTest | Should -HaveParameter InformationAction -Type ActionPreference -Not -Mandatory
        }
        It "Should have ProgressAction as a non-mandatory ActionPreference parameter" {
            $CommandUnderTest | Should -HaveParameter ProgressAction -Type ActionPreference -Not -Mandatory
        }
        It "Should have ErrorVariable as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter ErrorVariable -Type String -Not -Mandatory
        }
        It "Should have WarningVariable as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter WarningVariable -Type String -Not -Mandatory
        }
        It "Should have InformationVariable as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter InformationVariable -Type String -Not -Mandatory
        }
        It "Should have OutVariable as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter OutVariable -Type String -Not -Mandatory
        }
        It "Should have OutBuffer as a non-mandatory Int32 parameter" {
            $CommandUnderTest | Should -HaveParameter OutBuffer -Type Int32 -Not -Mandatory
        }
        It "Should have PipelineVariable as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter PipelineVariable -Type String -Not -Mandatory
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
