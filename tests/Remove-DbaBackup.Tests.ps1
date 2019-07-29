$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"


Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'Path', 'BackupFileExtension', 'RetentionPeriod', 'CheckArchiveBit', 'RemoveEmptyBackupFolder', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
    Context "It's Confirm impact should be medium" {
        $command = Get-Command Remove-DbaBackup
        $metadata = [System.Management.Automation.CommandMetadata]$command
        $metadata.ConfirmImpact | Should Be 'Medium'
    }
}


Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    $testPath = "TestDrive:\sqlbackups"
    if (!(Test-Path $testPath)) {
        New-Item -Path $testPath -ItemType Container
    }
    Context "Path validation" {
        { Remove-DbaBackup -Path 'funnypath' -BackupFileExtension 'bak' -RetentionPeriod '0d' -EnableException } | Should Throw "not found"
    }
    Context "RetentionPeriod validation" {
        { Remove-DbaBackup -Path $testPath -BackupFileExtension 'bak' -RetentionPeriod 'ad' -EnableException } | Should Throw "format invalid"
        { Remove-DbaBackup -Path $testPath -BackupFileExtension 'bak' -RetentionPeriod '11y' -EnableException } | Should Throw "units invalid"
    }
    Context "BackupFileExtension validation" {
        { Remove-DbaBackup -Path $testPath -BackupFileExtension '.bak' -RetentionPeriod '0d' -EnableException -WarningAction SilentlyContinue } | Should Not Throw
    }
    Context "BackupFileExtension message validation" {
        Remove-DbaBackup -Path $testPath -BackupFileExtension '.bak' -RetentionPeriod '0d' -WarningAction SilentlyContinue -WarningVariable warnmessage
        $warnmessage | Should -Match period
    }
    Context "Files are removed" {
        for ($i = 1; $i -le 5; $i++) {
            $filepath = Join-Path $testPath "dbatoolsci_$($i)_backup.bak"
            Set-Content $filepath -value "."
            (Get-ChildItem $filepath).LastWriteTime = (Get-Date).AddDays(-5)
        }
        It "Should remove all files with retention 0d" {
            $null = Remove-DbaBackup -Path $testPath -BackupFileExtension 'bak' -RetentionPeriod '0d'
            (Get-ChildItem -Path $testPath -File -Recurse).Count | Should Be 0
        }
    }
    Context "Files with matching extensions only are removed" {
        for ($i = 1; $i -le 5; $i++) {
            $filepath = Join-Path $testPath "dbatoolsci_$($i)_backup.bak"
            Set-Content $filepath -value "."
            (Get-ChildItem $filepath).LastWriteTime = (Get-Date).AddDays(-5)
        }
        for ($i = 1; $i -le 5; $i++) {
            $filepath = Join-Path $testPath "dbatoolsci_$($i)_backup.trn"
            Set-Content $filepath -value "."
            (Get-ChildItem $filepath).LastWriteTime = (Get-Date).AddDays(-5)
        }
        It "Should remove all files but not the trn ones" {
            $null = Remove-DbaBackup -Path $testPath -BackupFileExtension 'bak' -RetentionPeriod '0d'
            (Get-ChildItem -Path $testPath -File -Recurse).Count | Should Be 5
            (Get-ChildItem -Path $testPath -File -Recurse).Name | Should BeLike '*trn'
        }
    }
    Context "Cleanup empty folders" {
        $testPathinner_empty = "TestDrive:\sqlbackups\empty"
        if (!(Test-Path $testPathinner_empty)) {
            New-Item -Path $testPathinner_empty -ItemType Container
        }
        $testPathinner = "TestDrive:\sqlbackups\inner"
        if (!(Test-Path $testPathinner)) {
            New-Item -Path $testPathinner -ItemType Container
        }
        for ($i = 1; $i -le 5; $i++) {
            $filepath = Join-Path $testPath "dbatoolsci_$($i)_backup.bak"
            Set-Content $filepath -value "."
            (Get-ChildItem $filepath).LastWriteTime = (Get-Date).AddDays(-5)
        }
        for ($i = 1; $i -le 5; $i++) {
            $filepath = Join-Path $testPathinner "dbatoolsci_$($i)_backup.bak"
            Set-Content $filepath -value "."
            (Get-ChildItem $filepath).LastWriteTime = (Get-Date).AddDays(-5)
        }
        It "Removes files but leaves empty dirs" {
            Remove-DbaBackup -Path $testPath -BackupFileExtension 'bak' -RetentionPeriod '0d'
            (Get-ChildItem -Path $testPath -Directory -Recurse).Count | Should Be 2
        }
        It "Removes files and removes empty dirs" {
            Remove-DbaBackup -Path $testPath -BackupFileExtension 'bak' -RetentionPeriod '0d' -RemoveEmptyBackupFolder
            (Get-ChildItem -Path $testPath -Directory -Recurse).Count | Should Be 0
        }
    }
}