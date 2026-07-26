#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaSsisProject",
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
                "IncludeVersion",
                "IncludePackage",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        It "Should expose Name as an alias of Project" {
            (Get-Command $CommandName).Parameters["Project"].Aliases | Should -Contain "Name"
        }

        It "Should not declare ShouldProcess" {
            (Get-Command $CommandName).Parameters.Keys | Should -Not -Contain "WhatIf"
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        $ssisInstance  = $TestConfig.InstanceSsis
        $projectFolder = "dbatoolsci_ssisprojfolder"
        # The sibling names have the first as an exact prefix: a LIKE or wildcard implementation of
        # -Folder or -Project would return both, an exact-name implementation returns only the first.
        $siblingFolder = "dbatoolsci_ssisprojfolder2"
        $projectName   = "dbatoolsci_ssisproj"
        $siblingProject = "dbatoolsci_ssisproj2"
        $projectComment = "dbatools project read fixture"
        # The lab reference project, rebuilt by Initialize-MigrationLab, supplies the .ispac. A
        # hand-built one is refused by the deploy parser, and SSDT is not on the test runner.
        $referenceFolder  = "dbatoolsci_charfolder"
        $referenceProject = "dbatoolsci_charproject"

        $ssisServer = Connect-DbaInstance -SqlInstance $ssisInstance -Database SSISDB
        if (-not $ssisServer.ConnectionContext.IsOpen) {
            $ssisServer.ConnectionContext.Connect()
        }
        $ssisConnection = $ssisServer.ConnectionContext.SqlConnectionObject

        function Get-ReferenceIspac {
            $getProject = $ssisConnection.CreateCommand()
            $getProject.CommandText = "EXEC [catalog].[get_project] @folder_name = @folder, @project_name = @project"
            $null = $getProject.Parameters.AddWithValue("@folder", $referenceFolder)
            $null = $getProject.Parameters.AddWithValue("@project", $referenceProject)
            return , [byte[]]$getProject.ExecuteScalar()
        }

        function Copy-IspacUnderName {
            param(
                [byte[]]$Ispac,
                [string]$Name,
                [string]$Description
            )

            Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
            $sourceStream = New-Object -TypeName System.IO.MemoryStream -ArgumentList (, $Ispac)
            $sourceZip    = New-Object -TypeName System.IO.Compression.ZipArchive -ArgumentList $sourceStream, ([System.IO.Compression.ZipArchiveMode]::Read)

            $parts = New-Object -TypeName System.Collections.Specialized.OrderedDictionary
            foreach ($sourceEntry in $sourceZip.Entries) {
                $partReader = New-Object -TypeName System.IO.StreamReader -ArgumentList $sourceEntry.Open()
                $parts.Add($sourceEntry.FullName, $partReader.ReadToEnd())
                $partReader.Dispose()
            }
            $sourceZip.Dispose()
            $sourceStream.Dispose()

            # deploy_project insists the project name it is given equals the Name in the manifest,
            # so the rename happens inside the zip. Only the first match is rewritten - the package
            # metadata further down carries properties by the same names.
            $nameRegex        = New-Object -TypeName System.Text.RegularExpressions.Regex -ArgumentList '(?<open><SSIS:Property SSIS:Name="Name">)[^<]*(?<close></SSIS:Property>)'
            $descriptionRegex = New-Object -TypeName System.Text.RegularExpressions.Regex -ArgumentList '(?s)(?<open><SSIS:Property SSIS:Name="Description">).*?(?<close></SSIS:Property>)'
            $manifest = $parts["@Project.manifest"]
            $manifest = $nameRegex.Replace($manifest, "`${open}$Name`${close}", 1)
            $manifest = $descriptionRegex.Replace($manifest, "`${open}$Description`${close}", 1)
            $parts["@Project.manifest"] = $manifest

            $targetStream = New-Object -TypeName System.IO.MemoryStream
            $targetZip    = New-Object -TypeName System.IO.Compression.ZipArchive -ArgumentList $targetStream, ([System.IO.Compression.ZipArchiveMode]::Create), $true
            foreach ($partName in $parts.Keys) {
                $targetEntry = $targetZip.CreateEntry($partName)
                $partWriter  = New-Object -TypeName System.IO.StreamWriter -ArgumentList $targetEntry.Open(), (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false)
                $partWriter.Write($parts[$partName])
                $partWriter.Flush()
                $partWriter.Dispose()
            }
            $targetZip.Dispose()
            $rewritten = $targetStream.ToArray()
            $targetStream.Dispose()
            # Unary comma: PowerShell unrolls a returned byte[] into Object[], which SqlParameter refuses.
            return , $rewritten
        }

        function Publish-FixtureProject {
            param(
                [byte[]]$Ispac,
                [string]$FolderName,
                [string]$ProjectName
            )

            $deploy = $ssisConnection.CreateCommand()
            $deploy.CommandTimeout = 120
            $deploy.CommandText = "DECLARE @operationId bigint; EXEC [catalog].[deploy_project] @folder_name = @folder, @project_name = @project, @project_stream = @stream, @operation_id = @operationId OUTPUT;"
            $null = $deploy.Parameters.AddWithValue("@folder", $FolderName)
            $null = $deploy.Parameters.AddWithValue("@project", $ProjectName)
            $streamParameter = $deploy.Parameters.Add("@stream", [System.Data.SqlDbType]::VarBinary, -1)
            $streamParameter.Value = $Ispac
            $null = $deploy.ExecuteNonQuery()
        }

        $splatFolders = @{
            SqlInstance  = $ssisInstance
            Database     = "SSISDB"
            Query        = "
                IF NOT EXISTS (SELECT 1 FROM [catalog].[folders] WHERE name = @first)
                    EXEC [catalog].[create_folder] @folder_name = @first, @folder_id = NULL;
                IF NOT EXISTS (SELECT 1 FROM [catalog].[folders] WHERE name = @second)
                    EXEC [catalog].[create_folder] @folder_name = @second, @folder_id = NULL;"
            SqlParameter = @{
                first  = $projectFolder
                second = $siblingFolder
            }
        }
        Invoke-DbaQuery @splatFolders

        $referenceIspac = Get-ReferenceIspac
        Publish-FixtureProject -Ispac (Copy-IspacUnderName -Ispac $referenceIspac -Name $projectName -Description $projectComment) -FolderName $projectFolder -ProjectName $projectName
        Publish-FixtureProject -Ispac (Copy-IspacUnderName -Ispac $referenceIspac -Name $siblingProject -Description $projectComment) -FolderName $projectFolder -ProjectName $siblingProject
        # The same project name in a second folder: proves -Folder narrows and that FolderName is
        # the folder the project actually lives in, not the first folder the join happened to find.
        Publish-FixtureProject -Ispac (Copy-IspacUnderName -Ispac $referenceIspac -Name $projectName -Description $projectComment) -FolderName $siblingFolder -ProjectName $projectName
    }

    AfterAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        $splatTeardown = @{
            SqlInstance  = $TestConfig.InstanceSsis
            Database     = "SSISDB"
            Query        = "
                IF EXISTS (SELECT 1 FROM [catalog].[projects] p JOIN [catalog].[folders] f ON f.folder_id = p.folder_id WHERE p.name = @project AND f.name = @first)
                    EXEC [catalog].[delete_project] @folder_name = @first, @project_name = @project;
                IF EXISTS (SELECT 1 FROM [catalog].[projects] p JOIN [catalog].[folders] f ON f.folder_id = p.folder_id WHERE p.name = @sibling AND f.name = @first)
                    EXEC [catalog].[delete_project] @folder_name = @first, @project_name = @sibling;
                IF EXISTS (SELECT 1 FROM [catalog].[projects] p JOIN [catalog].[folders] f ON f.folder_id = p.folder_id WHERE p.name = @project AND f.name = @second)
                    EXEC [catalog].[delete_project] @folder_name = @second, @project_name = @project;
                IF EXISTS (SELECT 1 FROM [catalog].[folders] WHERE name = @first)
                    EXEC [catalog].[delete_folder] @folder_name = @first;
                IF EXISTS (SELECT 1 FROM [catalog].[folders] WHERE name = @second)
                    EXEC [catalog].[delete_folder] @folder_name = @second;"
            SqlParameter = @{
                first   = "dbatoolsci_ssisprojfolder"
                second  = "dbatoolsci_ssisprojfolder2"
                project = "dbatoolsci_ssisproj"
                sibling = "dbatoolsci_ssisproj2"
            }
        }
        Invoke-DbaQuery @splatTeardown
    }

    Context "Reading the catalog" {
        It "Returns every fixture project when unfiltered" {
            $allProjects = @(Get-DbaSsisProject -SqlInstance $ssisInstance)
            $allProjects.Name | Should -Contain $projectName
            $allProjects.Name | Should -Contain $siblingProject
        }

        It "Returns the verified catalog.projects columns" {
            $single = @(Get-DbaSsisProject -SqlInstance $ssisInstance -Folder $projectFolder -Project $projectName)
            $single.Count | Should -Be 1
            $single[0].Name | Should -Be $projectName
            $single[0].FolderName | Should -Be $projectFolder
            $single[0].Description | Should -Be $projectComment
            $single[0].ProjectId | Should -BeGreaterThan 0
            $single[0].FolderId | Should -BeGreaterThan 0
            $single[0].ObjectVersionLsn | Should -BeGreaterThan 0
            $single[0].ProjectFormatVersion | Should -Not -BeNullOrEmpty
            $single[0].DeployedByName | Should -Not -BeNullOrEmpty
            $single[0].LastDeployedTime | Should -Not -BeNullOrEmpty
            $single[0].ValidationStatus | Should -Not -BeNullOrEmpty
        }

        It "Accepts the instance from the pipeline" {
            $piped = @($ssisInstance | Get-DbaSsisProject -Folder $projectFolder -Project $projectName)
            $piped.Count | Should -Be 1
            $piped[0].Name | Should -Be $projectName
        }

        It "Processes every piped instance record" {
            $repeated = @($ssisInstance, $ssisInstance | Get-DbaSsisProject -Folder $projectFolder -Project $projectName)
            $repeated.Count | Should -Be 2
        }

        It "Accepts several project names at once" {
            $both = @(Get-DbaSsisProject -SqlInstance $ssisInstance -Folder $projectFolder -Project $projectName, $siblingProject)
            $both.Count | Should -Be 2
        }

        It "Binds -Name as an alias of -Project" {
            $viaAlias = @(Get-DbaSsisProject -SqlInstance $ssisInstance -Folder $projectFolder -Name $projectName)
            $viaAlias.Count | Should -Be 1
            $viaAlias[0].Name | Should -Be $projectName
        }
    }

    Context "-Project and -Folder are exact name lists" {
        It "Does not return the project whose name merely starts with the requested one" {
            $exact = @(Get-DbaSsisProject -SqlInstance $ssisInstance -Folder $projectFolder -Project $projectName)
            $exact.Name | Should -Not -Contain $siblingProject
        }

        It "Treats a LIKE metacharacter in -Project as a literal, returning nothing" {
            $withPercent = @(Get-DbaSsisProject -SqlInstance $ssisInstance -Project "$projectName%")
            $withPercent.Count | Should -Be 0
        }

        It "Treats a wildcard in -Project as a literal, returning nothing" {
            $withStar = @(Get-DbaSsisProject -SqlInstance $ssisInstance -Project "$projectName*")
            $withStar.Count | Should -Be 0
        }

        It "Does not return projects from the folder whose name merely starts with the requested one" {
            $oneFolder = @(Get-DbaSsisProject -SqlInstance $ssisInstance -Folder $projectFolder)
            $oneFolder.Count | Should -Be 2
            $oneFolder.FolderName | Should -Not -Contain $siblingFolder
        }

        It "Reports the folder each project actually lives in" {
            $sameNameTwice = @(Get-DbaSsisProject -SqlInstance $ssisInstance -Folder $projectFolder, $siblingFolder -Project $projectName)
            $sameNameTwice.Count | Should -Be 2
            $sameNameTwice.FolderName | Should -Contain $projectFolder
            $sameNameTwice.FolderName | Should -Contain $siblingFolder
            ($sameNameTwice | Where-Object FolderName -eq $siblingFolder).Name | Should -Be $projectName
        }
    }

    Context "-IncludePackage" {
        It "Leaves the Packages property off by default" {
            $plain = @(Get-DbaSsisProject -SqlInstance $ssisInstance -Folder $projectFolder -Project $projectName)[0]
            $plain.PSObject.Properties.Name | Should -Not -Contain "Packages"
        }

        It "Attaches the packages the project deployed" {
            $withPackages = @(Get-DbaSsisProject -SqlInstance $ssisInstance -Folder $projectFolder -Project $projectName -IncludePackage)[0]
            $withPackages.Packages.Count | Should -Be 1
            $withPackages.Packages[0].Name | Should -Be "dbatoolsci_charpackage.dtsx"
            $withPackages.Packages[0].EntryPoint | Should -BeTrue
            $withPackages.Packages[0].PackageId | Should -BeGreaterThan 0
        }

        It "Gives each project only its own packages" {
            $multiple = @(Get-DbaSsisProject -SqlInstance $ssisInstance -Folder $projectFolder -IncludePackage)
            $multiple.Count | Should -Be 2
            foreach ($project in $multiple) {
                $project.Packages.Count | Should -Be 1
                $project.Packages[0].ProjectId | Should -Be $project.ProjectId
            }
        }
    }

    Context "-IncludeVersion" {
        It "Leaves the Versions property off by default" {
            $plain = @(Get-DbaSsisProject -SqlInstance $ssisInstance -Folder $projectFolder -Project $projectName)[0]
            $plain.PSObject.Properties.Name | Should -Not -Contain "Versions"
        }

        It "Attaches the project's deployment history" {
            $withVersions = @(Get-DbaSsisProject -SqlInstance $ssisInstance -Folder $projectFolder -Project $projectName -IncludeVersion)[0]
            $withVersions.Versions.Count | Should -BeGreaterThan 0
            $withVersions.Versions[0].Name | Should -Be $projectName
            $withVersions.Versions[0].ObjectVersionLsn | Should -BeGreaterThan 0
            $withVersions.Versions[0].CreatedBy | Should -Not -BeNullOrEmpty
        }

        It "Gives each project only its own versions" {
            $multiple = @(Get-DbaSsisProject -SqlInstance $ssisInstance -Folder $projectFolder -IncludeVersion)
            $multiple.Count | Should -Be 2
            foreach ($project in $multiple) {
                $project.Versions.Count | Should -BeGreaterThan 0
                foreach ($version in $project.Versions) {
                    $version.ProjectId | Should -Be $project.ProjectId
                }
            }
        }
    }

    Context "Output decoration" {
        It "Carries the instance property triple" {
            $decorated = @(Get-DbaSsisProject -SqlInstance $ssisInstance -Folder $projectFolder -Project $projectName)[0]
            $decorated.ComputerName | Should -Not -BeNullOrEmpty
            $decorated.InstanceName | Should -Not -BeNullOrEmpty
            $decorated.SqlInstance | Should -Not -BeNullOrEmpty
        }

        It "Carries the dbatools.SsisProject type name" {
            $decorated = @(Get-DbaSsisProject -SqlInstance $ssisInstance -Folder $projectFolder -Project $projectName)[0]
            $decorated.PSObject.TypeNames[0] | Should -Be "dbatools.SsisProject"
        }

        It "Keeps ProjectId on the object but off the default view" {
            $decorated = @(Get-DbaSsisProject -SqlInstance $ssisInstance -Folder $projectFolder -Project $projectName)[0]
            $displaySet = $decorated.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $displaySet | Should -Contain "FolderName"
            $displaySet | Should -Contain "LastDeployedTime"
            $displaySet | Should -Not -Contain "ProjectId"
            $decorated.PSObject.Properties.Name | Should -Contain "ProjectId"
        }
    }

    Context "An instance with no SSIS catalog" {
        # InstanceSingle carries no SSISDB, so this exercises the presence check rather than
        # failing inside the catalog schema.
        It "Warns and returns nothing" {
            $splatNoCatalog = @{
                SqlInstance     = $TestConfig.InstanceSingle
                EnableException = $false
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $none = @(Get-DbaSsisProject @splatNoCatalog)
            $none.Count | Should -Be 0
            ($warn -join " ") | Should -BeLike "*No SSIS catalog (SSISDB) found*"
        }

        It "Throws under -EnableException" {
            { Get-DbaSsisProject -SqlInstance $TestConfig.InstanceSingle -EnableException } | Should -Throw "*No SSIS catalog (SSISDB) found*"
        }
    }
}
