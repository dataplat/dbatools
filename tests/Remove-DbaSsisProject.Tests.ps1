#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaSsisProject",
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
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        It "Should declare ShouldProcess at High impact" {
            (Get-Command $CommandName).Parameters.Keys | Should -Contain "WhatIf"
            $cmdletBinding = (Get-Command $CommandName).ImplementingType.GetCustomAttributes([System.Management.Automation.CmdletAttribute], $false)[0]
            $cmdletBinding.SupportsShouldProcess | Should -BeTrue
            $cmdletBinding.ConfirmImpact | Should -Be "High"
        }

        It "Should keep SqlInstance off the pipeline and out of mandatory" {
            # Both halves are load-bearing where -InputObject also takes pipeline input. Mandatory
            # makes the -InputObject path unbindable outright, and a second ValueFromPipeline
            # parameter double-binds, so an ordinary instance pipeline lands in -InputObject.
            $sqlInstance = (Get-Command $CommandName).Parameters["SqlInstance"].Attributes | Where-Object { $PSItem -is [System.Management.Automation.ParameterAttribute] }
            $sqlInstance.Mandatory | Should -BeFalse
            $sqlInstance.ValueFromPipeline | Should -BeFalse
            $inputObject = (Get-Command $CommandName).Parameters["InputObject"].Attributes | Where-Object { $PSItem -is [System.Management.Automation.ParameterAttribute] }
            $inputObject.ValueFromPipeline | Should -BeTrue
        }
    }

    Context "Refusals that settle before anything connects" {
        It "Refuses a call with no instance and no input object" {
            { Remove-DbaSsisProject -Project "anything" -EnableException } | Should -Throw "*either -SqlInstance or an Input Object*"
        }

        It "Refuses an instance with no project named, without reaching the server" {
            # The instance here is unreachable, so a command that had lost the guard would fail
            # with a connection error instead - which is how this leg tells "refused" from "tried
            # and could not", and so proves no catalog.delete_project call was ever issued.
            $splatNoTarget = @{
                SqlInstance     = $TestConfig.InstanceUnreachable
                EnableException = $true
            }
            { Remove-DbaSsisProject @splatNoTarget } | Should -Throw "*You must supply -Project, or pipe in projects from Get-DbaSsisProject*"
        }

        It "Refuses a folder with no project named, without reaching the server" {
            # -Folder is not a target. A folder with no project named still means every project in
            # it, so the guard is on -Project specifically and -Folder does not satisfy it.
            $splatFolderOnly = @{
                SqlInstance     = $TestConfig.InstanceUnreachable
                Folder          = "anything"
                EnableException = $true
            }
            { Remove-DbaSsisProject @splatFolderOnly } | Should -Throw "*You must supply -Project*"
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        $ssisInstance   = $TestConfig.InstanceSsis
        $primaryFolder  = "dbatoolsci_rmprojfolder1"
        $secondFolder   = "dbatoolsci_rmprojfolder2"
        $targetProject  = "dbatoolsci_rmprojtarget"
        $whatIfProject  = "dbatoolsci_rmprojwhatif"
        $guardProject   = "dbatoolsci_rmprojguard"
        $pipeProjectA   = "dbatoolsci_rmprojpipea"
        $pipeProjectB   = "dbatoolsci_rmprojpipeb"
        $sharedProject  = "dbatoolsci_rmprojshared"
        $twinProject    = "dbatoolsci_rmprojtwin"
        $prefixProject  = "dbatoolsci_rmprojpre"
        $prefixSibling  = "dbatoolsci_rmprojpre_extra"
        $primaryProjects = @($targetProject, $whatIfProject, $guardProject, $pipeProjectA, $pipeProjectB, $sharedProject, $twinProject, $prefixProject, $prefixSibling)
        $secondProjects = @($sharedProject, $twinProject)

        # An .ispac is an OPC zip of four text parts, so the suite builds its own rather than
        # depending on a binary fixture or on the SSIS design-time assemblies, which ship only for
        # Windows PowerShell. The project name inside the manifest is what the catalog records.
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

        function Remove-SsisFolderFixture {
            param($FolderName)
            # A folder will not drop while it still holds projects, so a cleanup that only drops
            # the folder leaks both.
            $splatProjectDrop = @{
                SqlInstance     = $TestConfig.InstanceSsis
                Database        = "SSISDB"
                Query           = "DECLARE @name sysname; DECLARE leftovers CURSOR LOCAL FAST_FORWARD FOR SELECT p.name FROM [catalog].[projects] p JOIN [catalog].[folders] f ON f.folder_id = p.folder_id WHERE f.name = @folder; OPEN leftovers; FETCH NEXT FROM leftovers INTO @name; WHILE @@FETCH_STATUS = 0 BEGIN EXEC [catalog].[delete_project] @folder_name = @folder, @project_name = @name; FETCH NEXT FROM leftovers INTO @name; END; CLOSE leftovers; DEALLOCATE leftovers;"
                SqlParameter    = @{ folder = $FolderName }
                EnableException = $false
            }
            Invoke-DbaQuery @splatProjectDrop

            $splatFolderDrop = @{
                SqlInstance     = $TestConfig.InstanceSsis
                Database        = "SSISDB"
                Query           = "IF EXISTS (SELECT 1 FROM [catalog].[folders] WHERE name = @folder) EXEC [catalog].[delete_folder] @folder_name = @folder;"
                SqlParameter    = @{ folder = $FolderName }
                EnableException = $false
            }
            Invoke-DbaQuery @splatFolderDrop
        }

        # A leftover from an interrupted run would turn the deploy legs into redeploys and leave
        # the ambiguity leg matching three folders instead of two.
        Remove-SsisFolderFixture -FolderName $primaryFolder
        Remove-SsisFolderFixture -FolderName $secondFolder

        foreach ($fixtureFolder in @($primaryFolder, $secondFolder)) {
            $splatNewFolder = @{
                SqlInstance = $ssisInstance
                Folder      = $fixtureFolder
                Description = "remove project fixture"
            }
            $null = New-DbaSsisFolder @splatNewFolder
        }

        # A fresh directory of this run's own, rather than predictable names in the shared temp
        # root: two runs at once would otherwise write each other's fixture files.
        $removeRunId = [guid]::NewGuid().ToString("n")
        $projectRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "dbatoolsci_rmproj_$removeRunId"
        $null = New-Item -Path $projectRoot -ItemType Directory -Force

        foreach ($deployment in @(@($primaryFolder, $primaryProjects), @($secondFolder, $secondProjects))) {
            foreach ($projectName in $deployment[1]) {
                $projectPath = Join-Path -Path $projectRoot -ChildPath "$projectName.ispac"
                if (-not (Test-Path -LiteralPath $projectPath)) {
                    New-SsisProjectFile -ProjectName $projectName -PackageName "$projectName`_package" -Path $projectPath
                }

                $splatPublish = @{
                    SqlInstance = $ssisInstance
                    Folder      = $deployment[0]
                    Project     = $projectName
                    Path        = $projectPath
                }
                $null = Publish-DbaSsisProject @splatPublish
            }
        }

        # Every later assertion of the form "it is still there" is worthless if the deploys did not
        # land, so the run refuses to start rather than proving nothing quietly.
        foreach ($deployment in @(@($primaryFolder, $primaryProjects), @($secondFolder, $secondProjects))) {
            foreach ($projectName in $deployment[1]) {
                if ((Get-SsisProjectRow -Folder $deployment[0] -Project $projectName).Count -ne 1) {
                    throw "Fixture project $projectName was not deployed to $($deployment[0]) on $ssisInstance - the suite cannot prove a removal against a catalog that never held it."
                }
            }
        }
    }

    AfterAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        # Folder literals rather than the variables so cleanup still runs when BeforeAll died
        # before setting them.
        Remove-SsisFolderFixture -FolderName "dbatoolsci_rmprojfolder1"
        Remove-SsisFolderFixture -FolderName "dbatoolsci_rmprojfolder2"

        if ($projectRoot -and (Test-Path -LiteralPath $projectRoot)) {
            Remove-Item -LiteralPath $projectRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Removing a project" {
        It "Removes the project and reports it in the read command's shape" {
            $read = @(Get-DbaSsisProject -SqlInstance $ssisInstance -Folder $primaryFolder -Project $targetProject)[0]
            $splatRemove = @{
                SqlInstance = $ssisInstance
                Folder      = $primaryFolder
                Project     = $targetProject
                Confirm     = $false
            }
            $removed = @(Remove-DbaSsisProject @splatRemove)
            $removed.Count | Should -Be 1
            $removed[0].Name | Should -Be $targetProject
            $removed[0].FolderName | Should -Be $primaryFolder
            $removed[0].Status | Should -Be "Dropped"
            $removed[0].ProjectId | Should -Be $read.ProjectId
            $removed[0].PSObject.TypeNames[0] | Should -Be "dbatools.SsisProject"
            (Get-SsisProjectRow -Folder $primaryFolder -Project $targetProject).Count | Should -Be 0
        }

        It "Reports a project that is not there and removes nothing" {
            $splatMissing = @{
                SqlInstance     = $ssisInstance
                Folder          = $primaryFolder
                Project         = "dbatoolsci_rmprojabsent"
                EnableException = $false
                WarningVariable = "missingWarnings"
                WarningAction   = "SilentlyContinue"
                Confirm         = $false
            }
            $none = @(Remove-DbaSsisProject @splatMissing)
            $none.Count | Should -Be 0
            ($missingWarnings -join " ") | Should -BeLike "*does not exist*"
        }

        It "Leaves a project whose name merely starts with the requested one" {
            $splatPrefix = @{
                SqlInstance = $ssisInstance
                Folder      = $primaryFolder
                Project     = $prefixProject
                Confirm     = $false
            }
            $removed = @(Remove-DbaSsisProject @splatPrefix)
            $removed.Count | Should -Be 1
            (Get-SsisProjectRow -Folder $primaryFolder -Project $prefixProject).Count | Should -Be 0
            (Get-SsisProjectRow -Folder $primaryFolder -Project $prefixSibling).Count | Should -Be 1
        }
    }

    Context "The target guard" {
        It "Refuses an instance and a folder with no project named, and issues no delete" {
            # -Folder with no project reads as "every project in that folder". The assertion that
            # matters is not the message but the catalog afterwards: the folder's projects are all
            # still there, so no catalog.delete_project call was made.
            $before = @(Get-DbaSsisProject -SqlInstance $ssisInstance -Folder $primaryFolder).Name
            $before.Count | Should -BeGreaterThan 0
            $splatNoTarget = @{
                SqlInstance     = $ssisInstance
                Folder          = $primaryFolder
                EnableException = $false
                WarningVariable = "guardWarnings"
                WarningAction   = "SilentlyContinue"
                Confirm         = $false
            }
            $none = @(Remove-DbaSsisProject @splatNoTarget)
            $none.Count | Should -Be 0
            ($guardWarnings -join " ") | Should -BeLike "*You must supply -Project*"
            $after = @(Get-DbaSsisProject -SqlInstance $ssisInstance -Folder $primaryFolder).Name
            Compare-Object -ReferenceObject $before -DifferenceObject $after | Should -BeNullOrEmpty
            $after | Should -Contain $guardProject
        }
    }

    Context "-WhatIf" {
        It "Reports without removing anything" {
            $splatWhatIf = @{
                SqlInstance = $ssisInstance
                Folder      = $primaryFolder
                Project     = $whatIfProject
                WhatIf      = $true
            }
            $whatIfResult = @(Remove-DbaSsisProject @splatWhatIf)
            $whatIfResult.Count | Should -Be 0
            (Get-SsisProjectRow -Folder $primaryFolder -Project $whatIfProject).Count | Should -Be 1
        }
    }

    Context "A project name that lives in more than one folder" {
        It "Names the folders and removes none of them" {
            # Project names are unique only within a folder. Picking one would be a guess and
            # removing both would be a far bigger operation than the caller asked for, so the
            # surviving row in each folder is the assertion, not the message.
            $splatAmbiguous = @{
                SqlInstance     = $ssisInstance
                Project         = $sharedProject
                EnableException = $false
                WarningVariable = "ambiguousWarnings"
                WarningAction   = "SilentlyContinue"
                Confirm         = $false
            }
            $none = @(Remove-DbaSsisProject @splatAmbiguous)
            $none.Count | Should -Be 0
            ($ambiguousWarnings -join " ") | Should -BeLike "*exists in more than one folder*"
            ($ambiguousWarnings -join " ") | Should -BeLike "*$primaryFolder*"
            ($ambiguousWarnings -join " ") | Should -BeLike "*$secondFolder*"
            (Get-SsisProjectRow -Folder $primaryFolder -Project $sharedProject).Count | Should -Be 1
            (Get-SsisProjectRow -Folder $secondFolder -Project $sharedProject).Count | Should -Be 1
        }

        It "Throws the same refusal under -EnableException" {
            $splatAmbiguousThrow = @{
                SqlInstance     = $ssisInstance
                Project         = $sharedProject
                EnableException = $true
                Confirm         = $false
            }
            { Remove-DbaSsisProject @splatAmbiguousThrow } | Should -Throw "*exists in more than one folder*"
            (Get-SsisProjectRow -Folder $primaryFolder -Project $sharedProject).Count | Should -Be 1
        }

        It "Removes only the copy in the folder that was named" {
            # Same ambiguous name, disambiguated: the twin in the other folder is what proves
            # -Folder scoped the removal rather than the command picking the first match.
            $splatScoped = @{
                SqlInstance = $ssisInstance
                Folder      = $primaryFolder
                Project     = $twinProject
                Confirm     = $false
            }
            $removed = @(Remove-DbaSsisProject @splatScoped)
            $removed.Count | Should -Be 1
            $removed[0].FolderName | Should -Be $primaryFolder
            (Get-SsisProjectRow -Folder $primaryFolder -Project $twinProject).Count | Should -Be 0
            (Get-SsisProjectRow -Folder $secondFolder -Project $twinProject).Count | Should -Be 1
        }
    }

    Context "Two records in one pipeline" {
        It "Removes the second piped project as well as the first" {
            # Removal streams per record, so what record 2 does is decided entirely on the second
            # record - record 1 alone proves none of it.
            $firstObject = @(Get-DbaSsisProject -SqlInstance $ssisInstance -Folder $primaryFolder -Project $pipeProjectA)[0]
            $secondObject = @(Get-DbaSsisProject -SqlInstance $ssisInstance -Folder $primaryFolder -Project $pipeProjectB)[0]
            $removed = @($firstObject, $secondObject | Remove-DbaSsisProject -Confirm:$false)
            $removed.Count | Should -Be 2
            $removed.Name | Should -Contain $pipeProjectA
            $removed.Name | Should -Contain $pipeProjectB
            @($removed | Where-Object Status -NE "Dropped").Count | Should -Be 0
            (Get-SsisProjectRow -Folder $primaryFolder -Project $pipeProjectA).Count | Should -Be 0
            (Get-SsisProjectRow -Folder $primaryFolder -Project $pipeProjectB).Count | Should -Be 0
        }
    }

    Context "-InputObject" {
        It "Refuses an object that is not a catalog project" {
            $imposter = [PSCustomObject]@{
                SqlInstance = $ssisInstance
                FolderName  = $primaryFolder
                Name        = $guardProject
            }
            $splatImposter = @{
                EnableException = $false
                WarningVariable = "imposterWarnings"
                WarningAction   = "SilentlyContinue"
                Confirm         = $false
            }
            $refused = @($imposter | Remove-DbaSsisProject @splatImposter)
            $refused.Count | Should -Be 0
            ($imposterWarnings -join " ") | Should -BeLike "*not a dbatools.SsisProject*"
            (Get-SsisProjectRow -Folder $primaryFolder -Project $guardProject).Count | Should -Be 1
        }
    }

    Context "An instance with no SSIS catalog" {
        It "Warns and returns nothing" {
            $splatNoCatalog = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Project         = $guardProject
                EnableException = $false
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                Confirm         = $false
            }
            $none = @(Remove-DbaSsisProject @splatNoCatalog)
            $none.Count | Should -Be 0
            ($warn -join " ") | Should -BeLike "*No SSIS catalog (SSISDB) found*"
        }

        It "Throws on the same instance under -EnableException" {
            $splatNoCatalogThrow = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Project         = $guardProject
                EnableException = $true
                Confirm         = $false
            }
            { Remove-DbaSsisProject @splatNoCatalogThrow } | Should -Throw "*No SSIS catalog (SSISDB) found*"
        }
    }
}
