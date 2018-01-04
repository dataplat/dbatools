$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 5
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Find-DbaBackup).Parameters.Keys
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    $testPath = "TestDrive:\sqlbackups"
    if (!(Test-Path $testPath)) {
        New-Item -Path $testPath -ItemType Container
    }
    Context "Path validation" {
        { Find-DbaBackup -Path 'funnypath' -BackupFileExtension 'bak' -RetentionPeriod '0d' -EnableException } | Should Throw "not found"
    }
    Context "RetentionPeriod validation" {
        { Find-DbaBackup -Path $testPath -BackupFileExtension 'bak' -RetentionPeriod 'ad' -EnableException } | Should Throw "format invalid"
        { Find-DbaBackup -Path $testPath -BackupFileExtension 'bak' -RetentionPeriod '11y' -EnableException } | Should Throw "units invalid"
    }
    Context "BackupFileExtension validation" {
        { Find-DbaBackup -Path $testPath -BackupFileExtension '.bak' -RetentionPeriod '0d' -EnableException } | Should Not Throw
    }
    Context "BackupFileExtension message validation" {
        $warnmessage = Find-DbaBackup -Path $testPath -BackupFileExtension '.bak' -RetentionPeriod '0d' 3>&1
        $warnmessage | Should BeLike '*period*'
    }
    Context "Files found match the proper retention" {
        for ($i = 1; $i -le 5; $i++) {
            $filepath = Join-Path $testPath "dbatoolsci_$($i)_backup_hours.bak"
            Set-Content $filepath -value "."
            (Get-ChildItem $filepath).LastWriteTime = (Get-Date).AddHours(-10)
        }
        for ($i = 1; $i -le 5; $i++) {
            $filepath = Join-Path $testPath "dbatoolsci_$($i)_backup_days.bak"
            Set-Content $filepath -value "."
            (Get-ChildItem $filepath).LastWriteTime = (Get-Date).AddDays(-5)
        }
        for ($i = 1; $i -le 5; $i++) {
            $filepath = Join-Path $testPath "dbatoolsci_$($i)_backup_weeks.bak"
            Set-Content $filepath -value "."
            (Get-ChildItem $filepath).LastWriteTime = (Get-Date).AddDays(-5 * 7)
        }
        for ($i = 1; $i -le 5; $i++) {
            $filepath = Join-Path $testPath "dbatoolsci_$($i)_backup_months.bak"
            Set-Content $filepath -value "."
            (Get-ChildItem $filepath).LastWriteTime = (Get-Date).AddDays(-5 * 30)
        }
        It "Should find all files with retention 0d" {
            $results = Find-DbaBackup -Path $testPath -BackupFileExtension 'bak' -RetentionPeriod '0d'
            $results.Length | Should Be 20
        }
        It "Should find no files '*hours*' with retention 11h" {
            $results = Find-DbaBackup -Path $testPath -BackupFileExtension 'bak' -RetentionPeriod '11h'
            $results.Length | Should Be 15
            ($results | Where-Object FullName -Like '*hours*').Count | Should Be 0
        }
        It "Should find no files '*days*' with retention 6d" {
            $results = Find-DbaBackup -Path $testPath -BackupFileExtension 'bak' -RetentionPeriod '6d'
            $results.Length | Should Be 10
            ($results | Where-Object FullName -Like '*hours*').Count | Should Be 0
            ($results | Where-Object FullName -Like '*days*').Count | Should Be 0
        }
        It "Should find no files '*weeks*' with retention 6w" {
            $results = Find-DbaBackup -Path $testPath -BackupFileExtension 'bak' -RetentionPeriod '6w'
            $results.Length | Should Be 5
            ($results | Where-Object FullName -Like '*hours*').Count | Should Be 0
            ($results | Where-Object FullName -Like '*days*').Count | Should Be 0
            ($results | Where-Object FullName -Like '*weeks*').Count | Should Be 0
        }
        It "Should find no files '*months*' with retention 6m" {
            $results = Find-DbaBackup -Path $testPath -BackupFileExtension 'bak' -RetentionPeriod '6m'
            $results.Length | Should Be 0
            ($results | Where-Object FullName -Like '*hours*').Count | Should Be 0
            ($results | Where-Object FullName -Like '*days*').Count | Should Be 0
            ($results | Where-Object FullName -Like '*weeks*').Count | Should Be 0
            ($results | Where-Object FullName -Like '*weeks*').Count | Should Be 0
        }
    }
    Context "Files found match the proper archive bit" {
        for ($i = 1; $i -le 5; $i++) {
            $filepath = Join-Path $testPath "dbatoolsci_$($i)_backup_notarchive.bak"
            Set-Content $filepath -value "."
            (Get-ChildItem $filepath).LastWriteTime = (Get-Date).AddDays(-5)
            (Get-ChildItem $filepath).Attributes = "Normal"
        }
        for ($i = 1; $i -le 5; $i++) {
            $filepath = Join-Path $testPath "dbatoolsci_$($i)_backup_archive.bak"
            Set-Content $filepath -value "."
            (Get-ChildItem $filepath).LastWriteTime = (Get-Date).AddDays(-5)
            (Get-ChildItem $filepath).Attributes = "Archive"
        }
        It "Should find all files with retention 0d" {
            $results = Find-DbaBackup -Path $testPath -BackupFileExtension 'bak' -RetentionPeriod '0d'
            $results.Length | Should Be 10
        }
        It "Should find only files with the archive bit not set" {
            $results = Find-DbaBackup -Path $testPath -BackupFileExtension 'bak' -RetentionPeriod '0d' -CheckArchiveBit
            $results.Length | Should Be 5
            ($results | Where-Object FullName -Like '*_notarchive*').Count | Should Be 5
            ($results | Where-Object FullName -Like '*_archive*').Count | Should Be 0
        }
    }
    Context "Files found match the proper extension" {
        for ($i = 1; $i -le 5; $i++) {
            $filepath = Join-Path $testPath "dbatoolsci_$($i)_backup.trn"
            Set-Content $filepath -value "."
            (Get-ChildItem $filepath).LastWriteTime = (Get-Date).AddDays(-5)
        }
        for ($i = 1; $i -le 5; $i++) {
            $filepath = Join-Path $testPath "dbatoolsci_$($i)_backup.bak"
            Set-Content $filepath -value "."
            (Get-ChildItem $filepath).LastWriteTime = (Get-Date).AddDays(-5)
        }
        It "Should find 5 files with extension trn" {
            $results = Find-DbaBackup -Path $testPath -BackupFileExtension 'trn' -RetentionPeriod '0d'
            $results.Length | Should Be 5
        }
        It "Should find 5 files with extension bak" {
            $results = Find-DbaBackup -Path $testPath -BackupFileExtension 'bak' -RetentionPeriod '0d'
            $results.Length | Should Be 5
        }
    }
}
