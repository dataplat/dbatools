#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Find-DbaBackup",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: pipeline-multiple N/A -- no parameter takes pipeline input; Path is a single string.
# NativeChecklist: multi-instance-failure N/A -- the command has no SqlInstance or other multi-target parameter; it walks one path.
# NativeChecklist: whatif-confirm N/A -- the command is read-only and does not declare SupportsShouldProcess.
# NativeChecklist: azure-sqldb N/A -- the command never connects to SQL Server; it walks the file system through the PowerShell FileSystem provider, and Azure SQL Database exposes no file system (https://learn.microsoft.com/azure/azure-sql/database/transact-sql-tsql-differences-sql-server).
# NativeChecklist: sql-login N/A -- the pinned command has no SqlCredential parameter and no SQL connection.

Describe "Native Find-DbaBackup" -Tag IntegrationTests {
    BeforeAll {
        $findRoot = "TestDrive:\native_find_$([guid]::NewGuid().ToString('N'))"
        # Files are made through .NET on the file system path; the commands under test get the TestDrive: path.
        $findRootFs = (New-Item -Path $findRoot -ItemType Directory).FullName
        $findOld = (Get-Date).AddDays(-10)

        function New-FindFile {
            param([string]$RelativePath, [datetime]$LastWrite, [string]$Attributes = "Archive")
            $findFile = [System.IO.Path]::Combine($findRootFs, $RelativePath)
            $null = [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($findFile))
            [System.IO.File]::WriteAllText($findFile, ".")
            [System.IO.File]::SetLastWriteTime($findFile, $LastWrite)
            [System.IO.File]::SetAttributes($findFile, [System.IO.FileAttributes]$Attributes)
        }

        New-FindFile -RelativePath "top_old.bak" -LastWrite $findOld
        New-FindFile -RelativePath "top_new.bak" -LastWrite (Get-Date)
        New-FindFile -RelativePath "top_old.trn" -LastWrite $findOld
        New-FindFile -RelativePath "top_old.bakx" -LastWrite $findOld
        New-FindFile -RelativePath "top_hidden.bak" -LastWrite $findOld -Attributes "Hidden"
        New-FindFile -RelativePath "level1\nested_old.bak" -LastWrite $findOld
        New-FindFile -RelativePath "level1\level2\deep [x] old.bak" -LastWrite $findOld -Attributes "Normal"
        New-FindFile -RelativePath "hiddendir\inside_old.bak" -LastWrite $findOld
        [System.IO.File]::SetAttributes([System.IO.Path]::Combine($findRootFs, "hiddendir"), [System.IO.FileAttributes]"Directory, Hidden")
    }

    It "returns the same files and provider objects as Get-ChildItem" {
        $findExpected = @(Get-ChildItem $findRoot -Filter "*.bak" -File -Recurse | Where-Object LastWriteTime -lt (Get-Date).AddDays(-5))
        $findResult = @(Find-DbaBackup -Path $findRoot -BackupFileExtension "bak" -RetentionPeriod "5d")
        $findExpected.Count | Should -BeGreaterThan 2
        ($findResult.FullName | Sort-Object) -join "|" | Should -BeExactly (($findExpected.FullName | Sort-Object) -join "|")
        $findResult.FullName | Should -Not -Contain ([System.IO.Path]::Combine($findRootFs, "top_hidden.bak"))
        foreach ($findItem in $findResult) {
            $findItem | Should -BeOfType [System.IO.FileInfo]
            $findMatch = $findExpected | Where-Object FullName -eq $findItem.FullName
            $findItem.PSPath | Should -BeExactly $findMatch.PSPath
            $findItem.PSParentPath | Should -BeExactly $findMatch.PSParentPath
            $findItem.PSDrive.Name | Should -BeExactly $findMatch.PSDrive.Name
            $findItem.PSProvider.Name | Should -BeExactly "FileSystem"
        }
    }

    It "finds backups under every directory a wildcard path matches" {
        New-FindFile -RelativePath "pipe_1\remove me.bak" -LastWrite $findOld
        New-FindFile -RelativePath "pipe_1\sub\remove too.bak" -LastWrite $findOld
        New-FindFile -RelativePath "pipe_2\also.bak" -LastWrite $findOld
        New-FindFile -RelativePath "star\inner\star_old.bak" -LastWrite $findOld
        $findPipeExpected = @("pipe_1\remove me.bak", "pipe_1\sub\remove too.bak", "pipe_2\also.bak" | ForEach-Object { [System.IO.Path]::Combine($findRootFs, $PSItem) })
        $findWildcard = @(Find-DbaBackup -Path "$findRoot\pipe_*" -BackupFileExtension "bak" -RetentionPeriod "1d")
        ($findWildcard.FullName | Sort-Object) -join "|" | Should -BeExactly (($findPipeExpected | Sort-Object) -join "|")
        $findStar = @(Find-DbaBackup -Path "$findRoot\star\*" -BackupFileExtension "bak" -RetentionPeriod "1d")
        $findStar.FullName | Should -BeExactly ([System.IO.Path]::Combine($findRootFs, "star\inner\star_old.bak"))
        $findWildcard | Remove-Item
        $findPipeExpected | ForEach-Object { [System.IO.File]::Exists($PSItem) | Should -BeFalse }
        [System.IO.Directory]::Exists([System.IO.Path]::Combine($findRootFs, "pipe_1\sub")) | Should -BeTrue
    }

    It "keeps archived files with an explicit -CheckArchiveBit:`$false and drops them with -CheckArchiveBit" -Tag NativeChecklist:switch-false {
        $findAll = @(Find-DbaBackup -Path $findRoot -BackupFileExtension "bak" -RetentionPeriod "5d" -CheckArchiveBit:$false)
        $findUnarchived = @(Find-DbaBackup -Path $findRoot -BackupFileExtension "bak" -RetentionPeriod "5d" -CheckArchiveBit)
        $findAll.Name | Should -Contain "top_old.bak"
        $findUnarchived.Name | Should -Not -Contain "top_old.bak"
        $findUnarchived.Name | Should -Contain "deep [x] old.bak"
        $findUnarchived.Count | Should -Be 1
    }

    It "warns and returns nothing for an invalid retention without EnableException, and throws with it" -Tag NativeChecklist:enable-exception {
        $findWarnings = @()
        $findResult = @(Find-DbaBackup -Path $findRoot -BackupFileExtension "bak" -RetentionPeriod "5y" -WarningVariable findWarnings -WarningAction SilentlyContinue)
        $findResult.Count | Should -Be 0
        ($findWarnings -join " ") | Should -BeLike "*Failed to interpret retention time.*"
        { Find-DbaBackup -Path $findRoot -BackupFileExtension "bak" -RetentionPeriod "5y" -EnableException } | Should -Throw "*units invalid*"
    }

    It "warns and returns nothing for a missing path without EnableException" -Tag NativeChecklist:enable-exception {
        $findWarnings = @()
        $findResult = @(Find-DbaBackup -Path "$findRoot\missing" -BackupFileExtension "bak" -RetentionPeriod "1d" -WarningVariable findWarnings -WarningAction SilentlyContinue)
        $findResult.Count | Should -Be 0
        ($findWarnings -join " ") | Should -BeLike "*missing not found*"
    }

    It "accepts upper-case units and a signed value as the pinned conversion does" {
        @(Find-DbaBackup -Path $findRoot -BackupFileExtension "bak" -RetentionPeriod "+5D").Count | Should -Be @(Find-DbaBackup -Path $findRoot -BackupFileExtension "bak" -RetentionPeriod "5d").Count
        { Find-DbaBackup -Path $findRoot -BackupFileExtension "bak" -RetentionPeriod "d" -EnableException } | Should -Throw "*format invalid*"
    }

    It "warns about directories it cannot enumerate and still returns the rest" {
        $findDenied = [System.IO.Path]::Combine($findRootFs, "denied")
        New-FindFile -RelativePath "denied\locked_old.bak" -LastWrite $findOld
        $findSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
        $findRule = New-Object System.Security.AccessControl.FileSystemAccessRule($findSid, "ListDirectory", "Deny")
        $findAcl = Get-Acl -LiteralPath $findDenied
        $findAcl.AddAccessRule($findRule)
        Set-Acl -LiteralPath $findDenied -AclObject $findAcl
        try {
            $findGciErrors = @()
            $null = Get-ChildItem $findRoot -Filter "*.bak" -File -Recurse -ErrorAction SilentlyContinue -ErrorVariable findGciErrors
            $findGciErrors.Count | Should -BeGreaterThan 0 -Because "the deny rule makes Get-ChildItem fail on that directory too"
            $findWarnings = @()
            $findResult = @(Find-DbaBackup -Path $findRoot -BackupFileExtension "bak" -RetentionPeriod "5d" -WarningVariable findWarnings -WarningAction SilentlyContinue)
            ($findWarnings -join " ") | Should -BeLike "*Errors encountered enumerating files.*"
            $findResult.Name | Should -Contain "top_old.bak"
            $findResult.Name | Should -Not -Contain "locked_old.bak"
        } finally {
            $findAcl = Get-Acl -LiteralPath $findDenied
            $null = $findAcl.RemoveAccessRule($findRule)
            Set-Acl -LiteralPath $findDenied -AclObject $findAcl
        }
    }
}
