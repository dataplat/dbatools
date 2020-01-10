$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'User', 'DestinationVersion', 'Path', 'FilePath', 'InputObject', 'NoClobber', 'Append', 'EnableException', 'ScriptingOptionsObject', 'ExcludeGoBatchSeparator', 'Passthru'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $AltExportPath = "$env:USERPROFILE\Documents"
        $outputFile = "$AltExportPath\Dbatoolsci_user_CustomFile.sql"
        try {
            $dbname = "dbatoolsci_exportdbauser"
            $login = "dbatoolsci_exportdbauser_login"
            $user = "dbatoolsci_exportdbauser_user"
            $server = Connect-DbaInstance -SqlInstance $script:instance1
            $null = $server.Query("CREATE DATABASE [$dbname]")

            $securePassword = $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force)
            $null = New-DbaLogin -SqlInstance $script:instance1 -Login $login -Password $securePassword

            $db = Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbname
            $null = $db.Query("CREATE USER [$user] FOR LOGIN [$login]")
        } catch { } # No idea why appveyor can't handle this
    }
    AfterAll {
        Remove-DbaDatabase -SqlInstance $script:instance1 -Database $dbname -Confirm:$false
        Remove-DbaLogin -SqlInstance $script:instance1 -Login $login -Confirm:$false
        (Get-ChildItem $outputFile -ErrorAction SilentlyContinue) | Remove-Item -ErrorAction SilentlyContinue
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
            $file = Export-DbaUser -SqlInstance $script:instance1 -Database $dbname -ScriptingOptionsObject $scriptingOptions -WarningAction SilentlyContinue
            $results = Get-Content -Path $file -Raw
            $allfiles += $file.FullName
            $results | Should Not BeLike ('*USE `[' + $dbname + '`]*')
        }
        It 'Includes database context' {
            $scriptingOptions = New-DbaScriptingOption
            $scriptingOptions.IncludeDatabaseContext = $true
            $file = Export-DbaUser -SqlInstance $script:instance1 -Database $dbname -ScriptingOptionsObject $scriptingOptions -WarningAction SilentlyContinue
            $results = Get-Content -Path $file -Raw
            $allfiles += $file.FullName
            $results | Should BeLike ('*USE `[' + $dbname + '`]*')
        }
        It 'Defaults to include database context' {
            $file = Export-DbaUser -SqlInstance $script:instance1 -Database $dbname -WarningAction SilentlyContinue
            $results = Get-Content -Path $file -Raw
            $allfiles += $file.FullName
            $results | Should BeLike ('*USE `[' + $dbname + '`]*')
        }
    }
}