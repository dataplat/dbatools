#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Publish-DbaSsisProject",
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

        It "Should take a single folder and a single project" {
            (Get-Command $CommandName).Parameters["Folder"].ParameterType.FullName | Should -Be "System.String"
            (Get-Command $CommandName).Parameters["Project"].ParameterType.FullName | Should -Be "System.String"
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        $ssisInstance   = $TestConfig.InstanceSsis
        $deployFolder   = "dbatoolsci_pubfolder1"
        $simpleProject  = "dbatoolsci_pubproject1"
        $aliasProject   = "dbatoolsci_pubproject2"
        $versionProject = "dbatoolsci_pubproject3"
        $whatIfProject  = "dbatoolsci_pubproject4"
        $mismatchName   = "dbatoolsci_pubproject5"
        $corruptProject = "dbatoolsci_pubproject6"
        $aliasNameProject = "dbatoolsci_pubproject7"
        $missingFolder  = "dbatoolsci_pubnosuchfolder"
        $createdProjects = @($simpleProject, $aliasProject, $versionProject, $whatIfProject, $mismatchName, $corruptProject, $aliasNameProject)

        # An .ispac is an OPC zip of four text parts, so the suite builds its own rather than
        # depending on a binary fixture or on the SSIS design-time assemblies, which ship only for
        # Windows PowerShell. The project name inside the manifest is what the catalog matches
        # -Project against, which is also what makes the mismatch leg below constructible.
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

        function Get-SsisProjectRow {
            param($Folder, $Project)
            $splatProjectRead = @{
                SqlInstance  = $TestConfig.InstanceSsis
                Database     = "SSISDB"
                Query        = "SELECT p.project_id, p.name, p.object_version_lsn FROM [catalog].[projects] p JOIN [catalog].[folders] f ON f.folder_id = p.folder_id WHERE f.name = @folder AND p.name = @project"
                SqlParameter = @{
                    folder  = $Folder
                    project = $Project
                }
            }
            # The comma keeps the array intact across the return: without it PowerShell unrolls a
            # one-row result to a bare DataRow, and [0] then indexes its first COLUMN, not its
            # first row.
            , @(Invoke-DbaQuery @splatProjectRead)
        }

        # A leftover from an interrupted run would turn the create legs into redeploys, so the
        # names are cleared before the run rather than only after it.
        foreach ($staleProject in $createdProjects) {
            $splatStaleProject = @{
                SqlInstance  = $ssisInstance
                Database     = "SSISDB"
                Query        = "IF EXISTS (SELECT 1 FROM [catalog].[projects] p JOIN [catalog].[folders] f ON f.folder_id = p.folder_id WHERE f.name = @folder AND p.name = @project) EXEC [catalog].[delete_project] @folder_name = @folder, @project_name = @project;"
                SqlParameter = @{
                    folder  = $deployFolder
                    project = $staleProject
                }
            }
            Invoke-DbaQuery @splatStaleProject
        }

        $splatFolderSetup = @{
            SqlInstance  = $ssisInstance
            Database     = "SSISDB"
            Query        = "IF NOT EXISTS (SELECT 1 FROM [catalog].[folders] WHERE name = @folder) EXEC [catalog].[create_folder] @folder_name = @folder, @folder_id = NULL;"
            SqlParameter = @{ folder = $deployFolder }
        }
        Invoke-DbaQuery @splatFolderSetup

        # A fresh directory of this run's own, rather than predictable names in the shared temp
        # root: two runs at once would otherwise write each other's fixture files, and cleaning up
        # by filter would delete the other run's.
        $publishRunId = [guid]::NewGuid().ToString("n")
        $projectRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "dbatoolsci_pub_$publishRunId"
        $null = New-Item -Path $projectRoot -ItemType Directory -Force

        $projectFiles = @{ }
        foreach ($projectName in $createdProjects) {
            $projectPath = Join-Path -Path $projectRoot -ChildPath "$projectName.ispac"
            New-SsisProjectFile -ProjectName $projectName -PackageName "$projectName`_package" -Path $projectPath
            $projectFiles[$projectName] = $projectPath
        }

        # Deliberately not a zip, so the catalog fails to open the stream at all - the second of
        # the two reasons it reports only through its operation log.
        $corruptPath = Join-Path -Path $projectRoot -ChildPath "dbatoolsci_pubcorrupt.ispac"
        Set-Content -LiteralPath $corruptPath -Value "this is not a project file" -Encoding Ascii
        $emptyPath = Join-Path -Path $projectRoot -ChildPath "dbatoolsci_pubempty.ispac"
        Set-Content -LiteralPath $emptyPath -Value "" -NoNewline -Encoding Ascii
        $absentPath = Join-Path -Path $projectRoot -ChildPath "dbatoolsci_pubabsent.ispac"
    }

    AfterAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        foreach ($leftoverProject in @("dbatoolsci_pubproject1", "dbatoolsci_pubproject2", "dbatoolsci_pubproject3", "dbatoolsci_pubproject4", "dbatoolsci_pubproject5", "dbatoolsci_pubproject6")) {
            $splatProjectCleanup = @{
                SqlInstance  = $TestConfig.InstanceSsis
                Database     = "SSISDB"
                Query        = "IF EXISTS (SELECT 1 FROM [catalog].[projects] p JOIN [catalog].[folders] f ON f.folder_id = p.folder_id WHERE f.name = @folder AND p.name = @project) EXEC [catalog].[delete_project] @folder_name = @folder, @project_name = @project;"
                SqlParameter = @{
                    folder  = "dbatoolsci_pubfolder1"
                    project = $leftoverProject
                }
            }
            Invoke-DbaQuery @splatProjectCleanup
        }

        $splatFolderCleanup = @{
            SqlInstance  = $TestConfig.InstanceSsis
            Database     = "SSISDB"
            Query        = "IF EXISTS (SELECT 1 FROM [catalog].[folders] WHERE name = @folder) EXEC [catalog].[delete_folder] @folder_name = @folder;"
            SqlParameter = @{ folder = "dbatoolsci_pubfolder1" }
        }
        Invoke-DbaQuery @splatFolderCleanup

        if ($projectRoot -and (Test-Path -LiteralPath $projectRoot)) {
            Remove-Item -LiteralPath $projectRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Deploying a project" {
        It "Deploys the project and returns it" {
            $splatPublish = @{
                SqlInstance = $ssisInstance
                Folder      = $deployFolder
                Project     = $simpleProject
                Path        = $projectFiles[$simpleProject]
            }
            $published = @(Publish-DbaSsisProject @splatPublish)
            $published.Count | Should -Be 1
            $published[0].Name | Should -Be $simpleProject
            $published[0].FolderName | Should -Be $deployFolder
            $published[0].LastDeployedTime | Should -Not -BeNullOrEmpty
            $published[0].DeployedByName | Should -Not -BeNullOrEmpty

            $catalogRow = Get-SsisProjectRow -Folder $deployFolder -Project $simpleProject
            $catalogRow.Count | Should -Be 1
            $published[0].ProjectId | Should -Be $catalogRow[0].project_id
        }

        It "Deploys the packages the project file carries" {
            $splatPackageRead = @{
                SqlInstance  = $ssisInstance
                Database     = "SSISDB"
                Query        = "SELECT k.name FROM [catalog].[packages] k JOIN [catalog].[projects] p ON p.project_id = k.project_id JOIN [catalog].[folders] f ON f.folder_id = p.folder_id WHERE f.name = @folder AND p.name = @project"
                SqlParameter = @{
                    folder  = $deployFolder
                    project = $simpleProject
                }
            }
            $packages = @(Invoke-DbaQuery @splatPackageRead)
            $packages.Count | Should -Be 1
            $packages[0].name | Should -Be "$simpleProject`_package.dtsx"
        }

        It "Decorates the deployed project exactly like the read command does" {
            $read = @(Get-DbaSsisProject -SqlInstance $ssisInstance -Folder $deployFolder -Project $simpleProject)[0]
            $splatDecoration = @{
                SqlInstance = $ssisInstance
                Folder      = $deployFolder
                Project     = $aliasProject
                Path        = $projectFiles[$aliasProject]
            }
            $published = @(Publish-DbaSsisProject @splatDecoration)[0]
            $published.PSObject.TypeNames[0] | Should -Be "dbatools.SsisProject"
            $published.ComputerName | Should -Not -BeNullOrEmpty
            $published.InstanceName | Should -Not -BeNullOrEmpty
            $published.SqlInstance | Should -Not -BeNullOrEmpty
            $publishedDisplaySet = $published.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $readDisplaySet = $read.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $readDisplaySet -DifferenceObject $publishedDisplaySet | Should -BeNullOrEmpty
        }

        It "Binds -Name as an alias of -Project" {
            # Counting a project that was deployed through -Project proves only that -Project
            # works, so the alias gets a fixture of its own and is the parameter that deploys it.
            $splatAliasPublish = @{
                SqlInstance = $ssisInstance
                Folder      = $deployFolder
                Name        = $aliasNameProject
                Path        = $projectFiles[$aliasNameProject]
            }
            $viaAlias = @(Publish-DbaSsisProject @splatAliasPublish)
            $viaAlias.Count | Should -Be 1
            $viaAlias[0].Name | Should -Be $aliasNameProject

            $splatAliasRead = @{
                SqlInstance  = $ssisInstance
                Database     = "SSISDB"
                Query        = "SELECT COUNT(*) AS deployed FROM [catalog].[projects] p JOIN [catalog].[folders] f ON f.folder_id = p.folder_id WHERE f.name = @folder AND p.name = @project"
                SqlParameter = @{
                    folder  = $deployFolder
                    project = $aliasNameProject
                }
            }
            (Invoke-DbaQuery @splatAliasRead).deployed | Should -Be 1
        }

        It "Deploying over an existing project keeps the old one as a version" {
            $splatFirst = @{
                SqlInstance = $ssisInstance
                Folder      = $deployFolder
                Project     = $versionProject
                Path        = $projectFiles[$versionProject]
            }
            $first = @(Publish-DbaSsisProject @splatFirst)[0]
            $second = @(Publish-DbaSsisProject @splatFirst)[0]
            $second.ProjectId | Should -Be $first.ProjectId
            $second.ObjectVersionLsn | Should -Not -Be $first.ObjectVersionLsn

            $splatVersionRead = @{
                SqlInstance  = $ssisInstance
                Database     = "SSISDB"
                Query        = "SELECT COUNT(*) AS versions FROM [catalog].[object_versions] v WHERE v.object_type = 20 AND v.object_id = @projectId"
                SqlParameter = @{ projectId = $first.ProjectId }
            }
            (Invoke-DbaQuery @splatVersionRead).versions | Should -BeGreaterThan 1
        }
    }

    Context "A deployment the catalog refuses" {
        It "Reports the reason the catalog only records in its operation log" {
            # The raised error says nothing but "query the operation_messages view for the
            # operation identifier N" - the text asserted here exists only in that view, so the
            # leg fails if the command reports the raised error without reading the log. It is
            # asserted on the warning because the module unwraps every wrapped exception back to
            # the SqlException, which leaves the message as the only place the reason can ride.
            $splatMismatch = @{
                SqlInstance     = $ssisInstance
                Folder          = $deployFolder
                Project         = $mismatchName
                Path            = $projectFiles[$simpleProject]
                EnableException = $false
                WarningVariable = "mismatchWarning"
                WarningAction   = "SilentlyContinue"
            }
            $refused = @(Publish-DbaSsisProject @splatMismatch)
            $refused.Count | Should -Be 0
            ($mismatchWarning -join " ") | Should -BeLike "*does not match the project name in the deployment file*"

            (Get-SsisProjectRow -Folder $deployFolder -Project $mismatchName).Count | Should -Be 0
        }

        It "Reports an unreadable project file the same way" {
            $splatCorrupt = @{
                SqlInstance     = $ssisInstance
                Folder          = $deployFolder
                Project         = $corruptProject
                Path            = $corruptPath
                EnableException = $false
                WarningVariable = "corruptWarning"
                WarningAction   = "SilentlyContinue"
            }
            $refused = @(Publish-DbaSsisProject @splatCorrupt)
            $refused.Count | Should -Be 0
            ($corruptWarning -join " ") | Should -BeLike "*Failed to open project stream*"
        }

        It "Throws under -EnableException when the catalog refuses" {
            $splatCorruptThrow = @{
                SqlInstance     = $ssisInstance
                Folder          = $deployFolder
                Project         = $corruptProject
                Path            = $corruptPath
                EnableException = $true
            }
            { Publish-DbaSsisProject @splatCorruptThrow } | Should -Throw "*Failed to deploy project*"
        }

        It "Refuses a folder that does not exist rather than creating it" {
            $splatMissingFolder = @{
                SqlInstance = $ssisInstance
                Folder      = $missingFolder
                Project     = $simpleProject
                Path        = $projectFiles[$simpleProject]
            }
            { Publish-DbaSsisProject @splatMissingFolder } | Should -Throw "*$missingFolder*"

            $splatFolderCheck = @{
                SqlInstance  = $ssisInstance
                Database     = "SSISDB"
                Query        = "SELECT COUNT(*) AS folders FROM [catalog].[folders] WHERE name = @folder"
                SqlParameter = @{ folder = $missingFolder }
            }
            (Invoke-DbaQuery @splatFolderCheck).folders | Should -Be 0
        }
    }

    Context "The project file is checked before anything connects" {
        It "Refuses a path that does not exist" {
            $splatAbsent = @{
                SqlInstance = $ssisInstance
                Folder      = $deployFolder
                Project     = $simpleProject
                Path        = $absentPath
            }
            { Publish-DbaSsisProject @splatAbsent } | Should -Throw "*does not exist*"
        }

        It "Refuses an empty file" {
            $splatEmpty = @{
                SqlInstance = $ssisInstance
                Folder      = $deployFolder
                Project     = $simpleProject
                Path        = $emptyPath
            }
            { Publish-DbaSsisProject @splatEmpty } | Should -Throw "*is empty*"
        }
    }

    Context "-WhatIf" {
        It "Reports without deploying the project" {
            $splatWhatIf = @{
                SqlInstance = $ssisInstance
                Folder      = $deployFolder
                Project     = $whatIfProject
                Path        = $projectFiles[$whatIfProject]
                WhatIf      = $true
            }
            $whatIfResult = @(Publish-DbaSsisProject @splatWhatIf)
            $whatIfResult.Count | Should -Be 0
            (Get-SsisProjectRow -Folder $deployFolder -Project $whatIfProject).Count | Should -Be 0
        }
    }

    Context "An instance with no SSIS catalog" {
        # InstanceSingle carries no SSISDB, so this exercises the presence check rather than
        # failing inside the catalog schema.
        It "Warns and returns nothing" {
            $splatNoCatalog = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Folder          = $deployFolder
                Project         = $simpleProject
                Path            = $projectFiles[$simpleProject]
                EnableException = $false
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $none = @(Publish-DbaSsisProject @splatNoCatalog)
            $none.Count | Should -Be 0
            ($warn -join " ") | Should -BeLike "*No SSIS catalog (SSISDB) found*"
        }

        It "Throws under -EnableException" {
            $splatNoCatalogThrow = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Folder          = $deployFolder
                Project         = $simpleProject
                Path            = $projectFiles[$simpleProject]
                EnableException = $true
            }
            { Publish-DbaSsisProject @splatNoCatalogThrow } | Should -Throw "*No SSIS catalog (SSISDB) found*"
        }
    }
}
