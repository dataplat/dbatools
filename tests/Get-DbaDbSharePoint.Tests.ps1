param($ModuleName = 'dbatools')

Describe "Get-DbaDbSharePoint" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbSharePoint
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "ConfigDatabase",
                "InputObject",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command gets SharePoint Databases" {
        BeforeAll {
            $skip = $false
            $spdb = 'SharePoint_Admin_7c0c491d0e6f43858f75afa5399d49ab', 'WSS_Logging', 'SecureStoreService_20e1764876504335a6d8dd0b1937f4bf', 'DefaultWebApplicationDB', 'SharePoint_Config_4c524cb90be44c6f906290fe3e34f2e0', 'DefaultPowerPivotServiceApplicationDB-5b638361-c6fc-4ad9-b8ba-d05e63e48ac6', 'SharePoint_Config_4c524cb90be44c6f906290fe3e34f2e0'
            Get-DbaProcess -SqlInstance $global:instance2 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            foreach ($db in $spdb) {
                try {
                    $null = $server.Query("Create Database [$db]")
                } catch { continue }
            }

            $bacpac = "$global:appveyorlabrepo\bacpac\sharepoint_config.bacpac"
            if (Test-Path -Path $bacpac) {
                $sqlpackage = (Get-Command sqlpackage -ErrorAction Ignore).Source
                if (-not $sqlpackage) {
                    $libraryPath = Get-DbatoolsLibraryPath
                    if ($libraryPath -match 'desktop$') {
                        $sqlpackage = Join-DbaPath -Path (Get-DbatoolsLibraryPath) -ChildPath lib, sqlpackage.exe
                    } elseif ($isWindows) {
                        $sqlpackage = Join-DbaPath -Path (Get-DbatoolsLibraryPath) -ChildPath lib, win, sqlpackage.exe
                    } else {
                        # Not implemented
                    }
                }
                $skip = $true
            } else {
                Write-Warning -Message "No bacpac found in path [$bacpac], skipping tests."
                $skip = $true
            }
        }

        AfterAll {
            Remove-DbaDatabase -SqlInstance $global:instance2 -Database $spdb -Confirm:$false
        }

        It "Returns <_> from in the SharePoint database list" -Skip:$skip -ForEach $spdb {
            $results = Get-DbaDbSharePoint -SqlInstance $global:instance2
            $_ | Should -BeIn $results.Name
        }
    }
}
