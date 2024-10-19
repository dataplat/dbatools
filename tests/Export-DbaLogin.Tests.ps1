param($ModuleName = 'dbatools')

Describe "Export-DbaLogin" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $DefaultExportPath = Get-DbatoolsConfigValue -FullName path.dbatoolsexport
        $AltExportPath = "$env:USERPROFILE\Documents"
        $random = Get-Random
        $dbname1 = "dbatoolsci_exportdbalogin1$random"
        $login1 = "dbatoolsci_exportdbalogin_login1$random"
        $user1 = "dbatoolsci_exportdbalogin_user1$random"

        $dbname2 = "dbatoolsci_exportdbalogin2$random"
        $login2 = "dbatoolsci_exportdbalogin_login2$random"
        $user2 = "dbatoolsci_exportdbalogin_user2$random"

        $server = Connect-DbaInstance -SqlInstance $global:instance2
        $db1 = New-DbaDatabase -SqlInstance $server -Name $dbname1
        $null = $server.Query("CREATE LOGIN [$login1] WITH PASSWORD = 'GoodPass1234!'")
        $db1.Query("CREATE USER [$user1] FOR LOGIN [$login1]")

        $db2 = New-DbaDatabase -SqlInstance $server -Name $dbname2
        $null = $server.Query("CREATE LOGIN [$login2] WITH PASSWORD = 'GoodPass1234!'")
        $null = $server.Query("ALTER LOGIN [$login2] DISABLE")
        $null = $server.Query("DENY CONNECT SQL TO [$login2]")

        if ($server.VersionMajor -lt 11) {
            $null = $server.Query("EXEC sys.sp_addsrvrolemember @rolename=N'dbcreator', @loginame=N'$login2'")
        } else {
            $null = $server.Query("ALTER SERVER ROLE [dbcreator] ADD MEMBER [$login2]")
        }
        $db2.Query("CREATE USER [$user2] FOR LOGIN [$login2]")
        $db2.Query("GRANT SELECT ON sys.tables TO [$user2] WITH GRANT OPTION")

        # login and user that have the same name but aren't linked
        $login3 = "dbatoolsci_exportdbalogin_login3$random"
        $server.Query("CREATE LOGIN [$login3] WITH PASSWORD = 'GoodPass1234!'")
        $db1.Query("CREATE USER [$login3] WITHOUT LOGIN")
    }

    AfterAll {
        Remove-DbaDatabase -SqlInstance $global:instance2 -Database $dbname1 -Confirm:$false
        Remove-DbaLogin -SqlInstance $global:instance2 -Login $login1 -Confirm:$false

        Remove-DbaDatabase -SqlInstance $global:instance2 -Database $dbname2 -Confirm:$false
        Remove-DbaLogin -SqlInstance $global:instance2 -Login $login2 -Confirm:$false
        $timenow = (Get-Date -uformat "%m%d%Y%H")
        $ExportedCredential = Get-ChildItem $DefaultExportPath, $AltExportPath | Where-Object { $_.Name -match "$timenow\d{4}-login.sql|Dbatoolsci_login_CustomFile.sql" }
        if ($ExportedCredential) {
            $null = Remove-Item -Path $($ExportedCredential.FullName) -ErrorAction SilentlyContinue
        }

        Remove-DbaLogin -SqlInstance $global:instance2 -Login $login3 -Confirm:$false
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Export-DbaLogin
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have Login as a parameter" {
            $CommandUnderTest | Should -HaveParameter Login
        }
        It "Should have ExcludeLogin as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeLogin
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have ExcludeJobs as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeJobs
        }
        It "Should have ExcludeDatabase as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase
        }
        It "Should have ExcludePassword as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludePassword
        }
        It "Should have DefaultDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter DefaultDatabase
        }
        It "Should have Path as a parameter" {
            $CommandUnderTest | Should -HaveParameter Path
        }
        It "Should have FilePath as a parameter" {
            $CommandUnderTest | Should -HaveParameter FilePath
        }
        It "Should have Encoding as a parameter" {
            $CommandUnderTest | Should -HaveParameter Encoding
        }
        It "Should have NoClobber as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter NoClobber
        }
        It "Should have Append as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Append
        }
        It "Should have BatchSeparator as a parameter" {
            $CommandUnderTest | Should -HaveParameter BatchSeparator
        }
        It "Should have DestinationVersion as a parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationVersion
        }
        It "Should have NoPrefix as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter NoPrefix
        }
        It "Should have Passthru as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Passthru
        }
        It "Should have ObjectLevel as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter ObjectLevel
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Executes with Exclude Parameters" {
        It "Should exclude databases when exporting" {
            $file = Export-DbaLogin -SqlInstance $global:instance2 -ExcludeDatabase -WarningAction SilentlyContinue
            $results = Get-Content -Path $file -Raw
            $results | Should -Match '\nGo\r'
        }
        It "Should exclude Jobs when exporting" {
            $file = Export-DbaLogin -SqlInstance $global:instance2 -ExcludeJobs -WarningAction SilentlyContinue
            $results = Get-Content -Path $file -Raw
            $results | Should -Not -Match 'Job'
        }
        It "Should exclude Go when exporting" {
            $file = Export-DbaLogin -SqlInstance $global:instance2 -BatchSeparator '' -ObjectLevel -WarningAction SilentlyContinue
            $results = Get-Content -Path $file -Raw
            $results | Should -Not -Match 'GO'
            $results | Should -Match "GRANT SELECT ON OBJECT::\[sys\]\.\[tables\] TO \[$user2\] WITH GRANT OPTION"
            $results | Should -Match "CREATE USER \[$user2\] FOR LOGIN \[$login2\]"
            $results | Should -Match "IF NOT EXISTS"
            $results | Should -Match "USE \[$dbname2\]"
        }
        It "Should exclude a specific login" {
            $file = Export-DbaLogin -SqlInstance $global:instance2 -ExcludeLogin $login1 -WarningAction SilentlyContinue
            $results = Get-Content -Path $file -Raw
            $results | Should -Not -Match "$login1"
        }
        It "Should exclude passwords" {
            $file = Export-DbaLogin -SqlInstance $global:instance2 -ExcludeLogin $login1 -WarningAction SilentlyContinue -ExcludePassword
            $results = Get-Content -Path $file -Raw
            $results | Should -Not -Match '(?<=PASSWORD =\s0x)(\w+)'
        }
    }

    Context "Executes for various users, databases, and environments" {
        It "Should Export a specific user" {
            $file = Export-DbaLogin -SqlInstance $global:instance2 -Login $login1 -Database $dbname1 -DefaultDatabase master -WarningAction SilentlyContinue
            $results = Get-Content -Path $file -Raw
            $results | Should -Not -Match "$login2|$dbname2"
            $results | Should -Match "$login1|$dbname1"
            $results | Should -Match ([regex]::Escape("IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'$user1')"))
        }
        It "Should Export with object level permissions" {
            $results = Export-DbaLogin -SqlInstance $global:instance2 -Login $login2 -ObjectLevel -PassThru -WarningAction SilentlyContinue
            $results | Should -Not -Match "$login1|$dbname1"
            $results | Should -Match "GRANT SELECT ON OBJECT::\[sys\]\.\[tables\] TO \[$user2\] WITH GRANT OPTION"
            $results | Should -Match "CREATE USER \[$user2\] FOR LOGIN \[$login2\]"
            $results | Should -Match "IF NOT EXISTS"
            $results | Should -Match "USE \[$dbname2\]"
        }
        It "Should Export for the SQLVersion <_>" -ForEach @((Get-Command $CommandName).Parameters.DestinationVersion.Attributes.ValidValues) {
            $file = Export-DbaLogin -SqlInstance $global:instance2 -Login $login2 -Database $dbname2 -DestinationVersion $_ -WarningAction SilentlyContinue
            $results = Get-Content -Path $file -Raw
            $results | Should -Match "$login2|$dbname2"
            $results | Should -Not -Match "$login1|$dbname1"
        }
        It "Should Export only logins from the db that is piped in" {
            $file = $db1 | Export-DbaLogin
            $results = Get-Content -Path $file -Raw
            $results | Should -Not -Match "$login2|$dbname2|$login3"
            $results | Should -Match "$login1|$dbname1"
            $results | Should -Match ([regex]::Escape("IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'$user1')"))
        }
    }

    Context "Exports file to random and specified paths" {
        It "Should export file to the configured path" {
            $file = Export-DbaLogin -SqlInstance $global:instance2 -ExcludeDatabase -WarningAction SilentlyContinue
            $results = $file.DirectoryName
            $results | Should -Be $DefaultExportPath
        }
        It "Should export file to custom folder path" {
            $file = Export-DbaLogin -SqlInstance $global:instance2 -Path $AltExportPath -ExcludeDatabase -WarningAction SilentlyContinue
            $results = $file.DirectoryName
            $results | Should -Be $AltExportPath
        }
        It "Should export file to custom file path" {
            $file = Export-DbaLogin -SqlInstance $global:instance2 -FilePath "$AltExportPath\Dbatoolsci_login_CustomFile.sql" -ExcludeDatabase -WarningAction SilentlyContinue
            $results = $file.Name
            $results | Should -Be "Dbatoolsci_login_CustomFile.sql"
        }
        It "Should export file to custom file path and Append" {
            $file = Export-DbaLogin -SqlInstance $global:instance2 -FilePath "$AltExportPath\Dbatoolsci_login_CustomFile.sql" -Append -ExcludeDatabase -WarningAction SilentlyContinue
            $file.CreationTimeUtc.Ticks | Should -BeLessThan $file.LastWriteTimeUtc.Ticks
        }
        It "Should not export file to custom file path with NoClobber" {
            { Export-DbaLogin -SqlInstance $global:instance2 -FilePath "$AltExportPath\Dbatoolsci_login_CustomFile.sql" -NoClobber -WarningAction SilentlyContinue } | Should -Throw
        }
    }
}
