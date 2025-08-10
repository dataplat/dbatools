$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'InputObject', 'Login', 'ExcludeLogin', 'Database', 'ExcludeJobs', 'ExcludeDatabase', 'ExcludePassword', 'DefaultDatabase', 'Path', 'FilePath', 'Encoding', 'NoClobber', 'Append', 'BatchSeparator', 'DestinationVersion', 'NoPrefix', 'Passthru', 'ObjectLevel', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $DefaultExportPath = Get-DbatoolsConfigValue -FullName path.dbatoolsexport
        $AltExportPath = "$env:USERPROFILE\Documents"
        $random = Get-Random
        $dbname1 = "dbatoolsci_exportdbalogin1$random"
        $login1 = "dbatoolsci_exportdbalogin_login1$random"
        $user1 = "dbatoolsci_exportdbalogin_user1$random"

        $dbname2 = "dbatoolsci_exportdbalogin2$random"
        $login2 = "dbatoolsci_exportdbalogin_login2$random"
        $user2 = "dbatoolsci_exportdbalogin_user2$random"

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
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
        Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname1 -Confirm:$false
        Remove-DbaLogin -SqlInstance $TestConfig.instance2 -Login $login1 -Confirm:$false

        Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname2 -Confirm:$false
        Remove-DbaLogin -SqlInstance $TestConfig.instance2 -Login $login2 -Confirm:$false
        $timenow = (Get-Date -uformat "%m%d%Y%H")
        $ExportedCredential = Get-ChildItem $DefaultExportPath, $AltExportPath | Where-Object { $_.Name -match "$timenow\d{4}-login.sql|Dbatoolsci_login_CustomFile.sql" }
        if ($ExportedCredential) {
            $null = Remove-Item -Path $($ExportedCredential.FullName) -ErrorAction SilentlyContinue
        }

        Remove-DbaLogin -SqlInstance $TestConfig.instance2 -Login $login3 -Confirm:$false
    }

    Context "Executes with Exclude Parameters" {
        It "Should exclude databases when exporting" {
            $file = Export-DbaLogin -SqlInstance $TestConfig.instance2 -ExcludeDatabase -WarningAction SilentlyContinue
            $results = Get-Content -Path $file -Raw
            $allfiles += $file.FullName
            $results | Should Match '\nGo\r'
        }
        It "Should exclude Jobs when exporting" {
            $file = Export-DbaLogin -SqlInstance $TestConfig.instance2 -ExcludeJobs -WarningAction SilentlyContinue
            $results = Get-Content -Path $file -Raw
            $allfiles += $file.FullName
            $results | Should Not Match 'Job'
        }
        It "Should exclude Go when exporting" {
            $file = Export-DbaLogin -SqlInstance $TestConfig.instance2 -BatchSeparator '' -ObjectLevel -WarningAction SilentlyContinue
            $results = Get-Content -Path $file -Raw
            $allfiles += $file.FullName
            $results | Should Not Match 'GO'
            $results | Should Match "GRANT SELECT ON OBJECT::\[sys\]\.\[tables\] TO \[$user2\] WITH GRANT OPTION"
            $results | Should Match "CREATE USER \[$user2\] FOR LOGIN \[$login2\]"
            $results | Should Match "IF NOT EXISTS"
            $results | Should Match "USE \[$dbname2\]"
        }
        It "Should exclude a specific login" {
            $file = Export-DbaLogin -SqlInstance $TestConfig.instance2 -ExcludeLogin $login1 -WarningAction SilentlyContinue
            $results = Get-Content -Path $file -Raw
            $allfiles += $file.FullName
            $results | Should Not Match "$login1"
        }
        It "Should exclude passwords" {
            $file = Export-DbaLogin -SqlInstance $TestConfig.instance2 -ExcludeLogin $login1 -WarningAction SilentlyContinue -ExcludePassword
            $results = Get-Content -Path $file -Raw
            $allfiles += $file.FullName
            $results | Should Not Match '(?<=PASSWORD =\s0x)(\w+)'
        }
    }
    Context "Executes for various users, databases, and environments" {
        It "Should Export a specific user" {
            $file = Export-DbaLogin -SqlInstance $TestConfig.instance2 -Login $login1 -Database $dbname1 -DefaultDatabase master -WarningAction SilentlyContinue
            $results = Get-Content -Path $file -Raw
            $allfiles += $file.FullName
            $results | Should Not Match "$login2|$dbname2"
            $results | Should Match "$login1|$dbname1"
            $results | Should -Match ([regex]::Escape("IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'$user1')"))
        }
        It "Should Export with object level permissions" {
            $results = Export-DbaLogin -SqlInstance $TestConfig.instance2 -Login $login2 -ObjectLevel -PassThru -WarningAction SilentlyContinue
            $results | Should Not Match "$login1|$dbname1"
            $results | Should Match "GRANT SELECT ON OBJECT::\[sys\]\.\[tables\] TO \[$user2\] WITH GRANT OPTION"
            $results | Should Match "CREATE USER \[$user2\] FOR LOGIN \[$login2\]"
            $results | Should Match "IF NOT EXISTS"
            $results | Should Match "USE \[$dbname2\]"
        }
        foreach ($version in $((Get-Command $CommandName).Parameters.DestinationVersion.attributes.validvalues)) {
            It "Should Export for the SQLVersion $version" {
                $file = Export-DbaLogin -SqlInstance $TestConfig.instance2 -Login $login2 -Database $dbname2 -DestinationVersion $version -WarningAction SilentlyContinue
                $results = Get-Content -Path $file -Raw
                $allfiles += $file.FullName
                $results | Should Match "$login2|$dbname2"
                $results | Should Not Match "$login1|$dbname1"
            }
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
            $file = Export-DbaLogin -SqlInstance $TestConfig.instance2 -ExcludeDatabase -WarningAction SilentlyContinue
            $results = $file.DirectoryName
            $allfiles += $file.FullName
            $results | Should Be $DefaultExportPath
        }
        It "Should export file to custom folder path" {
            $file = Export-DbaLogin -SqlInstance $TestConfig.instance2 -Path $AltExportPath -ExcludeDatabase -WarningAction SilentlyContinue
            $results = $file.DirectoryName
            $allfiles += $file.FullName
            $results | Should Be $AltExportPath
        }
        It "Should export file to custom file path" {
            $file = Export-DbaLogin -SqlInstance $TestConfig.instance2 -FilePath "$AltExportPath\Dbatoolsci_login_CustomFile.sql" -ExcludeDatabase -WarningAction SilentlyContinue
            $results = $file.Name
            $allfiles += $file.FullName
            $results | Should Be "Dbatoolsci_login_CustomFile.sql"
        }
        It "Should export file to custom file path and Append" {
            $file = Export-DbaLogin -SqlInstance $TestConfig.instance2 -FilePath "$AltExportPath\Dbatoolsci_login_CustomFile.sql" -Append -ExcludeDatabase -WarningAction SilentlyContinue
            $allfiles += $file.FullName
            $file.CreationTimeUtc.Ticks | Should BeLessThan $file.LastWriteTimeUtc.Ticks
        }
        It "Should not export file to custom file path with NoClobber" {
            { Export-DbaLogin -SqlInstance $TestConfig.instance2 -FilePath "$AltExportPath\Dbatoolsci_login_CustomFile.sql" -NoClobber -WarningAction SilentlyContinue } | Should Throw
        }
    }
}
