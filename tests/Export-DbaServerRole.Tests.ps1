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
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Object[] -Not -Mandatory
        }
        It "Should have ScriptingOptionsObject parameter" {
            $CommandUnderTest | Should -HaveParameter ScriptingOptionsObject -Type ScriptingOptions -Not -Mandatory
        }
        It "Should have ServerRole parameter" {
            $CommandUnderTest | Should -HaveParameter ServerRole -Type String[] -Not -Mandatory
        }
        It "Should have ExcludeServerRole parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeServerRole -Type String[] -Not -Mandatory
        }
        It "Should have ExcludeFixedRole parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeFixedRole -Type SwitchParameter -Not -Mandatory
        }
        It "Should have IncludeRoleMember parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeRoleMember -Type SwitchParameter -Not -Mandatory
        }
        It "Should have Path parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type String -Not -Mandatory
        }
        It "Should have FilePath parameter" {
            $CommandUnderTest | Should -HaveParameter FilePath -Type String -Not -Mandatory
        }
        It "Should have Passthru parameter" {
            $CommandUnderTest | Should -HaveParameter Passthru -Type SwitchParameter -Not -Mandatory
        }
        It "Should have BatchSeparator parameter" {
            $CommandUnderTest | Should -HaveParameter BatchSeparator -Type String -Not -Mandatory
        }
        It "Should have NoClobber parameter" {
            $CommandUnderTest | Should -HaveParameter NoClobber -Type SwitchParameter -Not -Mandatory
        }
        It "Should have Append parameter" {
            $CommandUnderTest | Should -HaveParameter Append -Type SwitchParameter -Not -Mandatory
        }
        It "Should have NoPrefix parameter" {
            $CommandUnderTest | Should -HaveParameter NoPrefix -Type SwitchParameter -Not -Mandatory
        }
        It "Should have Encoding parameter" {
            $CommandUnderTest | Should -HaveParameter Encoding -Type String -Not -Mandatory
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter -Not -Mandatory
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

        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $null = $server.Query("CREATE LOGIN [$login1] WITH PASSWORD = 'GoodPass1234!'")
        $null = $server.Query("CREATE SERVER ROLE [$svRole] AUTHORIZATION [$login1]")
        $null = $server.Query("ALTER SERVER ROLE [dbcreator] ADD MEMBER [$svRole]")
        $null = $server.Query("GRANT CREATE TRACE EVENT NOTIFICATION TO [$svRole]")
        $null = $server.Query("DENY SELECT ALL USER SECURABLES TO [$svRole]")
        $null = $server.Query("GRANT VIEW ANY DEFINITION TO [$svRole]")
        $null = $server.Query("GRANT VIEW ANY DATABASE TO [$svRole]")
    }

    AfterAll {
        Remove-DbaServerRole -SqlInstance $script:instance2 -ServerRole $svRole -Confirm:$false
        Remove-DbaLogin -SqlInstance $script:instance2 -Login $login1 -Confirm:$false
        Remove-Item -Path $outputFile -ErrorAction SilentlyContinue
    }

    Context "Check if output file was created" {
        BeforeAll {
            $null = Export-DbaServerRole -SqlInstance $script:instance2 -FilePath $outputFile
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
            $role = Get-DbaServerRole -SqlInstance $script:instance2 -ServerRole $svRole
            $null = $role | Export-DbaServerRole -FilePath $outputFile
            $script:results = $role | Export-DbaServerRole -Passthru
        }

        It "Exports results to one sql file" {
            (Get-ChildItem $outputFile).Count | Should -Be 1
        }

        It "Exported file is bigger than 0" {
            (Get-ChildItem $outputFile).Length | Should -BeGreaterThan 0
        }

        It "should include the defined BatchSeparator" {
            $script:results | Should -Match "GO"
        }

        It "should include the role" {
            $script:results | Should -Match "CREATE SERVER ROLE [$svRole]"
        }

        It "should include ADD MEMBER" {
            $script:results | Should -Match "ALTER SERVER ROLE [dbcreator] ADD MEMBER [$svRole]"
        }

        It "should include GRANT CREATE TRACE EVENT" {
            $script:results | Should -Match "GRANT CREATE TRACE EVENT NOTIFICATION TO [$svRole]"
        }

        It "should include DENY SELECT ALL USER SECURABLES" {
            $script:results | Should -Match "DENY SELECT ALL USER SECURABLES TO [$svRole]"
        }

        It "should include VIEW ANY DEFINITION" {
            $script:results | Should -Match "GRANT VIEW ANY DEFINITION TO [$svRole];"
        }

        It "should include GRANT VIEW ANY DATABASE" {
            $script:results | Should -Match "GRANT VIEW ANY DATABASE TO [$svRole];"
        }
    }
}
