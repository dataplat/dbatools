$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'User', 'DestinationVersion', 'Encoding', 'Path', 'FilePath', 'InputObject', 'NoClobber', 'Append', 'EnableException', 'ScriptingOptionsObject', 'ExcludeGoBatchSeparator', 'Passthru', 'Template'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $AltExportPath = "$env:USERPROFILE\Documents"
        $outputPath = "$AltExportPath\Dbatoolsci_user_CustomFolder"
        $outputFile = "$AltExportPath\Dbatoolsci_user_CustomFile.sql"
        $outputFile2 = "$AltExportPath\Dbatoolsci_user_CustomFile2.sql"
        try {
            $dbname = "dbatoolsci_exportdbauser"
            $login = "dbatoolsci_exportdbauser_login"
            $login2 = "dbatoolsci_exportdbauser_login2"
            $user = "dbatoolsci_exportdbauser_user"
            $user2 = "dbatoolsci_exportdbauser_user2"
            $table = "dbatoolsci_exportdbauser_table"
            $role = "dbatoolsci_exportdbauser_role"
            $server = Connect-DbaInstance -SqlInstance $script:instance1
            $null = $server.Query("CREATE DATABASE [$dbname]")

            $securePassword = $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force)
            $null = New-DbaLogin -SqlInstance $script:instance1 -Login $login -Password $securePassword
            $null = New-DbaLogin -SqlInstance $script:instance1 -Login $login2 -Password $securePassword

            $db = Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbname
            $null = $db.Query("CREATE USER [$user] FOR LOGIN [$login]")
            $null = $db.Query("CREATE USER [$user2] FOR LOGIN [$login2]")
            $null = $db.Query("CREATE ROLE [$role]")

            $null = $db.Query("CREATE TABLE $table (C1 INT);")
            $null = $db.Query("GRANT SELECT ON OBJECT::$table TO [$user];")
            $null = $db.Query("EXEC sp_addrolemember '$role', '$user';")
            $null = $db.Query("GRANT SELECT ON OBJECT::$table TO [$user2];")
        } catch { } # No idea why appveyor can't handle this
    }
    AfterAll {
        Remove-DbaDatabase -SqlInstance $script:instance1 -Database $dbname -Confirm:$false
        Remove-DbaLogin -SqlInstance $script:instance1 -Login $login -Confirm:$false
        Remove-DbaLogin -SqlInstance $script:instance1 -Login $login2 -Confirm:$false
        (Get-ChildItem $outputFile -ErrorAction SilentlyContinue) | Remove-Item -ErrorAction SilentlyContinue
        (Get-ChildItem $outputFile2 -ErrorAction SilentlyContinue) | Remove-Item -ErrorAction SilentlyContinue
        Remove-Item -Path $outputPath -Recurse -ErrorAction SilentlyContinue -Confirm:$false
    }

    Context "Check if output file was created" {
        if (Get-DbaDbUser -SqlInstance $script:instance1 -Database $dbname | Where-Object Name -eq $user) {
            $null = Export-DbaUser -SqlInstance $script:instance1 -Database $dbname -User $user -FilePath $outputFile
            It "Exports results to one sql file" {
                (Get-ChildItem $outputFile).Count | Should Be 1
            }
            It "Exported file is bigger than 0" {
                (Get-ChildItem $outputFile).Length | Should BeGreaterThan 0
            }
        }
    }

    Context "Respects options specified in the ScriptingOptionsObject parameter" {
        It 'Excludes database context' {
            $scriptingOptions = New-DbaScriptingOption
            $scriptingOptions.IncludeDatabaseContext = $false
            $null = Export-DbaUser -SqlInstance $script:instance1 -Database $dbname -ScriptingOptionsObject $scriptingOptions -FilePath $outputFile2 -WarningAction SilentlyContinue
            $results = Get-Content -Path $outputFile2 -Raw
            $results | Should Not BeLike ('*USE `[' + $dbname + '`]*')
            (Get-ChildItem $outputFile2 -ErrorAction SilentlyContinue) | Remove-Item -ErrorAction SilentlyContinue
        }
        It 'Includes database context' {
            $scriptingOptions = New-DbaScriptingOption
            $scriptingOptions.IncludeDatabaseContext = $true
            $null = Export-DbaUser -SqlInstance $script:instance1 -Database $dbname -ScriptingOptionsObject $scriptingOptions -FilePath $outputFile2 -WarningAction SilentlyContinue
            $results = Get-Content -Path $outputFile2 -Raw
            $results | Should BeLike ('*USE `[' + $dbname + '`]*')
            (Get-ChildItem $outputFile2 -ErrorAction SilentlyContinue) | Remove-Item -ErrorAction SilentlyContinue
        }
        It 'Defaults to include database context' {
            $null = Export-DbaUser -SqlInstance $script:instance1 -Database $dbname -FilePath $outputFile2 -WarningAction SilentlyContinue
            $results = Get-Content -Path $outputFile2 -Raw
            $results | Should BeLike ('*USE `[' + $dbname + '`]*')
            (Get-ChildItem $outputFile2 -ErrorAction SilentlyContinue) | Remove-Item -ErrorAction SilentlyContinue
        }
        It 'Exports as template' {
            $results = Export-DbaUser -SqlInstance $script:instance1 -Database $dbname -User $user -Template -DestinationVersion SQLServer2016 -WarningAction SilentlyContinue -Passthru
            $results | Should BeLike "*CREATE USER ``[{templateUser}``] FOR LOGIN ``[{templateLogin}``]*"
            $results | Should BeLike "*GRANT SELECT ON OBJECT::``[dbo``].``[$table``] TO ``[{templateUser}``]*"
            $results | Should BeLike "*ALTER ROLE ``[$role``] ADD MEMBER ``[{templateUser}``]*"
        }
    }

    Context "Check if one output file per user was created" {
        $null = Export-DbaUser -SqlInstance $script:instance1 -Database $dbname -Path $outputPath
        It "Exports two files to the path" {
            (Get-ChildItem $outputPath).Count | Should Be 2
        }
        It "Exported file name contains username '$user'" {
            Get-ChildItem $outputPath | Where-Object Name -like ('*' + $User + '*') | Should BeTrue
        }
        It "Exported file name contains username '$user2'" {
            Get-ChildItem $outputPath | Where-Object Name -like ('*' + $User2 + '*') | Should BeTrue
        }
    }
}