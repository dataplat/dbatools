#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Export-DbaSsisProject",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Folder",
                "Project",
                "Path",
                "FilePath",
                "Force",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        It "Should expose Name as an alias of Project" {
            (Get-Command $CommandName).Parameters["Project"].Aliases | Should -Contain "Name"
        }

        It "Should declare ShouldProcess" {
            (Get-Command $CommandName).Parameters.Keys | Should -Contain "WhatIf"
        }

        It "Should take projects from the pipeline" {
            $inputObject = (Get-Command $CommandName).Parameters["InputObject"]
            $inputObject.ParameterType.FullName | Should -Be "System.Management.Automation.PSObject[]"
            $inputObject.Attributes.Where({ $PSItem -is [System.Management.Automation.ParameterAttribute] }).ValueFromPipeline | Should -Contain $true
        }

        It "Should not make SqlInstance mandatory, so the input object path can bind" {
            $sqlInstance = (Get-Command $CommandName).Parameters["SqlInstance"]
            $sqlInstance.Attributes.Where({ $PSItem -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -Not -Contain $true
            $sqlInstance.Attributes.Where({ $PSItem -is [System.Management.Automation.ParameterAttribute] }).ValueFromPipeline | Should -Not -Contain $true
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        $ssisInstance   = $TestConfig.InstanceSsis
        $exportFolder   = "dbatoolsci_expfolder1"
        $secondFolder   = "dbatoolsci_expfolder2"
        $simpleProject  = "dbatoolsci_expproject1"
        $secondProject  = "dbatoolsci_expproject2"
        $whatIfProject  = "dbatoolsci_expproject3"
        $forceProject   = "dbatoolsci_expproject4"
        $pipedProject   = "dbatoolsci_expproject5"
        $missingProject = "dbatoolsci_expnosuchproject"
        $exportProjects = @($simpleProject, $secondProject, $whatIfProject, $forceProject, $pipedProject)

        # An .ispac is an OPC zip of four text parts, so the suite builds its own rather than
        # depending on a binary fixture or on the SSIS design-time assemblies, which ship only for
        # Windows PowerShell. The project name inside the manifest is what the catalog stores, and
        # reading it back out of the exported file is what proves the export carried the real
        # project stream rather than any bytes of the right length.
        function New-SsisProjectFile {
            param($ProjectName, $PackageName, $Path)

            if (-not ("System.IO.Compression.ZipArchive" -as [type])) {
                Add-Type -AssemblyName "System.IO.Compression"
            }

            $packageXml = @"
<?xml version="1.0"?>
<DTS:Executable xmlns:DTS="www.microsoft.com/SqlServer/Dts" DTS:refId="Package" DTS:CreationName="Microsoft.Package" DTS:DTSID="{11D1A8D9-CC5B-4F22-9C7E-08890C43B547}" DTS:ExecutableType="Microsoft.Package" DTS:LocaleID="1033" DTS:ObjectName="$PackageName" DTS:VersionGUID="{B7CC7047-831E-4853-B30A-6C22843AC290}"><DTS:Property DTS:Name="PackageFormatVersion">8</DTS:Property><DTS:Variables /><DTS:Executables /></DTS:Executable>
"@

            $parametersXml = @"
<?xml version="1.0"?>
<SSIS:Parameters xmlns:SSIS="www.microsoft.com/SqlServer/SSIS" />
"@

            $manifestXml = @"
<SSIS:Project SSIS:ProtectionLevel="DontSaveSensitive" xmlns:SSIS="www.microsoft.com/SqlServer/SSIS">
  <SSIS:Properties>
    <SSIS:Property SSIS:Name="ID">{010f1219-5a15-4d9f-8736-08541cd40b6e}</SSIS:Property>
    <SSIS:Property SSIS:Name="Name">$ProjectName</SSIS:Property>
    <SSIS:Property SSIS:Name="VersionMajor">1</SSIS:Property>
    <SSIS:Property SSIS:Name="VersionMinor">0</SSIS:Property>
    <SSIS:Property SSIS:Name="VersionBuild">0</SSIS:Property>
    <SSIS:Property SSIS:Name="VersionComments">
    </SSIS:Property>
    <SSIS:Property SSIS:Name="CreationDate">2026-08-03T15:40:56.683402+02:00</SSIS:Property>
    <SSIS:Property SSIS:Name="CreatorName">dbatools</SSIS:Property>
    <SSIS:Property SSIS:Name="CreatorComputerName">dbatools</SSIS:Property>
    <SSIS:Property SSIS:Name="Description">
    </SSIS:Property>
    <SSIS:Property SSIS:Name="FormatVersion">1</SSIS:Property>
  </SSIS:Properties>
  <SSIS:Packages>
    <SSIS:Package SSIS:Name="$PackageName.dtsx" SSIS:EntryPoint="1" />
  </SSIS:Packages>
  <SSIS:ConnectionManagers />
  <SSIS:DeploymentInfo>
    <SSIS:ProjectConnectionParameters />
    <SSIS:PackageInfo>
      <SSIS:PackageMetaData SSIS:Name="$PackageName.dtsx">
        <SSIS:Properties>
          <SSIS:Property SSIS:Name="ID">{11D1A8D9-CC5B-4F22-9C7E-08890C43B547}</SSIS:Property>
          <SSIS:Property SSIS:Name="Name">$PackageName</SSIS:Property>
          <SSIS:Property SSIS:Name="VersionMajor">1</SSIS:Property>
          <SSIS:Property SSIS:Name="VersionMinor">0</SSIS:Property>
          <SSIS:Property SSIS:Name="VersionBuild">0</SSIS:Property>
          <SSIS:Property SSIS:Name="VersionComments">
          </SSIS:Property>
          <SSIS:Property SSIS:Name="VersionGUID">{B7CC7047-831E-4853-B30A-6C22843AC290}</SSIS:Property>
          <SSIS:Property SSIS:Name="PackageFormatVersion">8</SSIS:Property>
          <SSIS:Property SSIS:Name="Description">
          </SSIS:Property>
          <SSIS:Property SSIS:Name="ProtectionLevel">0</SSIS:Property>
        </SSIS:Properties>
        <SSIS:Parameters />
      </SSIS:PackageMetaData>
    </SSIS:PackageInfo>
  </SSIS:DeploymentInfo>
</SSIS:Project>
"@

            $contentTypesXml = "<?xml version=`"1.0`" encoding=`"utf-8`"?><Types xmlns=`"http://schemas.openxmlformats.org/package/2006/content-types`"><Default Extension=`"dtsx`" ContentType=`"text/xml`" /><Default Extension=`"params`" ContentType=`"text/xml`" /><Default Extension=`"manifest`" ContentType=`"text/xml`" /></Types>"

            $fileStream = New-Object System.IO.FileStream ($Path, [System.IO.FileMode]::Create)
            $archive = New-Object System.IO.Compression.ZipArchive ($fileStream, [System.IO.Compression.ZipArchiveMode]::Create)
            try {
                foreach ($part in @(@("$PackageName.dtsx", $packageXml), @("Project.params", $parametersXml), @("@Project.manifest", $manifestXml), @("[Content_Types].xml", $contentTypesXml))) {
                    $entry = $archive.CreateEntry($part[0])
                    $entryWriter = New-Object System.IO.StreamWriter ($entry.Open())
                    $entryWriter.Write($part[1])
                    $entryWriter.Flush()
                    $entryWriter.Dispose()
                }
            } finally {
                $archive.Dispose()
                $fileStream.Dispose()
            }
        }

        # The name recorded in the manifest INSIDE the exported file. A length check alone passes on
        # any file of the right size, including one left over from an earlier project.
        function Get-SsisProjectFileName {
            param($Path)

            if (-not ("System.IO.Compression.ZipArchive" -as [type])) {
                Add-Type -AssemblyName "System.IO.Compression"
            }

            $fileStream = New-Object System.IO.FileStream ($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read)
            $archive = New-Object System.IO.Compression.ZipArchive ($fileStream, [System.IO.Compression.ZipArchiveMode]::Read)
            try {
                $manifestEntry = $archive.Entries | Where-Object { $PSItem.FullName -eq "@Project.manifest" }
                if (-not $manifestEntry) {
                    return $null
                }
                $entryReader = New-Object System.IO.StreamReader ($manifestEntry.Open())
                $manifestText = $entryReader.ReadToEnd()
                $entryReader.Dispose()
                $manifestXml = [xml]$manifestText
                ($manifestXml.Project.Properties.Property | Where-Object { $PSItem.Name -eq "Name" }).InnerText
            } finally {
                $archive.Dispose()
                $fileStream.Dispose()
            }
        }

        # A leftover from an interrupted run would leave the deploy legs redeploying instead of
        # deploying, so both fixture folders are cleared before the run rather than only after it.
        foreach ($staleFolder in @($exportFolder, $secondFolder)) {
            $splatStaleProjects = @{
                SqlInstance  = $ssisInstance
                Database     = "SSISDB"
                Query        = "DECLARE @name sysname; DECLARE leftovers CURSOR LOCAL FAST_FORWARD FOR SELECT p.name FROM [catalog].[projects] p JOIN [catalog].[folders] f ON f.folder_id = p.folder_id WHERE f.name = @folder; OPEN leftovers; FETCH NEXT FROM leftovers INTO @name; WHILE @@FETCH_STATUS = 0 BEGIN EXEC [catalog].[delete_project] @folder_name = @folder, @project_name = @name; FETCH NEXT FROM leftovers INTO @name; END; CLOSE leftovers; DEALLOCATE leftovers;"
                SqlParameter = @{ folder = $staleFolder }
            }
            Invoke-DbaQuery @splatStaleProjects

            $splatFolderSetup = @{
                SqlInstance  = $ssisInstance
                Database     = "SSISDB"
                Query        = "IF NOT EXISTS (SELECT 1 FROM [catalog].[folders] WHERE name = @folder) EXEC [catalog].[create_folder] @folder_name = @folder, @folder_id = NULL;"
                SqlParameter = @{ folder = $staleFolder }
            }
            Invoke-DbaQuery @splatFolderSetup
        }

        # A fresh directory of this run's own, rather than predictable names in the shared temp
        # root: two runs at once would otherwise write each other's fixture files, and cleaning up
        # by filter would delete the other run's.
        $exportRunId = [guid]::NewGuid().ToString("n")
        $sourceRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "dbatoolsci_expsrc_$exportRunId"
        $exportRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "dbatoolsci_expout_$exportRunId"
        $null = New-Item -Path $sourceRoot -ItemType Directory -Force
        $null = New-Item -Path $exportRoot -ItemType Directory -Force

        foreach ($projectName in $exportProjects) {
            $projectPath = Join-Path -Path $sourceRoot -ChildPath "$projectName.ispac"
            New-SsisProjectFile -ProjectName $projectName -PackageName "$projectName`_package" -Path $projectPath

            $splatDeploy = @{
                SqlInstance = $ssisInstance
                Folder      = $exportFolder
                Project     = $projectName
                Path        = $projectPath
            }
            $null = Publish-DbaSsisProject @splatDeploy
        }

        # The same project name in a second folder, so the folder half of the auto-generated file
        # name is load-bearing: a command naming files after the project alone collides here.
        $secondFolderPath = Join-Path -Path $sourceRoot -ChildPath "$simpleProject`_second.ispac"
        New-SsisProjectFile -ProjectName $simpleProject -PackageName "$simpleProject`_package" -Path $secondFolderPath
        $splatSecondFolderDeploy = @{
            SqlInstance = $ssisInstance
            Folder      = $secondFolder
            Project     = $simpleProject
            Path        = $secondFolderPath
        }
        $null = Publish-DbaSsisProject @splatSecondFolderDeploy
    }

    AfterAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        # Everything in the suite's own folders goes, rather than a list of names to keep in step
        # with the fixtures - a surviving project also blocks its folder from being dropped. The
        # folder literals rather than the variables so cleanup still runs when BeforeAll died
        # before setting them.
        foreach ($cleanupFolder in @("dbatoolsci_expfolder1", "dbatoolsci_expfolder2")) {
            $splatProjectCleanup = @{
                SqlInstance  = $TestConfig.InstanceSsis
                Database     = "SSISDB"
                Query        = "DECLARE @name sysname; DECLARE leftovers CURSOR LOCAL FAST_FORWARD FOR SELECT p.name FROM [catalog].[projects] p JOIN [catalog].[folders] f ON f.folder_id = p.folder_id WHERE f.name = @folder; OPEN leftovers; FETCH NEXT FROM leftovers INTO @name; WHILE @@FETCH_STATUS = 0 BEGIN EXEC [catalog].[delete_project] @folder_name = @folder, @project_name = @name; FETCH NEXT FROM leftovers INTO @name; END; CLOSE leftovers; DEALLOCATE leftovers;"
                SqlParameter = @{ folder = $cleanupFolder }
            }
            Invoke-DbaQuery @splatProjectCleanup

            $splatFolderCleanup = @{
                SqlInstance  = $TestConfig.InstanceSsis
                Database     = "SSISDB"
                Query        = "IF EXISTS (SELECT 1 FROM [catalog].[folders] WHERE name = @folder) EXEC [catalog].[delete_folder] @folder_name = @folder;"
                SqlParameter = @{ folder = $cleanupFolder }
            }
            Invoke-DbaQuery @splatFolderCleanup
        }

        foreach ($runDirectory in @($sourceRoot, $exportRoot)) {
            if ($runDirectory -and (Test-Path -LiteralPath $runDirectory)) {
                Remove-Item -LiteralPath $runDirectory -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Exporting into a directory" {
        It "Writes the project stream the catalog holds" {
            $splatExport = @{
                SqlInstance = $ssisInstance
                Folder      = $exportFolder
                Project     = $simpleProject
                Path        = $exportRoot
            }
            $exported = @(Export-DbaSsisProject @splatExport)
            $exported.Count | Should -Be 1

            $expectedFile = Join-Path -Path $exportRoot -ChildPath "$exportFolder-$simpleProject.ispac"
            Test-Path -LiteralPath $expectedFile | Should -BeTrue
            $exported[0].FilePath | Should -Be $expectedFile
            $exported[0].Bytes | Should -Be (Get-Item -LiteralPath $expectedFile).Length
            $exported[0].Bytes | Should -BeGreaterThan 0

            # The bytes are the project the catalog holds, not merely a file of plausible size.
            Get-SsisProjectFileName -Path $expectedFile | Should -Be $simpleProject
        }

        It "Names the file after the folder as well as the project" {
            # The same project name is deployed in two folders, so a command naming files after the
            # project alone writes the second export over the first and this leg finds one file.
            $splatSecondFolder = @{
                SqlInstance = $ssisInstance
                Folder      = $secondFolder
                Project     = $simpleProject
                Path        = $exportRoot
            }
            $exported = @(Export-DbaSsisProject @splatSecondFolder)
            $exported.Count | Should -Be 1

            $firstFile = Join-Path -Path $exportRoot -ChildPath "$exportFolder-$simpleProject.ispac"
            $secondFile = Join-Path -Path $exportRoot -ChildPath "$secondFolder-$simpleProject.ispac"
            Test-Path -LiteralPath $firstFile | Should -BeTrue
            Test-Path -LiteralPath $secondFile | Should -BeTrue
            $exported[0].FilePath | Should -Be $secondFile
        }

        It "Decorates the exported project like the read command does, with the file it wrote" {
            $read = @(Get-DbaSsisProject -SqlInstance $ssisInstance -Folder $exportFolder -Project $secondProject)[0]
            $splatDecoration = @{
                SqlInstance = $ssisInstance
                Folder      = $exportFolder
                Project     = $secondProject
                Path        = $exportRoot
            }
            $exported = @(Export-DbaSsisProject @splatDecoration)[0]
            $exported.PSObject.TypeNames[0] | Should -Be "dbatools.SsisProject"
            $exported.ComputerName | Should -Not -BeNullOrEmpty
            $exported.InstanceName | Should -Not -BeNullOrEmpty
            $exported.SqlInstance | Should -Not -BeNullOrEmpty

            # Every property the read emits, carrying the same value, plus exactly the two export
            # facts - so this is the read's object with the file details attached, not a different
            # shape that happens to share a name. Values compare as text because the timestamps are
            # DbaDateTime, which is not equatable to another instance of itself.
            $expectedProperties = @($read.PSObject.Properties.Name) + @("FilePath", "Bytes")
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject @($exported.PSObject.Properties.Name) | Should -BeNullOrEmpty
            foreach ($readProperty in $read.PSObject.Properties.Name) {
                [string]$exported.$readProperty | Should -Be ([string]$read.$readProperty)
            }
            $exported.FilePath | Should -Not -BeNullOrEmpty
            $exported.Bytes | Should -BeGreaterThan 0
        }

        It "Exports every project a multi-project selection resolves to" {
            # Two records through one invocation: a command that exported only the first would pass
            # every single-project leg in this file.
            $multiRoot = Join-Path -Path $exportRoot -ChildPath "multi"
            $splatMulti = @{
                SqlInstance = $ssisInstance
                Folder      = $exportFolder
                Project     = @($simpleProject, $secondProject)
                Path        = $multiRoot
            }
            $exported = @(Export-DbaSsisProject @splatMulti)
            $exported.Count | Should -Be 2

            $firstFile = Join-Path -Path $multiRoot -ChildPath "$exportFolder-$simpleProject.ispac"
            $secondFile = Join-Path -Path $multiRoot -ChildPath "$exportFolder-$secondProject.ispac"
            Test-Path -LiteralPath $firstFile | Should -BeTrue
            Test-Path -LiteralPath $secondFile | Should -BeTrue
            Get-SsisProjectFileName -Path $firstFile | Should -Be $simpleProject
            Get-SsisProjectFileName -Path $secondFile | Should -Be $secondProject
        }

        It "Falls back to the export configuration directory when neither path is supplied" {
            $configRoot = Join-Path -Path $exportRoot -ChildPath "fromconfig"
            $null = New-Item -Path $configRoot -ItemType Directory -Force
            $previousExportPath = Get-DbatoolsConfigValue -FullName "Path.DbatoolsExport"
            try {
                Set-DbatoolsConfig -FullName "Path.DbatoolsExport" -Value $configRoot
                $splatDefaultPath = @{
                    SqlInstance = $ssisInstance
                    Folder      = $exportFolder
                    Project     = $pipedProject
                }
                $exported = @(Export-DbaSsisProject @splatDefaultPath)
                $exported.Count | Should -Be 1
                $exported[0].FilePath | Should -Be (Join-Path -Path $configRoot -ChildPath "$exportFolder-$pipedProject.ispac")
                Test-Path -LiteralPath $exported[0].FilePath | Should -BeTrue
            } finally {
                Set-DbatoolsConfig -FullName "Path.DbatoolsExport" -Value $previousExportPath
            }
        }
    }

    Context "Exporting to a named file" {
        It "Writes exactly the file it was given" {
            $namedFile = Join-Path -Path $exportRoot -ChildPath "named-export.ispac"
            $splatNamed = @{
                SqlInstance = $ssisInstance
                Folder      = $exportFolder
                Project     = $simpleProject
                FilePath    = $namedFile
            }
            $exported = @(Export-DbaSsisProject @splatNamed)
            $exported.Count | Should -Be 1
            $exported[0].FilePath | Should -Be $namedFile
            Get-SsisProjectFileName -Path $namedFile | Should -Be $simpleProject
        }

        It "Refuses a selection of more than one project and writes nothing" {
            # Without the refusal each project would overwrite the previous one and the caller would
            # be holding a single file believing they had several, so the assertion is that the file
            # was never created at all.
            $collidingFile = Join-Path -Path $exportRoot -ChildPath "colliding-export.ispac"
            $splatColliding = @{
                SqlInstance = $ssisInstance
                Folder      = $exportFolder
                Project     = @($simpleProject, $secondProject)
                FilePath    = $collidingFile
            }
            { Export-DbaSsisProject @splatColliding } | Should -Throw "*resolved to 2*"
            Test-Path -LiteralPath $collidingFile | Should -BeFalse
        }

        It "Refuses -Path and -FilePath together" {
            $bothFile = Join-Path -Path $exportRoot -ChildPath "both-export.ispac"
            $splatBoth = @{
                SqlInstance = $ssisInstance
                Folder      = $exportFolder
                Project     = $simpleProject
                Path        = $exportRoot
                FilePath    = $bothFile
            }
            { Export-DbaSsisProject @splatBoth } | Should -Throw "*one or the other*"
            Test-Path -LiteralPath $bothFile | Should -BeFalse
        }
    }

    Context "An existing destination file" {
        It "Refuses to overwrite it and leaves it untouched" {
            $occupiedFile = Join-Path -Path $exportRoot -ChildPath "occupied-export.ispac"
            Set-Content -LiteralPath $occupiedFile -Value "not a project file" -Encoding Ascii -NoNewline

            $splatNoForce = @{
                SqlInstance = $ssisInstance
                Folder      = $exportFolder
                Project     = $forceProject
                FilePath    = $occupiedFile
            }
            { Export-DbaSsisProject @splatNoForce } | Should -Throw "*already exists*"

            # The content, not just the existence: a command that wrote and then reported the error
            # would still leave the file there.
            Get-Content -LiteralPath $occupiedFile -Raw | Should -Be "not a project file"
        }

        It "Overwrites it under -Force" {
            $forcedFile = Join-Path -Path $exportRoot -ChildPath "forced-export.ispac"
            Set-Content -LiteralPath $forcedFile -Value "not a project file" -Encoding Ascii -NoNewline

            $splatForce = @{
                SqlInstance = $ssisInstance
                Folder      = $exportFolder
                Project     = $forceProject
                FilePath    = $forcedFile
                Force       = $true
            }
            $exported = @(Export-DbaSsisProject @splatForce)
            $exported.Count | Should -Be 1
            Get-SsisProjectFileName -Path $forcedFile | Should -Be $forceProject
        }

        It "Refusing one file still exports the rest of the selection" {
            $partialRoot = Join-Path -Path $exportRoot -ChildPath "partial"
            $null = New-Item -Path $partialRoot -ItemType Directory -Force
            $blockedFile = Join-Path -Path $partialRoot -ChildPath "$exportFolder-$simpleProject.ispac"
            Set-Content -LiteralPath $blockedFile -Value "not a project file" -Encoding Ascii -NoNewline

            $splatPartial = @{
                SqlInstance     = $ssisInstance
                Folder          = $exportFolder
                Project         = @($simpleProject, $secondProject)
                Path            = $partialRoot
                EnableException = $false
                WarningVariable = "partialWarning"
                WarningAction   = "SilentlyContinue"
            }
            $exported = @(Export-DbaSsisProject @splatPartial)
            $exported.Count | Should -Be 1
            $exported[0].Name | Should -Be $secondProject
            ($partialWarning -join " ") | Should -BeLike "*already exists*"

            Get-Content -LiteralPath $blockedFile -Raw | Should -Be "not a project file"
            Get-SsisProjectFileName -Path (Join-Path -Path $partialRoot -ChildPath "$exportFolder-$secondProject.ispac") | Should -Be $secondProject
        }
    }

    Context "Taking projects from the pipeline" {
        It "Exports the projects Get-DbaSsisProject emits" {
            $pipedRoot = Join-Path -Path $exportRoot -ChildPath "piped"
            # Two objects piped in literally rather than a name list: a list quietly becomes a
            # one-record leg if a fixture goes missing, and the second record is the only place the
            # command's per-invocation state is observable at all.
            $pipedFirstProject = @(Get-DbaSsisProject -SqlInstance $ssisInstance -Folder $exportFolder -Project $simpleProject)[0]
            $pipedSecondProject = @(Get-DbaSsisProject -SqlInstance $ssisInstance -Folder $exportFolder -Project $pipedProject)[0]
            $exported = @($pipedFirstProject, $pipedSecondProject | Export-DbaSsisProject -Path $pipedRoot)
            $exported.Count | Should -Be 2
            $exported[1].Name | Should -Be $pipedProject

            $pipedFirst = Join-Path -Path $pipedRoot -ChildPath "$exportFolder-$simpleProject.ispac"
            $pipedSecond = Join-Path -Path $pipedRoot -ChildPath "$exportFolder-$pipedProject.ispac"
            Get-SsisProjectFileName -Path $pipedFirst | Should -Be $simpleProject
            Get-SsisProjectFileName -Path $pipedSecond | Should -Be $pipedProject
        }

        It "Refuses an object that is not an SSIS project" {
            $strayRoot = Join-Path -Path $exportRoot -ChildPath "stray"
            $stray = [PSCustomObject]@{
                SqlInstance = $ssisInstance
                FolderName  = $exportFolder
                Name        = $simpleProject
            }
            { $stray | Export-DbaSsisProject -Path $strayRoot } | Should -Throw "*dbatools.SsisProject*"
            Test-Path -LiteralPath $strayRoot | Should -BeFalse
        }
    }

    Context "A project that is not there" {
        It "Reports it and writes no file" {
            $missingRoot = Join-Path -Path $exportRoot -ChildPath "missing"
            $splatMissing = @{
                SqlInstance = $ssisInstance
                Folder      = $exportFolder
                Project     = $missingProject
                Path        = $missingRoot
            }
            { Export-DbaSsisProject @splatMissing } | Should -Throw "*No SSIS project matched*"
            Test-Path -LiteralPath $missingRoot | Should -BeFalse
        }
    }

    Context "-WhatIf" {
        It "Reports without writing the file" {
            $whatIfRoot = Join-Path -Path $exportRoot -ChildPath "whatif"
            $splatWhatIf = @{
                SqlInstance = $ssisInstance
                Folder      = $exportFolder
                Project     = $whatIfProject
                Path        = $whatIfRoot
                WhatIf      = $true
            }
            $whatIfResult = @(Export-DbaSsisProject @splatWhatIf)
            $whatIfResult.Count | Should -Be 0

            # The directory as well as the file: creating the destination is a side effect too.
            Test-Path -LiteralPath (Join-Path -Path $whatIfRoot -ChildPath "$exportFolder-$whatIfProject.ispac") | Should -BeFalse
            Test-Path -LiteralPath $whatIfRoot | Should -BeFalse
        }
    }

    Context "An instance with no SSIS catalog" {
        # InstanceSingle carries no SSISDB, so this exercises the presence check rather than
        # failing inside the catalog schema.
        It "Warns and returns nothing" {
            $noCatalogRoot = Join-Path -Path $exportRoot -ChildPath "nocatalog"
            $splatNoCatalog = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Folder          = $exportFolder
                Project         = $simpleProject
                Path            = $noCatalogRoot
                EnableException = $false
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $none = @(Export-DbaSsisProject @splatNoCatalog)
            $none.Count | Should -Be 0
            ($warn -join " ") | Should -BeLike "*No SSIS catalog (SSISDB) found*"
            Test-Path -LiteralPath $noCatalogRoot | Should -BeFalse
        }

        It "Throws under -EnableException" {
            $splatNoCatalogThrow = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Folder          = $exportFolder
                Project         = $simpleProject
                Path            = (Join-Path -Path $exportRoot -ChildPath "nocatalogthrow")
                EnableException = $true
            }
            { Export-DbaSsisProject @splatNoCatalogThrow } | Should -Throw "*No SSIS catalog (SSISDB) found*"
        }
    }
}
