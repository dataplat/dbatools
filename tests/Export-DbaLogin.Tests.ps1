$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'InputObject', 'Login', 'ExcludeLogin', 'Database', 'ExcludeJobs', 'ExcludeDatabase', 'ExcludePassword', 'DefaultDatabase', 'Path', 'FilePath', 'Encoding', 'NoClobber', 'Append', 'BatchSeparator', 'DestinationVersion', 'NoPrefix', 'Passthru', 'EnableException'
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
        try {
            $random = Get-Random
            $dbname1 = "dbatoolsci_exportdbalogin1$random"
            $login1 = "dbatoolsci_exportdbalogin_login1$random"
            $user1 = "dbatoolsci_exportdbalogin_user1$random"

            $dbname2 = "dbatoolsci_exportdbalogin2$random"
            $login2 = "dbatoolsci_exportdbalogin_login2$random"
            $user2 = "dbatoolsci_exportdbalogin_user2$random"

            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $null = $server.Query("CREATE DATABASE [$dbname1]")
            $null = $server.Query("CREATE LOGIN [$login1] WITH PASSWORD = 'GoodPass1234!'")
            $server.Databases[$dbname1].ExecuteNonQuery("CREATE USER [$user1] FOR LOGIN [$login1]")

            $null = $server.Query("CREATE DATABASE [$dbname2]")
            $null = $server.Query("CREATE LOGIN [$login2] WITH PASSWORD = 'GoodPass1234!'")
            $null = $server.Query("ALTER LOGIN [$login2] DISABLE")
            $null = $server.Query("DENY CONNECT SQL TO [$login2]")

            if ($server.VersionMajor -lt 11) {
                $null = $server.Query("EXEC sys.sp_addsrvrolemember @rolename=N'dbcreator', @loginame=N'$login2'")
            } else {
                $null = $server.Query("ALTER SERVER ROLE [dbcreator] ADD MEMBER [$login2]")
            }
            $null = $server.Query("GRANT SELECT ON sys.databases TO [$login2] WITH GRANT OPTION")
            $server.Databases[$dbname2].ExecuteNonQuery("CREATE USER [$user2] FOR LOGIN [$login2]")
        } catch {
            $_
        }
    }
    AfterAll {
        try {
            Remove-DbaDatabase -SqlInstance $script:instance2 -Database $dbname1 -Confirm:$false
            Remove-DbaLogin -SqlInstance $script:instance2 -Login $login1 -Confirm:$false

            Remove-DbaDatabase -SqlInstance $script:instance2 -Database $dbname2 -Confirm:$false
            Remove-DbaLogin -SqlInstance $script:instance2 -Login $login2 -Confirm:$false
        } catch { }
        $timenow = (Get-Date -uformat "%m%d%Y%H")
        $ExportedCredential = Get-ChildItem $DefaultExportPath, $AltExportPath | Where-Object { $_.Name -match "$timenow\d{4}-login.sql|Dbatoolsci_login_CustomFile.sql" }
        $null = Remove-Item -Path $($ExportedCredential.FullName) -ErrorAction SilentlyContinue
    }

    Context "Executes with Exclude Parameters" {
        It "Should exclude databases when exporting" {
            $file = Export-DbaLogin -SqlInstance $script:instance2 -ExcludeDatabase -WarningAction SilentlyContinue
            $results = Get-Content -Path $file -Raw
            $allfiles += $file.FullName
            $results | Should Match '\nGo\r'
        }
        It "Should exclude Jobs when exporting" {
            $file = Export-DbaLogin -SqlInstance $script:instance2 -ExcludeJobs -WarningAction SilentlyContinue
            $results = Get-Content -Path $file -Raw
            $allfiles += $file.FullName
            $results | Should Not Match 'Job'
        }
        It "Should exclude Go when exporting" {
            $file = Export-DbaLogin -SqlInstance $script:instance2 -ExcludeDatabase -BatchSeparator '' -WarningAction SilentlyContinue
            $results = Get-Content -Path $file -Raw
            $allfiles += $file.FullName
            $results | Should Not Match 'Go'
        }
        It "Should exclude a specific login" {
            $file = Export-DbaLogin -SqlInstance $script:instance2 -ExcludeLogin $login1 -WarningAction SilentlyContinue
            $results = Get-Content -Path $file -Raw
            $allfiles += $file.FullName
            $results | Should Not Match "$login1"
        }
        It "Should exclude passwords" {
            $file = Export-DbaLogin -SqlInstance $script:instance2 -ExcludeLogin $login1 -WarningAction SilentlyContinue -ExcludePassword
            $results = Get-Content -Path $file -Raw
            $allfiles += $file.FullName
            $results | Should Not Match '(?<=PASSWORD =\s0x)(\w+)'
        }
    }
    Context "Executes for various users, databases, and environments" {
        It "Should Export a specific user" {
            $file = Export-DbaLogin -SqlInstance $script:instance2 -Login $login1 -Database $dbname1 -DefaultDatabase master -WarningAction SilentlyContinue
            $results = Get-Content -Path $file -Raw
            $allfiles += $file.FullName
            $results | Should Not Match "$login2|$dbname2"
            $results | Should Match "$login1|$dbname1"
        }
        foreach ($version in $((Get-Command $CommandName).Parameters.DestinationVersion.attributes.validvalues)) {
            It "Should Export for the SQLVersion $version" {
                $file = Export-DbaLogin -SqlInstance $script:instance2 -Login $login2 -Database $dbname2 -DestinationVersion $version -WarningAction SilentlyContinue
                $results = Get-Content -Path $file -Raw
                $allfiles += $file.FullName
                $results | Should Match "$login2|$dbname2"
                $results | Should Not Match "$login1|$dbname1"
            }
        }
    }
    Context "Exports file to random and specified paths" {
        It "Should export file to the configured path" {
            $file = Export-DbaLogin -SqlInstance $script:instance2 -ExcludeDatabase -WarningAction SilentlyContinue
            $results = $file.DirectoryName
            $allfiles += $file.FullName
            $results | Should Be $DefaultExportPath
        }
        It "Should export file to custom folder path" {
            $file = Export-DbaLogin -SqlInstance $script:instance2 -Path $AltExportPath -ExcludeDatabase -WarningAction SilentlyContinue
            $results = $file.DirectoryName
            $allfiles += $file.FullName
            $results | Should Be $AltExportPath
        }
        It "Should export file to custom file path" {
            $file = Export-DbaLogin -SqlInstance $script:instance2 -FilePath "$AltExportPath\Dbatoolsci_login_CustomFile.sql" -ExcludeDatabase -WarningAction SilentlyContinue
            $results = $file.Name
            $allfiles += $file.FullName
            $results | Should Be "Dbatoolsci_login_CustomFile.sql"
        }
        It "Should export file to custom file path and Append" {
            $file = Export-DbaLogin -SqlInstance $script:instance2 -FilePath "$AltExportPath\Dbatoolsci_login_CustomFile.sql" -Append -ExcludeDatabase -WarningAction SilentlyContinue
            $allfiles += $file.FullName
            $file.CreationTimeUtc.Ticks | Should BeLessThan $file.LastWriteTimeUtc.Ticks
        }
        It "Should not export file to custom file path with NoClobber" {
            { Export-DbaLogin -SqlInstance $script:instance2 -FilePath "$AltExportPath\Dbatoolsci_login_CustomFile.sql" -NoClobber -WarningAction SilentlyContinue } | Should Throw
        }
    }
}