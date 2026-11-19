#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Format-DbaBackupInformation",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: multi-instance-failure N/A -- the command has no SqlInstance or other multi-target parameter; it rewrites the backup history objects it is given.
# NativeChecklist: whatif-confirm N/A -- the pinned function declares no SupportsShouldProcess and changes nothing outside the objects it returns.
# NativeChecklist: enable-exception N/A -- the pinned function has no Stop-Function or other failure path; -EnableException changes nothing it does.
# NativeChecklist: azure-sqldb N/A -- the command never connects to SQL Server; it prepares backup history (database names, data and log file placement, backup paths) for RESTORE, and Azure SQL Database supports neither backup/restore syntax nor file placement syntax (https://learn.microsoft.com/azure/azure-sql/database/transact-sql-tsql-differences-sql-server, items 8 and 9).
# NativeChecklist: sql-login N/A -- the pinned command has no SqlCredential parameter and no SQL connection.

Describe "Native Format-DbaBackupInformation" -Tag UnitTests {
    BeforeAll {
        $fmtRawInput = Join-Path (Split-Path $PSScriptRoot -Parent) "ObjectDefinitions\BackupRestore\RawInput"

        function New-FmtFile {
            param([string]$LogicalName, [string]$PhysicalName, [string]$Type)
            [PSCustomObject]@{
                LogicalName  = $LogicalName
                PhysicalName = $PhysicalName
                Type         = $Type
            }
        }

        function New-FmtHistory {
            param([string]$Database, [string]$Type = "Full", [string[]]$FullName, [object[]]$FileList)
            $fmtHistory = New-Object Dataplat.Dbatools.Database.BackupHistory
            $fmtHistory.Database = $Database
            $fmtHistory.Type = $Type
            $fmtHistory.FullName = $FullName
            $fmtHistory.FileList = $FileList
            $fmtHistory
        }
    }

    It "joins a URL restore directory with '/' and trims its trailing slashes, whatever the scheme case" {
        $fmtHistory = [PSCustomObject]@{
            Database = "UrlDb"
            Type     = "Full"
            FullName = @("s3://bucket/backups/UrlDb.bak")
            FileList = @(
                (New-FmtFile -LogicalName "UrlDb" -PhysicalName "C:\data\UrlDb.mdf" -Type "D"),
                (New-FmtFile -LogicalName "UrlDb_log" -PhysicalName "C:\log\UrlDb_log.ldf" -Type "L")
            )
        }
        $fmtResult = Format-DbaBackupInformation -BackupHistory $fmtHistory -DataFileDirectory "S3://bucket/restore//" -DatabaseFilePrefix "p_" -DatabaseFileSuffix "_s"
        $fmtResult.FileList[0].PhysicalName | Should -BeExactly "S3://bucket/restore/p_UrlDb_s.mdf"
        $fmtResult.FileList[1].PhysicalName | Should -BeExactly "S3://bucket/restore/p_UrlDb_log_s.ldf"
    }

    It "keeps PathSep for local and Linux restore directories" {
        $fmtWindows = [PSCustomObject]@{
            Database = "LocalDb"
            Type     = "Full"
            FullName = @("C:\backups\LocalDb.bak")
            FileList = @(New-FmtFile -LogicalName "LocalDb" -PhysicalName "C:\data\LocalDb.mdf" -Type "D")
        }
        $fmtLinux = [PSCustomObject]@{
            Database = "LinuxDb"
            Type     = "Full"
            FullName = @("/var/opt/mssql/backup/LinuxDb.bak")
            FileList = @(New-FmtFile -LogicalName "LinuxDb" -PhysicalName "/var/opt/mssql/data/LinuxDb.mdf" -Type "D")
        }
        (Format-DbaBackupInformation -BackupHistory $fmtWindows -DatabaseFileSuffix "_w").FileList[0].PhysicalName | Should -BeExactly "C:\data\LocalDb_w.mdf"
        (Format-DbaBackupInformation -BackupHistory $fmtLinux -PathSep "/" -DataFileDirectory "/restore/").FileList[0].PhysicalName | Should -BeExactly "/restore/LinuxDb.mdf"
    }

    It "maps the backup type, renames with a prefix and adds the original-value properties to a BackupHistory object" {
        $fmtHistory = New-FmtHistory -Database "TypeDb" -Type "Differential" -FullName @("C:\b\TypeDb.dif") -FileList @(New-FmtFile -LogicalName "TypeDb" -PhysicalName "C:\d\TypeDb.mdf" -Type "D")
        $fmtResult = Format-DbaBackupInformation -BackupHistory $fmtHistory -ReplaceDatabaseName "NewTypeDb" -DatabaseNamePrefix "pre_"
        $fmtResult | Should -BeOfType [Dataplat.Dbatools.Database.BackupHistory]
        $fmtResult.Type | Should -BeExactly "Database Differential"
        $fmtResult.Database | Should -BeExactly "pre_NewTypeDb"
        $fmtResult.OriginalDatabase | Should -BeExactly "TypeDb"
        $fmtResult.IsVerified | Should -BeFalse
        $fmtResult.FileList[0].PhysicalName | Should -BeExactly "C:\d\TypeDb.mdf"
        (Format-DbaBackupInformation -BackupHistory (New-FmtHistory -Database "LogDb" -Type "Log" -FullName @("C:\b\LogDb.trn") -FileList @())).Type | Should -BeExactly "Transaction Log"
        (Format-DbaBackupInformation -BackupHistory (New-FmtHistory -Database "FullDb" -Type "Full" -FullName @("C:\b\FullDb.bak") -FileList @())).Type | Should -BeExactly "Database"
    }

    It "keeps the first OriginalDatabase when an object is formatted twice" {
        $fmtHistory = New-FmtHistory -Database "TwiceDb" -FullName @("C:\b\TwiceDb.bak") -FileList @(New-FmtFile -LogicalName "TwiceDb" -PhysicalName "C:\d\TwiceDb.mdf" -Type "D")
        $fmtFirst = Format-DbaBackupInformation -BackupHistory $fmtHistory -ReplaceDatabaseName "TwiceDb2"
        $fmtSecond = Format-DbaBackupInformation -BackupHistory $fmtFirst -DatabaseNamePrefix "x_"
        $fmtSecond.Database | Should -BeExactly "x_TwiceDb2"
        $fmtSecond.OriginalDatabase | Should -BeExactly "TwiceDb"
    }

    It "renames every piped history object through a hashtable, in input order" -Tag NativeChecklist:pipeline-multiple {
        $fmtOne = New-FmtHistory -Database "PipeOne" -FullName @("C:\b\PipeOne.bak") -FileList @(New-FmtFile -LogicalName "PipeOne" -PhysicalName "C:\d\PipeOne.mdf" -Type "D")
        $fmtTwo = New-FmtHistory -Database "PipeTwo" -FullName @("C:\b\PipeTwo.bak") -FileList @(New-FmtFile -LogicalName "PipeTwo" -PhysicalName "C:\d\PipeTwo.mdf" -Type "D")
        $fmtThree = New-FmtHistory -Database "PipeThree" -FullName @("C:\b\PipeThree.bak") -FileList @(New-FmtFile -LogicalName "PipeThree" -PhysicalName "C:\d\PipeThree.mdf" -Type "D")
        $fmtResult = @($fmtOne, $fmtTwo, $fmtThree | Format-DbaBackupInformation -ReplaceDatabaseName @{ PipeOne = "First"; PipeTwo = "Second" } -ReplaceDbNameInFile)
        $fmtResult.Count | Should -Be 3
        ($fmtResult.Database -join "|") | Should -BeExactly "First|Second|PipeThree"
        ($fmtResult.FileList.PhysicalName -join "|") | Should -BeExactly "C:\d\First.mdf|C:\d\Second.mdf|C:\d\PipeThree.mdf"
    }

    It "keeps file names with an explicit -ReplaceDbNameInFile:`$false and renames them literally with -ReplaceDbNameInFile" -Tag NativeChecklist:switch-false {
        $fmtKept = New-FmtHistory -Database "Lit.Db" -FullName @("C:\b\Lit.Db.bak") -FileList @(New-FmtFile -LogicalName "Lit.Db" -PhysicalName "C:\d\LIT.DB_LitXDb.mdf" -Type "D")
        (Format-DbaBackupInformation -BackupHistory $fmtKept -ReplaceDatabaseName 'New$1Db' -ReplaceDbNameInFile:$false).FileList[0].PhysicalName | Should -BeExactly "C:\d\LIT.DB_LitXDb.mdf"
        $fmtRenamed = New-FmtHistory -Database "Lit.Db" -FullName @("C:\b\Lit.Db.bak") -FileList @(New-FmtFile -LogicalName "Lit.Db" -PhysicalName "C:\d\LIT.DB_LitXDb.mdf" -Type "D")
        (Format-DbaBackupInformation -BackupHistory $fmtRenamed -ReplaceDatabaseName 'New$1Db' -ReplaceDbNameInFile).FileList[0].PhysicalName | Should -BeExactly 'C:\d\New$1Db_LitXDb.mdf'
    }

    It "sends log and FileStream files to DataFileDirectory when their own directory is not given, and FileMapping overrides directories" {
        $fmtFiles = {
            @(
                (New-FmtFile -LogicalName "Dir" -PhysicalName "C:\d\Dir.mdf" -Type "D"),
                (New-FmtFile -LogicalName "Dir_log" -PhysicalName "C:\l\Dir_log.ldf" -Type "L"),
                (New-FmtFile -LogicalName "Dir_fs" -PhysicalName "C:\fs\Dir_fs" -Type "S")
            )
        }
        $fmtFallback = Format-DbaBackupInformation -BackupHistory (New-FmtHistory -Database "Dir" -FullName @("C:\b\Dir.bak") -FileList (& $fmtFiles)) -DataFileDirectory "E:\data\"
        ($fmtFallback.FileList.PhysicalName -join "|") | Should -BeExactly "E:\data\Dir.mdf|E:\data\Dir_log.ldf|E:\data\Dir_fs"
        $fmtOwn = Format-DbaBackupInformation -BackupHistory (New-FmtHistory -Database "Dir" -FullName @("C:\b\Dir.bak") -FileList (& $fmtFiles)) -DataFileDirectory "E:\data" -LogFileDirectory "F:\log\" -DestinationFileStreamDirectory "G:\fs\"
        ($fmtOwn.FileList.PhysicalName -join "|") | Should -BeExactly "E:\data\Dir.mdf|F:\log\Dir_log.ldf|G:\fs\Dir_fs"
        $fmtMapped = Format-DbaBackupInformation -BackupHistory (New-FmtHistory -Database "Dir" -FullName @("C:\b\Dir.bak") -FileList (& $fmtFiles)) -DataFileDirectory "E:\data" -FileMapping @{ Dir_log = "H:\mapped\Dir.ldf" }
        ($fmtMapped.FileList.PhysicalName -join "|") | Should -BeExactly "C:\d\Dir.mdf|H:\mapped\Dir.ldf|C:\fs\Dir_fs"
    }

    It "rebases every backup file onto RebaseBackupFolder and leaves http backups where they are" {
        $fmtLocal = New-FmtHistory -Database "Reb" -FullName @("C:\b\Reb_1.bak", "C:\b\Reb_2.bak") -FileList @()
        ((Format-DbaBackupInformation -BackupHistory $fmtLocal -RebaseBackupFolder "D:\moved\").FullName -join "|") | Should -BeExactly "D:\moved\Reb_1.bak|D:\moved\Reb_2.bak"
        $fmtUrl = New-FmtHistory -Database "Reb" -FullName @("https://account.blob.core.windows.net/b/Reb.bak") -FileList @()
        (Format-DbaBackupInformation -BackupHistory $fmtUrl -RebaseBackupFolder "D:\moved").FullName | Should -BeExactly "https://account.blob.core.windows.net/b/Reb.bak"
    }

    It "keeps the original backup paths in OriginalFullName after rebasing" {
        $fmtHistory = New-FmtHistory -Database "OrigName" -FullName @("C:\b\OrigName_1.bak", "C:\b\OrigName_2.bak") -FileList @()
        $fmtResult = Format-DbaBackupInformation -BackupHistory $fmtHistory -RebaseBackupFolder "D:\moved"
        ($fmtResult.FullName -join "|") | Should -BeExactly "D:\moved\OrigName_1.bak|D:\moved\OrigName_2.bak"
        ($fmtResult.OriginalFullName -join "|") | Should -BeExactly "C:\b\OrigName_1.bak|C:\b\OrigName_2.bak"

        $fmtImported = @(Get-DbaBackupInformation -Import -Path (Join-Path $fmtRawInput "RestoreTimeClean.xml"))
        $fmtImportedNames = @($fmtImported | ForEach-Object { $PSItem.FullName -join "," })
        $fmtImportedResult = @($fmtImported | Format-DbaBackupInformation -RebaseBackupFolder "D:\moved")
        @($fmtImportedResult | ForEach-Object { $PSItem.OriginalFullName -join "," }) -join "|" | Should -BeExactly ($fmtImportedNames -join "|")
        @($fmtImportedResult.FullName | Where-Object { $PSItem -notlike "D:\moved\*" }).Count | Should -Be 0
    }

    It "keeps the original file paths in OriginalFileList after relocating files" {
        $fmtHistory = New-FmtHistory -Database "OrigFile" -FullName @("C:\b\OrigFile.bak") -FileList @(
            (New-FmtFile -LogicalName "OrigFile" -PhysicalName "C:\d\OrigFile.mdf" -Type "D"),
            (New-FmtFile -LogicalName "OrigFile_log" -PhysicalName "C:\l\OrigFile_log.ldf" -Type "L")
        )
        $fmtResult = Format-DbaBackupInformation -BackupHistory $fmtHistory -DataFileDirectory "E:\data" -ReplaceDatabaseName "Moved" -ReplaceDbNameInFile
        ($fmtResult.FileList.PhysicalName -join "|") | Should -BeExactly "E:\data\Moved.mdf|E:\data\Moved_log.ldf"
        ($fmtResult.OriginalFileList.PhysicalName -join "|") | Should -BeExactly "C:\d\OrigFile.mdf|C:\l\OrigFile_log.ldf"
        ($fmtResult.OriginalFileList.LogicalName -join "|") | Should -BeExactly "OrigFile|OrigFile_log"
        ($fmtResult.OriginalFileList.Type -join "|") | Should -BeExactly "D|L"

        $fmtImported = @(Get-DbaBackupInformation -Import -Path (Join-Path $fmtRawInput "RestoreTimeClean.xml"))
        $fmtImportedPaths = @($fmtImported | ForEach-Object { $PSItem.FileList.PhysicalName -join "," })
        $fmtImportedResult = @($fmtImported | Format-DbaBackupInformation -DataFileDirectory "E:\data")
        @($fmtImportedResult | ForEach-Object { $PSItem.OriginalFileList.PhysicalName -join "," }) -join "|" | Should -BeExactly ($fmtImportedPaths -join "|")
        @($fmtImportedResult.FileList.PhysicalName | Where-Object { $PSItem -notlike "E:\data\*" }).Count | Should -Be 0
    }
}
