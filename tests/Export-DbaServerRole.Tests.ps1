$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'InputObject', 'ScriptingOptionsObject', 'ServerRole', 'ExcludeServerRole', 'ExcludeFixedRole', 'IncludeRoleMember', 'Path', 'FilePath', 'Passthru', 'BatchSeparator', 'NoClobber', 'Append', 'NoPrefix', 'Encoding', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $AltExportPath = "$env:USERPROFILE\Documents"
        $outputFile = "$AltExportPath\Dbatoolsci_ServerRole.sql"
        try {
            $random = Get-Random
            $login1 = "dbatoolsci_exportdbaserverrole_login1$random"
            $svRole = "dbatoolsci_ScriptPermissions$random"

            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $null = $server.Query("CREATE LOGIN [$login1] WITH PASSWORD = 'GoodPass1234!'")
            $null = $server.Query("CREATE SERVER ROLE [$svRole] AUTHORIZATION [$login1]")
            $null = $server.Query("ALTER SERVER ROLE [dbcreator] ADD MEMBER [$svRole]")
            $null = $server.Query("GRANT CREATE TRACE EVENT NOTIFICATION TO [$svRole]")
            $null = $server.Query("DENY SELECT ALL USER SECURABLES TO [$svRole]")
            $null = $server.Query("GRANT VIEW ANY DEFINITION TO [$svRole]")
            $null = $server.Query("GRANT VIEW ANY DATABASE TO [$svRole]")
        } catch {}
    }
    AfterAll {
        try {
            Remove-DbaServerRole -SqlInstance $TestConfig.instance2 -ServerRole $svRole -Confirm:$false
            Remove-DbaLogin -SqlInstance $TestConfig.instance2 -Login $login1 -Confirm:$false

        } catch { }
        (Get-ChildItem $outputFile -ErrorAction SilentlyContinue) | Remove-Item -ErrorAction SilentlyContinue
    }

    Context "Check if output file was created" {

        $null = Export-DbaServerRole -SqlInstance $TestConfig.instance2 -FilePath $outputFile
        It "Exports results to one sql file" {
            (Get-ChildItem $outputFile).Count | Should Be 1
        }
        It "Exported file is bigger than 0" {
            (Get-ChildItem $outputFile).Length | Should BeGreaterThan 0
        }
    }

    Context "Check using piped input created" {
        $role = Get-DbaServerRole -SqlInstance $TestConfig.instance2 -ServerRole $svRole
        $null = $role | Export-DbaServerRole -FilePath $outputFile
        It "Exports results to one sql file" {
            (Get-ChildItem $outputFile).Count | Should Be 1
        }
        It "Exported file is bigger than 0" {
            (Get-ChildItem $outputFile).Length | Should BeGreaterThan 0
        }

        $TestConfig.results = $role | Export-DbaServerRole -Passthru
        It "should include the defined BatchSeparator" {
            $TestConfig.results -match "GO"
        }
        It "should include the role" {
            $TestConfig.results -match "CREATE SERVER ROLE [$svRole]"
        }
        It "should include ADD MEMBER" {
            $TestConfig.results -match "ALTER SERVER ROLE [dbcreator] ADD MEMBER [$svRole]"
        }
        It "should include GRANT CREATE TRACE EVENT" {
            $TestConfig.results -match "GRANT CREATE TRACE EVENT NOTIFICATION TO [$svRole]"
        }
        It "should include DENY SELECT ALL USER SECURABLES" {
            $TestConfig.results -match "DENY SELECT ALL USER SECURABLES TO [$svRole]"
        }
        It "should include VIEW ANY DEFINITION" {
            $TestConfig.results -match "GRANT VIEW ANY DEFINITION TO [$svRole];"
        }
        It "should include GRANT VIEW ANY DATABASE" {
            $TestConfig.results -match "GRANT VIEW ANY DATABASE TO [$svRole];"
        }
    }
}
