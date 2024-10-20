param($ModuleName = 'dbatools')

Describe "Export-DbaServerRole Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Export-DbaServerRole
        }
        It "has all the required parameters" {
            $params = @(
                "SqlInstance",
                "SqlCredential",
                "InputObject",
                "ScriptingOptionsObject",
                "ServerRole",
                "ExcludeServerRole",
                "ExcludeFixedRole",
                "IncludeRoleMember",
                "Path",
                "FilePath",
                "Passthru",
                "BatchSeparator",
                "NoClobber",
                "Append",
                "NoPrefix",
                "Encoding",
                "EnableException"
            )
            It "has the required parameter: <_>" -ForEach $params {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
        }
    }
}

Describe "Export-DbaServerRole Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        $AltExportPath = "$env:USERPROFILE\Documents"
        $outputFile = "$AltExportPath\Dbatoolsci_ServerRole.sql"
    }

    BeforeAll {
        $random = Get-Random
        $login1 = "dbatoolsci_exportdbaserverrole_login1$random"
        $svRole = "dbatoolsci_ScriptPermissions$random"

        $server = Connect-DbaInstance -SqlInstance $global:instance2
        $null = $server.Query("CREATE LOGIN [$login1] WITH PASSWORD = 'GoodPass1234!'")
        $null = $server.Query("CREATE SERVER ROLE [$svRole] AUTHORIZATION [$login1]")
        $null = $server.Query("ALTER SERVER ROLE [dbcreator] ADD MEMBER [$svRole]")
        $null = $server.Query("GRANT CREATE TRACE EVENT NOTIFICATION TO [$svRole]")
        $null = $server.Query("DENY SELECT ALL USER SECURABLES TO [$svRole]")
        $null = $server.Query("GRANT VIEW ANY DEFINITION TO [$svRole]")
        $null = $server.Query("GRANT VIEW ANY DATABASE TO [$svRole]")
    }

    AfterAll {
        Remove-DbaServerRole -SqlInstance $global:instance2 -ServerRole $svRole -Confirm:$false
        Remove-DbaLogin -SqlInstance $global:instance2 -Login $login1 -Confirm:$false
        Remove-Item -Path $outputFile -ErrorAction SilentlyContinue
    }

    Context "Check if output file was created" {
        BeforeAll {
            $null = Export-DbaServerRole -SqlInstance $global:instance2 -FilePath $outputFile
        }

        It "Exports results to one sql file" {
            (Get-ChildItem $outputFile).Count | Should -Be 1
        }

        It "Exported file is bigger than 0" {
            (Get-ChildItem $outputFile).Length | Should -BeGreaterThan 0
        }
    }

    Context "Check using piped input created" {
        BeforeAll {
            $role = Get-DbaServerRole -SqlInstance $global:instance2 -ServerRole $svRole
            $null = $role | Export-DbaServerRole -FilePath $outputFile
            $global:results = $role | Export-DbaServerRole -Passthru
        }

        It "Exports results to one sql file" {
            (Get-ChildItem $outputFile).Count | Should -Be 1
        }

        It "Exported file is bigger than 0" {
            (Get-ChildItem $outputFile).Length | Should -BeGreaterThan 0
        }

        It "should include the defined BatchSeparator" {
            $global:results | Should -Match "GO"
        }

        It "should include the role" {
            $global:results | Should -Match "CREATE SERVER ROLE [$svRole]"
        }

        It "should include ADD MEMBER" {
            $global:results | Should -Match "ALTER SERVER ROLE [dbcreator] ADD MEMBER [$svRole]"
        }

        It "should include GRANT CREATE TRACE EVENT" {
            $global:results | Should -Match "GRANT CREATE TRACE EVENT NOTIFICATION TO [$svRole]"
        }

        It "should include DENY SELECT ALL USER SECURABLES" {
            $global:results | Should -Match "DENY SELECT ALL USER SECURABLES TO [$svRole]"
        }

        It "should include VIEW ANY DEFINITION" {
            $global:results | Should -Match "GRANT VIEW ANY DEFINITION TO [$svRole];"
        }

        It "should include GRANT VIEW ANY DATABASE" {
            $global:results | Should -Match "GRANT VIEW ANY DATABASE TO [$svRole];"
        }
    }
}
