#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Start-DbaSsisExecution",
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
                "Package",
                "Environment",
                "EnvironmentFolder",
                "Parameter",
                "ProjectParameter",
                "LoggingLevel",
                "Timeout",
                "Synchronous",
                "Use32BitRuntime",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        It "Should declare ShouldProcess" {
            (Get-Command $CommandName).Parameters.Keys | Should -Contain "WhatIf"
        }

        It "Should keep the two parameter scopes apart" {
            # One hashtable could not say which scope a name belongs to, and the catalog lets a
            # project parameter and a package parameter share a name.
            (Get-Command $CommandName).Parameters["Parameter"].ParameterType.FullName | Should -Be "System.Collections.Hashtable"
            (Get-Command $CommandName).Parameters["ProjectParameter"].ParameterType.FullName | Should -Be "System.Collections.Hashtable"
        }

        It "Should take Synchronous and Use32BitRuntime as switches" {
            (Get-Command $CommandName).Parameters["Synchronous"].ParameterType.FullName | Should -Be "System.Management.Automation.SwitchParameter"
            (Get-Command $CommandName).Parameters["Use32BitRuntime"].ParameterType.FullName | Should -Be "System.Management.Automation.SwitchParameter"
        }
    }

    Context "A timeout on a call that never waits" {
        It "Refuses -Timeout without -Synchronous" {
            # This refuses in BeginProcessing, so the unreachable instance name is never dialled.
            $splatTimeoutOnly = @{
                SqlInstance     = "dbatoolsci_nosuchhost_ssisexec"
                Folder          = "dbatoolsci_execfolder1"
                Project         = "dbatoolsci_execproject1"
                Package         = "dbatoolsci_execpackage1.dtsx"
                Timeout         = 30
                EnableException = $true
            }
            { Start-DbaSsisExecution @splatTimeoutOnly } | Should -Throw "*-Timeout applies only with -Synchronous*"
        }

        It "Refuses a -Timeout of zero or less" {
            # Zero would wait exactly one poll of a package that has had no time to finish, so every
            # run would report a timeout it never really had.
            foreach ($badTimeout in @(0, -30)) {
                $splatBadTimeout = @{
                    SqlInstance     = "dbatoolsci_nosuchhost_ssisexec"
                    Folder          = "dbatoolsci_execfolder1"
                    Project         = "dbatoolsci_execproject1"
                    Package         = "dbatoolsci_execpackage1.dtsx"
                    Timeout         = $badTimeout
                    Synchronous     = $true
                    EnableException = $true
                }
                { Start-DbaSsisExecution @splatBadTimeout } | Should -Throw "*-Timeout must be greater than zero seconds, not $badTimeout*"
            }
        }

        It "Refuses -EnvironmentFolder without -Environment" {
            # Ignoring it would start the package on its design-time values and report success, so
            # the caller learns nothing; the refusal has to come before the execution is created.
            $splatFolderOnly = @{
                SqlInstance       = "dbatoolsci_nosuchhost_ssisexec"
                Folder            = "dbatoolsci_execfolder1"
                Project           = "dbatoolsci_execproject1"
                Package           = "dbatoolsci_execpackage1.dtsx"
                EnvironmentFolder = "dbatoolsci_execdecoy1"
                EnableException   = $true
            }
            { Start-DbaSsisExecution @splatFolderOnly } | Should -Throw "*-EnvironmentFolder names the folder to look for -Environment in and does nothing on its own*"
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        $ssisInstance     = $TestConfig.InstanceSsis
        $executionFolder  = "dbatoolsci_execfolder1"
        $executionProject = "dbatoolsci_execproject1"
        $executionPackage = "dbatoolsci_execpackage1"
        $executionEnvironment = "dbatoolsci_execenv1"
        # Same environment name, different folder. The catalog allows a project to reference both,
        # and only a name collision proves the unqualified lookup picks the one beside the project.
        $decoyFolder = "dbatoolsci_execdecoy1"
        $packageParameterName = "PackageNumber"
        $projectParameterName = "ProjectNumber"

        function New-SsisParameterizedProjectFile {
            param($ProjectName, $PackageName, $Path)

            if (-not ("System.IO.Compression.ZipArchive" -as [type])) {
                Add-Type -AssemblyName "System.IO.Compression"
            }

            # The two halves of an .ispac spell a parameter's type in different dialects. Inside
            # the .dtsx, DTS:DataType is the VarEnum code, where 3 is Int32. In the manifest and in
            # Project.params, DataType is the System.TypeCode, where 3 is Boolean and 9 is Int32.
            # Using one number in both places deploys a parameter typed Object, and the execution
            # then fails on "incompatible data types" only once the package actually runs.
            $packageXml = @"
<?xml version="1.0"?>
<DTS:Executable xmlns:DTS="www.microsoft.com/SqlServer/Dts" DTS:refId="Package" DTS:CreationName="Microsoft.Package" DTS:DTSID="{21D1A8D9-CC5B-4F22-9C7E-08890C43B547}" DTS:ExecutableType="Microsoft.Package" DTS:LocaleID="1033" DTS:ObjectName="$PackageName" DTS:VersionGUID="{C7CC7047-831E-4853-B30A-6C22843AC290}">
  <DTS:Property DTS:Name="PackageFormatVersion">8</DTS:Property>
  <DTS:PackageParameters>
    <DTS:PackageParameter DTS:CreationName="" DTS:DataType="3" DTS:Description="" DTS:DTSID="{31D1A8D9-CC5B-4F22-9C7E-08890C43B547}" DTS:ObjectName="PackageNumber">
      <DTS:Property DTS:Name="ParameterValue" DTS:DataType="3">1</DTS:Property>
    </DTS:PackageParameter>
  </DTS:PackageParameters>
  <DTS:Variables />
  <DTS:Executables />
</DTS:Executable>
"@

            $parametersXml = @"
<?xml version="1.0"?>
<SSIS:Parameters xmlns:SSIS="www.microsoft.com/SqlServer/SSIS">
  <SSIS:Parameter SSIS:Name="ProjectNumber">
    <SSIS:Properties>
      <SSIS:Property SSIS:Name="ID">{41D1A8D9-CC5B-4F22-9C7E-08890C43B547}</SSIS:Property>
      <SSIS:Property SSIS:Name="CreationName"></SSIS:Property>
      <SSIS:Property SSIS:Name="Description"></SSIS:Property>
      <SSIS:Property SSIS:Name="IncludeInDebugDump">0</SSIS:Property>
      <SSIS:Property SSIS:Name="Required">0</SSIS:Property>
      <SSIS:Property SSIS:Name="Sensitive">0</SSIS:Property>
      <SSIS:Property SSIS:Name="Value">2</SSIS:Property>
      <SSIS:Property SSIS:Name="DataType">9</SSIS:Property>
      <SSIS:Property SSIS:Name="Name">ProjectNumber</SSIS:Property>
    </SSIS:Properties>
  </SSIS:Parameter>
</SSIS:Parameters>
"@

            $manifestXml = @"
<SSIS:Project SSIS:ProtectionLevel="DontSaveSensitive" xmlns:SSIS="www.microsoft.com/SqlServer/SSIS">
  <SSIS:Properties>
    <SSIS:Property SSIS:Name="ID">{510f1219-5a15-4d9f-8736-08541cd40b6e}</SSIS:Property>
    <SSIS:Property SSIS:Name="Name">$ProjectName</SSIS:Property>
    <SSIS:Property SSIS:Name="VersionMajor">1</SSIS:Property>
    <SSIS:Property SSIS:Name="VersionMinor">0</SSIS:Property>
    <SSIS:Property SSIS:Name="VersionBuild">0</SSIS:Property>
    <SSIS:Property SSIS:Name="VersionComments"></SSIS:Property>
    <SSIS:Property SSIS:Name="CreationDate">2026-08-03T15:40:56.683402+02:00</SSIS:Property>
    <SSIS:Property SSIS:Name="CreatorName">dbatools</SSIS:Property>
    <SSIS:Property SSIS:Name="CreatorComputerName">dbatools</SSIS:Property>
    <SSIS:Property SSIS:Name="Description"></SSIS:Property>
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
          <SSIS:Property SSIS:Name="ID">{21D1A8D9-CC5B-4F22-9C7E-08890C43B547}</SSIS:Property>
          <SSIS:Property SSIS:Name="Name">$PackageName</SSIS:Property>
          <SSIS:Property SSIS:Name="VersionMajor">1</SSIS:Property>
          <SSIS:Property SSIS:Name="VersionMinor">0</SSIS:Property>
          <SSIS:Property SSIS:Name="VersionBuild">0</SSIS:Property>
          <SSIS:Property SSIS:Name="VersionComments"></SSIS:Property>
          <SSIS:Property SSIS:Name="VersionGUID">{C7CC7047-831E-4853-B30A-6C22843AC290}</SSIS:Property>
          <SSIS:Property SSIS:Name="PackageFormatVersion">8</SSIS:Property>
          <SSIS:Property SSIS:Name="Description"></SSIS:Property>
          <SSIS:Property SSIS:Name="ProtectionLevel">0</SSIS:Property>
        </SSIS:Properties>
        <SSIS:Parameters>
          <SSIS:Parameter SSIS:Name="PackageNumber">
            <SSIS:Properties>
              <SSIS:Property SSIS:Name="ID">{31D1A8D9-CC5B-4F22-9C7E-08890C43B547}</SSIS:Property>
              <SSIS:Property SSIS:Name="CreationName"></SSIS:Property>
              <SSIS:Property SSIS:Name="Description"></SSIS:Property>
              <SSIS:Property SSIS:Name="IncludeInDebugDump">0</SSIS:Property>
              <SSIS:Property SSIS:Name="Required">0</SSIS:Property>
              <SSIS:Property SSIS:Name="Sensitive">0</SSIS:Property>
              <SSIS:Property SSIS:Name="Value">1</SSIS:Property>
              <SSIS:Property SSIS:Name="DataType">9</SSIS:Property>
              <SSIS:Property SSIS:Name="Name">PackageNumber</SSIS:Property>
            </SSIS:Properties>
          </SSIS:Parameter>
        </SSIS:Parameters>
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

        function New-SsisProcessProjectFile {
            param($ProjectName, $PackageName, $Path, $Executable, $Arguments)

            if (-not ("System.IO.Compression.ZipArchive" -as [type])) {
                Add-Type -AssemblyName "System.IO.Compression"
            }

            # An Execute Process task is the one task type that needs no connection manager, so the
            # package it lives in stays hand-writable. What it runs decides how the execution ends:
            # a process that takes a known length of time, or one that is not there at all.
            $packageGuid = [guid]::NewGuid().ToString("B").ToUpper()
            $taskGuid = [guid]::NewGuid().ToString("B").ToUpper()
            $packageXml = @"
<?xml version="1.0"?>
<DTS:Executable xmlns:DTS="www.microsoft.com/SqlServer/Dts" DTS:refId="Package" DTS:CreationName="Microsoft.Package" DTS:DTSID="$packageGuid" DTS:ExecutableType="Microsoft.Package" DTS:LocaleID="1033" DTS:ObjectName="$PackageName" DTS:VersionGUID="$packageGuid">
  <DTS:Property DTS:Name="PackageFormatVersion">8</DTS:Property>
  <DTS:Variables />
  <DTS:Executables>
    <DTS:Executable DTS:refId="Package\ProcessTask" DTS:CreationName="Microsoft.ExecuteProcess" DTS:DTSID="$taskGuid" DTS:ExecutableType="Microsoft.ExecuteProcess" DTS:LocaleID="-1" DTS:ObjectName="ProcessTask">
      <DTS:ObjectData>
        <ExecuteProcessData xmlns="www.microsoft.com/sqlserver/dts/tasks/executeprocesstask" Executable="$Executable" Arguments="$Arguments" />
      </DTS:ObjectData>
    </DTS:Executable>
  </DTS:Executables>
</DTS:Executable>
"@

            $manifestXml = @"
<SSIS:Project SSIS:ProtectionLevel="DontSaveSensitive" xmlns:SSIS="www.microsoft.com/SqlServer/SSIS">
  <SSIS:Properties>
    <SSIS:Property SSIS:Name="ID">$packageGuid</SSIS:Property>
    <SSIS:Property SSIS:Name="Name">$ProjectName</SSIS:Property>
    <SSIS:Property SSIS:Name="VersionMajor">1</SSIS:Property>
    <SSIS:Property SSIS:Name="VersionMinor">0</SSIS:Property>
    <SSIS:Property SSIS:Name="VersionBuild">0</SSIS:Property>
    <SSIS:Property SSIS:Name="VersionComments"></SSIS:Property>
    <SSIS:Property SSIS:Name="CreationDate">2026-08-03T15:40:56.683402+02:00</SSIS:Property>
    <SSIS:Property SSIS:Name="CreatorName">dbatools</SSIS:Property>
    <SSIS:Property SSIS:Name="CreatorComputerName">dbatools</SSIS:Property>
    <SSIS:Property SSIS:Name="Description"></SSIS:Property>
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
          <SSIS:Property SSIS:Name="ID">$packageGuid</SSIS:Property>
          <SSIS:Property SSIS:Name="Name">$PackageName</SSIS:Property>
          <SSIS:Property SSIS:Name="VersionMajor">1</SSIS:Property>
          <SSIS:Property SSIS:Name="VersionMinor">0</SSIS:Property>
          <SSIS:Property SSIS:Name="VersionBuild">0</SSIS:Property>
          <SSIS:Property SSIS:Name="VersionComments"></SSIS:Property>
          <SSIS:Property SSIS:Name="VersionGUID">$packageGuid</SSIS:Property>
          <SSIS:Property SSIS:Name="PackageFormatVersion">8</SSIS:Property>
          <SSIS:Property SSIS:Name="Description"></SSIS:Property>
          <SSIS:Property SSIS:Name="ProtectionLevel">0</SSIS:Property>
        </SSIS:Properties>
        <SSIS:Parameters />
      </SSIS:PackageMetaData>
    </SSIS:PackageInfo>
  </SSIS:DeploymentInfo>
</SSIS:Project>
"@

            $processContentTypesXml = "<?xml version=`"1.0`" encoding=`"utf-8`"?><Types xmlns=`"http://schemas.openxmlformats.org/package/2006/content-types`"><Default Extension=`"dtsx`" ContentType=`"text/xml`" /><Default Extension=`"params`" ContentType=`"text/xml`" /><Default Extension=`"manifest`" ContentType=`"text/xml`" /></Types>"
            $processParametersXml = "<?xml version=`"1.0`"?><SSIS:Parameters xmlns:SSIS=`"www.microsoft.com/SqlServer/SSIS`" />"

            $processStream = New-Object System.IO.FileStream ($Path, [System.IO.FileMode]::Create)
            $processArchive = New-Object System.IO.Compression.ZipArchive ($processStream, [System.IO.Compression.ZipArchiveMode]::Create)
            try {
                foreach ($processPart in @(@("$PackageName.dtsx", $packageXml), @("Project.params", $processParametersXml), @("@Project.manifest", $manifestXml), @("[Content_Types].xml", $processContentTypesXml))) {
                    $processEntry = $processArchive.CreateEntry($processPart[0])
                    $processWriter = New-Object System.IO.StreamWriter ($processEntry.Open())
                    $processWriter.Write($processPart[1])
                    $processWriter.Flush()
                    $processWriter.Dispose()
                }
            } finally {
                $processArchive.Dispose()
                $processStream.Dispose()
            }
        }

        function Get-SsisExecutionRow {
            param($ExecutionId)
            $splatExecutionRead = @{
                SqlInstance  = $TestConfig.InstanceSsis
                Database     = "SSISDB"
                Query        = "SELECT execution_id, folder_name, project_name, package_name, status, reference_id, use32bitruntime FROM [catalog].[executions] WHERE execution_id = @executionId"
                SqlParameter = @{ executionId = $ExecutionId }
            }
            # The comma keeps the array intact across the return: without it PowerShell unrolls a
            # one-row result to a bare DataRow, and [0] then indexes its first COLUMN, not its
            # first row.
            , @(Invoke-DbaQuery @splatExecutionRead)
        }

        function Get-SsisExecutionParameterValue {
            param($ExecutionId, $ObjectType, $ParameterName)
            $splatParameterRead = @{
                SqlInstance  = $TestConfig.InstanceSsis
                Database     = "SSISDB"
                Query        = "SELECT parameter_value FROM [catalog].[execution_parameter_values] WHERE execution_id = @executionId AND object_type = @objectType AND parameter_name = @parameterName"
                SqlParameter = @{
                    executionId   = $ExecutionId
                    objectType    = $ObjectType
                    parameterName = $ParameterName
                }
            }
            (Invoke-DbaQuery @splatParameterRead).parameter_value
        }

        # A leftover folder from an interrupted run would carry a leftover project and its
        # executions, so the whole folder is cleared and rebuilt rather than patched.
        $splatStaleReference = @{
            SqlInstance  = $ssisInstance
            Database     = "SSISDB"
            Query        = "DECLARE @rid bigint; DECLARE stale CURSOR LOCAL FAST_FORWARD FOR SELECT r.reference_id FROM [catalog].[environment_references] r JOIN [catalog].[projects] p ON p.project_id = r.project_id JOIN [catalog].[folders] f ON f.folder_id = p.folder_id WHERE f.name = @folder AND p.name = @project; OPEN stale; FETCH NEXT FROM stale INTO @rid; WHILE @@FETCH_STATUS = 0 BEGIN EXEC [catalog].[delete_environment_reference] @reference_id = @rid; FETCH NEXT FROM stale INTO @rid; END; CLOSE stale; DEALLOCATE stale;"
            SqlParameter = @{
                folder  = $executionFolder
                project = $executionProject
            }
        }
        Invoke-DbaQuery @splatStaleReference

        foreach ($staleStatement in @(
                "IF EXISTS (SELECT 1 FROM [catalog].[projects] p JOIN [catalog].[folders] f ON f.folder_id = p.folder_id WHERE f.name = @folder AND p.name = @project) EXEC [catalog].[delete_project] @folder_name = @folder, @project_name = @project;",
                "IF EXISTS (SELECT 1 FROM [catalog].[environments] e JOIN [catalog].[folders] f ON f.folder_id = e.folder_id WHERE f.name = @folder AND e.name = @environment) EXEC [catalog].[delete_environment] @folder_name = @folder, @environment_name = @environment;",
                "IF EXISTS (SELECT 1 FROM [catalog].[environments] e JOIN [catalog].[folders] f ON f.folder_id = e.folder_id WHERE f.name = @decoy AND e.name = @environment) EXEC [catalog].[delete_environment] @folder_name = @decoy, @environment_name = @environment;",
                "IF EXISTS (SELECT 1 FROM [catalog].[folders] WHERE name = @decoy) EXEC [catalog].[delete_folder] @folder_name = @decoy;",
                "IF NOT EXISTS (SELECT 1 FROM [catalog].[folders] WHERE name = @folder) EXEC [catalog].[create_folder] @folder_name = @folder, @folder_id = NULL;",
                "EXEC [catalog].[create_environment] @folder_name = @folder, @environment_name = @environment, @environment_description = NULL;"
            )) {
            $splatStale = @{
                SqlInstance  = $ssisInstance
                Database     = "SSISDB"
                Query        = $staleStatement
                SqlParameter = @{
                    folder      = $executionFolder
                    project     = $executionProject
                    environment = $executionEnvironment
                    decoy       = $decoyFolder
                }
            }
            Invoke-DbaQuery @splatStale
        }

        # A fresh directory of this run's own, rather than a predictable name in the shared temp
        # root: two runs at once would otherwise overwrite each other's project file.
        $executionRunId = [guid]::NewGuid().ToString("n")
        $projectRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "dbatoolsci_exec_$executionRunId"
        $null = New-Item -Path $projectRoot -ItemType Directory -Force
        $projectFile = Join-Path -Path $projectRoot -ChildPath "$executionProject.ispac"
        New-SsisParameterizedProjectFile -ProjectName $executionProject -PackageName $executionPackage -Path $projectFile

        $splatPublish = @{
            SqlInstance = $ssisInstance
            Folder      = $executionFolder
            Project     = $executionProject
            Path        = $projectFile
        }
        $null = Publish-DbaSsisProject @splatPublish

        # Two more projects in the same folder, for the two ways a synchronous wait can end other
        # than "it finished". Measured on this catalog: the parameterized package above reaches a
        # terminal status in about a second, the 25-second one below stays Running for 25, and the
        # missing-executable one fails in about one - so a -Timeout of 5 can only expire on the
        # slow project, and can only be reached on it.
        $slowProject = "dbatoolsci_execslowproject1"
        $slowPackage = "dbatoolsci_execslowpackage1"
        $failingProject = "dbatoolsci_execfailproject1"
        $failingPackage = "dbatoolsci_execfailpackage1"
        foreach ($processFixture in @(
                @{ Project = $slowProject; Package = $slowPackage; Executable = "ping.exe"; Arguments = "-n 25 127.0.0.1" },
                @{ Project = $failingProject; Package = $failingPackage; Executable = "dbatoolsci_nosuchprogram.exe"; Arguments = "" }
            )) {
            $processFile = Join-Path -Path $projectRoot -ChildPath "$($processFixture.Project).ispac"
            $splatProcessFile = @{
                ProjectName = $processFixture.Project
                PackageName = $processFixture.Package
                Path        = $processFile
                Executable  = $processFixture.Executable
                Arguments   = $processFixture.Arguments
            }
            New-SsisProcessProjectFile @splatProcessFile

            $splatProcessPublish = @{
                SqlInstance = $ssisInstance
                Folder      = $executionFolder
                Project     = $processFixture.Project
                Path        = $processFile
            }
            $null = Publish-DbaSsisProject @splatProcessPublish
        }

        foreach ($decoyStatement in @(
                "IF NOT EXISTS (SELECT 1 FROM [catalog].[folders] WHERE name = @decoy) EXEC [catalog].[create_folder] @folder_name = @decoy, @folder_id = NULL;",
                "IF NOT EXISTS (SELECT 1 FROM [catalog].[environments] e JOIN [catalog].[folders] f ON f.folder_id = e.folder_id WHERE f.name = @decoy AND e.name = @environment) EXEC [catalog].[create_environment] @folder_name = @decoy, @environment_name = @environment, @environment_description = NULL;"
            )) {
            $splatDecoy = @{
                SqlInstance  = $ssisInstance
                Database     = "SSISDB"
                Query        = $decoyStatement
                SqlParameter = @{
                    decoy       = $decoyFolder
                    environment = $executionEnvironment
                }
            }
            Invoke-DbaQuery @splatDecoy
        }

        # 'A' is an absolute reference - the folder is named and stored, and this one names the
        # decoy, so the project references two different environments under the same name.
        #
        # The decoy is created FIRST on purpose. Both references satisfy an environment_name match,
        # so a lookup that does not constrain the folder has to pick one, and an unordered TOP 1
        # tends to hand back the lower reference_id. Creating the wrong answer first is what makes
        # the collision leg fail against such a lookup instead of passing by luck.
        $splatDecoyReference = @{
            SqlInstance  = $ssisInstance
            Database     = "SSISDB"
            Query        = "DECLARE @rid bigint; EXEC [catalog].[create_environment_reference] @folder_name = @folder, @project_name = @project, @environment_name = @environment, @reference_type = 'A', @environment_folder_name = @decoy, @reference_id = @rid OUTPUT; SELECT ReferenceId = @rid;"
            SqlParameter = @{
                folder      = $executionFolder
                project     = $executionProject
                environment = $executionEnvironment
                decoy       = $decoyFolder
            }
        }
        $absoluteReferenceId = (Invoke-DbaQuery @splatDecoyReference).ReferenceId

        # 'R' is a relative reference - the environment lives in the project's own folder.
        $splatReference = @{
            SqlInstance  = $ssisInstance
            Database     = "SSISDB"
            Query        = "DECLARE @rid bigint; EXEC [catalog].[create_environment_reference] @folder_name = @folder, @project_name = @project, @environment_name = @environment, @reference_type = 'R', @environment_folder_name = NULL, @reference_id = @rid OUTPUT; SELECT ReferenceId = @rid;"
            SqlParameter = @{
                folder      = $executionFolder
                project     = $executionProject
                environment = $executionEnvironment
            }
        }
        $relativeReferenceId = (Invoke-DbaQuery @splatReference).ReferenceId
    }

    AfterAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        # The project carries more than one reference now, so a single SELECT @rid would leave the
        # rest behind and the folder would refuse to drop.
        $splatReferenceCleanup = @{
            SqlInstance  = $TestConfig.InstanceSsis
            Database     = "SSISDB"
            Query        = "DECLARE @rid bigint; DECLARE ref CURSOR LOCAL FAST_FORWARD FOR SELECT r.reference_id FROM [catalog].[environment_references] r JOIN [catalog].[projects] p ON p.project_id = r.project_id JOIN [catalog].[folders] f ON f.folder_id = p.folder_id WHERE f.name = @folder AND p.name = @project; OPEN ref; FETCH NEXT FROM ref INTO @rid; WHILE @@FETCH_STATUS = 0 BEGIN EXEC [catalog].[delete_environment_reference] @reference_id = @rid; FETCH NEXT FROM ref INTO @rid; END; CLOSE ref; DEALLOCATE ref;"
            SqlParameter = @{
                folder  = "dbatoolsci_execfolder1"
                project = "dbatoolsci_execproject1"
            }
        }
        Invoke-DbaQuery @splatReferenceCleanup

        # One leg deliberately walks away from a run that is still going, and a run still holding
        # its project stops the folder from being dropped. Waiting on the catalog's own status is
        # what makes the teardown deterministic instead of a race with a 25-second package.
        $splatRunningWait = @{
            SqlInstance  = $TestConfig.InstanceSsis
            Database     = "SSISDB"
            Query        = "DECLARE @waited int = 0; WHILE @waited < 60 AND EXISTS (SELECT 1 FROM [catalog].[executions] e WHERE e.folder_name = @folder AND e.status NOT IN (3, 4, 6, 7, 9)) BEGIN WAITFOR DELAY '00:00:02'; SET @waited = @waited + 2; END;"
            SqlParameter = @{ folder = "dbatoolsci_execfolder1" }
        }
        Invoke-DbaQuery @splatRunningWait

        foreach ($cleanupStatement in @(
                "DECLARE @name sysname; DECLARE leftovers CURSOR LOCAL FAST_FORWARD FOR SELECT p.name FROM [catalog].[projects] p JOIN [catalog].[folders] f ON f.folder_id = p.folder_id WHERE f.name = @folder; OPEN leftovers; FETCH NEXT FROM leftovers INTO @name; WHILE @@FETCH_STATUS = 0 BEGIN EXEC [catalog].[delete_project] @folder_name = @folder, @project_name = @name; FETCH NEXT FROM leftovers INTO @name; END; CLOSE leftovers; DEALLOCATE leftovers;",
                "IF EXISTS (SELECT 1 FROM [catalog].[environments] e JOIN [catalog].[folders] f ON f.folder_id = e.folder_id WHERE f.name = @folder AND e.name = @environment) EXEC [catalog].[delete_environment] @folder_name = @folder, @environment_name = @environment;",
                "IF EXISTS (SELECT 1 FROM [catalog].[environments] e JOIN [catalog].[folders] f ON f.folder_id = e.folder_id WHERE f.name = @decoy AND e.name = @environment) EXEC [catalog].[delete_environment] @folder_name = @decoy, @environment_name = @environment;",
                "IF EXISTS (SELECT 1 FROM [catalog].[folders] WHERE name = @folder) EXEC [catalog].[delete_folder] @folder_name = @folder;",
                "IF EXISTS (SELECT 1 FROM [catalog].[folders] WHERE name = @decoy) EXEC [catalog].[delete_folder] @folder_name = @decoy;"
            )) {
            $splatCleanup = @{
                SqlInstance  = $TestConfig.InstanceSsis
                Database     = "SSISDB"
                Query        = $cleanupStatement
                SqlParameter = @{
                    folder      = "dbatoolsci_execfolder1"
                    environment = "dbatoolsci_execenv1"
                    decoy       = "dbatoolsci_execdecoy1"
                }
            }
            Invoke-DbaQuery @splatCleanup
        }

        if ($projectRoot -and (Test-Path -LiteralPath $projectRoot)) {
            Remove-Item -LiteralPath $projectRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Starting a package" {
        It "Starts the package and returns the execution" {
            $splatStart = @{
                SqlInstance = $ssisInstance
                Folder      = $executionFolder
                Project     = $executionProject
                Package     = "$executionPackage.dtsx"
            }
            $started = @(Start-DbaSsisExecution @splatStart)
            $started.Count | Should -Be 1
            $started[0].ExecutionID | Should -BeGreaterThan 0
            $started[0].FolderName | Should -Be $executionFolder
            $started[0].ProjectName | Should -Be $executionProject
            $started[0].PackageName | Should -Be "$executionPackage.dtsx"

            $catalogRow = Get-SsisExecutionRow -ExecutionId $started[0].ExecutionID
            $catalogRow.Count | Should -Be 1
            $catalogRow[0].package_name | Should -Be "$executionPackage.dtsx"
        }

        It "Takes WorkerAgentId from the catalog's own schema" {
            # catalog.executions is a view inside SSISDB, so whether it exposes worker_agent_id is
            # a fact about the catalog rather than about the engine hosting it - a catalog restored
            # from an older instance is older than its server. Naming a column the view does not
            # have fails the whole SELECT, which would leave the package started and unreportable.
            $splatColumnPresence = @{
                SqlInstance  = $ssisInstance
                Database     = "SSISDB"
                Query        = "SELECT ColumnCount = COUNT(*) FROM sys.columns catalogColumns JOIN sys.objects catalogObjects ON catalogObjects.object_id = catalogColumns.object_id JOIN sys.schemas catalogSchemas ON catalogSchemas.schema_id = catalogObjects.schema_id WHERE catalogSchemas.name = 'catalog' AND catalogObjects.name = 'executions' AND catalogColumns.name = 'worker_agent_id'"
            }
            (Invoke-DbaQuery @splatColumnPresence).ColumnCount | Should -Be 1

            $splatStartWorker = @{
                SqlInstance = $ssisInstance
                Folder      = $executionFolder
                Project     = $executionProject
                Package     = "$executionPackage.dtsx"
            }
            $withWorker = @(Start-DbaSsisExecution @splatStartWorker)
            $withWorker.Count | Should -Be 1
            $withWorker[0].PSObject.Properties.Name | Should -Contain "WorkerAgentId"

            # The column is here, so the emitted value has to be the catalog's - a null would mean
            # the command decided the column was missing and substituted one.
            $splatWorkerRead = @{
                SqlInstance  = $ssisInstance
                Database     = "SSISDB"
                Query        = "SELECT WorkerAgent = CONVERT(nvarchar(64), worker_agent_id) FROM [catalog].[executions] WHERE execution_id = @executionId"
                SqlParameter = @{ executionId = $withWorker[0].ExecutionID }
            }
            # Whatever the row holds, the command has to report that and not something of its own.
            # Note the reach: with Scale Out off the row's value is NULL, and a command that had
            # wrongly concluded the column was absent would substitute NULL too - so this pins the
            # value against the catalog, not the presence check. Exercising the absent branch needs
            # a catalog whose view predates the column, which cannot be made here without altering
            # a shared SSISDB.
            $catalogWorkerAgent = (Invoke-DbaQuery @splatWorkerRead).WorkerAgent
            [string]$withWorker[0].WorkerAgentId | Should -Be ([string]$catalogWorkerAgent)
        }

        It "Decorates the execution exactly like the read command does" {
            $splatStartDecorated = @{
                SqlInstance = $ssisInstance
                Folder      = $executionFolder
                Project     = $executionProject
                Package     = "$executionPackage.dtsx"
            }
            $started = @(Start-DbaSsisExecution @splatStartDecorated)[0]
            $read = @(Get-DbaSsisExecution -SqlInstance $ssisInstance -ExecutionId $started.ExecutionID)[0]
            $started.PSObject.TypeNames[0] | Should -Be "dbatools.SsisExecution"
            $started.ComputerName | Should -Not -BeNullOrEmpty
            $started.SqlInstance | Should -Not -BeNullOrEmpty
            Compare-Object -ReferenceObject $read.PSObject.Properties.Name -DifferenceObject $started.PSObject.Properties.Name | Should -BeNullOrEmpty
            $startedDisplaySet = $started.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $readDisplaySet = $read.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $readDisplaySet -DifferenceObject $startedDisplaySet | Should -BeNullOrEmpty
        }
    }

    Context "-Synchronous" {
        It "Waits for the run and comes back with a terminal status" {
            $splatSynchronous = @{
                SqlInstance = $ssisInstance
                Folder      = $executionFolder
                Project     = $executionProject
                Package     = "$executionPackage.dtsx"
                Synchronous = $true
                Timeout     = 300
            }
            $finished = @(Start-DbaSsisExecution @splatSynchronous)
            $finished.Count | Should -Be 1
            $finished[0].StatusCode | Should -Be "Succeeded"
            $finished[0].EndTime | Should -Not -BeNullOrEmpty
            # Without the wait the status would still be Pending or Running here, so reading the
            # catalog back is what separates "waited" from "returned a status that was true once".
            (Get-SsisExecutionRow -ExecutionId $finished[0].ExecutionID)[0].status | Should -Be 7
        }

        It "Gives up at -Timeout and leaves the run alone" {
            # The wait has to end on its own terms, and it has to end without touching the run:
            # stopping a package the caller only asked to wait for is a destructive act nobody
            # requested, and stopping it would also hide the difference between "waited and gave up"
            # and "waited until it finished".
            $splatTimedOut = @{
                SqlInstance = $ssisInstance
                Folder      = $executionFolder
                Project     = $slowProject
                Package     = "$slowPackage.dtsx"
                Synchronous = $true
                Timeout     = 5
            }
            $timedOut = $null
            try {
                Start-DbaSsisExecution @splatTimedOut
            } catch {
                $timedOut = $PSItem
            }
            $timedOut | Should -Not -BeNullOrEmpty
            $timedOut.Exception.Message | Should -BeLike "*Timed out after 5 seconds*"
            $timedOut.Exception.Message | Should -BeLike "*has NOT been stopped*"

            # The id is read out of the message rather than from a return value because there is no
            # return value: a wait that expired hands the caller nothing, so the message is the only
            # place the execution can be named - and it has to be, or the run is unreachable.
            # -match rather than Should -Match: Pester evaluates its own match in its own scope, so
            # $Matches never reaches here from a Should.
            ($timedOut.Exception.Message -match "execution (\d+) is still") | Should -BeTrue
            $abandonedExecutionId = [int64]$Matches[1]
            # 3 Cancelled and 8 Stopping are what a command that stopped the run would leave behind.
            (Get-SsisExecutionRow -ExecutionId $abandonedExecutionId)[0].status | Should -BeIn @(1, 2, 5)
        }

        It "Reports a run that ended Failed, and what the catalog said about it" {
            # A terminal status is not the same as a successful one, and returning the execution
            # object for a failed run reads as success to every caller that checks for output. The
            # cause comes with it: the catalog logs it against the execution, and a caller told only
            # "Failed" has to go and find that view themselves.
            #
            # Reach: Cancelled and Halted take this same branch and differ only in the name the
            # message carries, and producing either needs a second session to stop the run while
            # this one is mid-poll, which one Pester runspace cannot do.
            $splatFailing = @{
                SqlInstance     = $ssisInstance
                Folder          = $executionFolder
                Project         = $failingProject
                Package         = "$failingPackage.dtsx"
                Synchronous     = $true
                Timeout         = 300
                EnableException = $false
                WarningVariable = "failureWarning"
                WarningAction   = "SilentlyContinue"
            }
            # Not the throwing shape on purpose: without -EnableException the failure is a warning,
            # and the caller's `if ($result)` is what decides what happens next. So this pins that
            # a failed run yields no result at all.
            $emitted = @(Start-DbaSsisExecution @splatFailing)
            $emitted.Count | Should -Be 0

            $failureText = $failureWarning -join " "
            $failureText | Should -BeLike "*finished as Failed*"
            $failureText | Should -BeLike "*dbatoolsci_nosuchprogram.exe*"

            ($failureText -match "execution (\d+)\)") | Should -BeTrue
            (Get-SsisExecutionRow -ExecutionId ([int64]$Matches[1]))[0].status | Should -Be 4
        }
    }

    Context "Execution parameters" {
        It "Sets package, project and system parameters in their own scopes" {
            # The catalog discriminates the three scopes on one smallint - 30 package, 20 project,
            # 50 system - so a command that put them all in one bucket would still create rows and
            # still look green. Reading each back under its own object_type is what tells them apart.
            $splatParameters = @{
                SqlInstance      = $ssisInstance
                Folder           = $executionFolder
                Project          = $executionProject
                Package          = "$executionPackage.dtsx"
                Parameter        = @{ $packageParameterName = 42 }
                ProjectParameter = @{ $projectParameterName = 99 }
                LoggingLevel     = 1
                Synchronous      = $true
                Timeout          = 300
            }
            $parameterized = @(Start-DbaSsisExecution @splatParameters)
            $parameterized.Count | Should -Be 1
            $parameterized[0].StatusCode | Should -Be "Succeeded"

            $executionId = $parameterized[0].ExecutionID
            Get-SsisExecutionParameterValue -ExecutionId $executionId -ObjectType 30 -ParameterName $packageParameterName | Should -Be 42
            Get-SsisExecutionParameterValue -ExecutionId $executionId -ObjectType 20 -ParameterName $projectParameterName | Should -Be 99
            Get-SsisExecutionParameterValue -ExecutionId $executionId -ObjectType 50 -ParameterName "LOGGING_LEVEL" | Should -Be 1
            $parameterized[0].LoggingLevel | Should -Be 1
        }
    }

    Context "-Environment" {
        It "Binds the run to the project's reference to that environment" {
            $splatEnvironment = @{
                SqlInstance = $ssisInstance
                Folder      = $executionFolder
                Project     = $executionProject
                Package     = "$executionPackage.dtsx"
                Environment = $executionEnvironment
            }
            $bound = @(Start-DbaSsisExecution @splatEnvironment)
            $bound.Count | Should -Be 1
            $bound[0].EnvironmentName | Should -Be $executionEnvironment
            $bound[0].ReferenceId | Should -BeGreaterThan 0
            (Get-SsisExecutionRow -ExecutionId $bound[0].ExecutionID)[0].reference_id | Should -Be $bound[0].ReferenceId
        }

        It "Picks the environment beside the project when another folder holds the same name" {
            # Both references satisfy an environment_name match, so this is the leg that separates
            # resolving the reference from finding any row that mentions the name. Asserting the
            # reference id rather than the environment name is the whole point: the names are equal.
            #
            # And the decoy has to be the lower id, or an unordered TOP 1 would return the right
            # answer by accident and this leg would prove nothing. Assert the ordering rather than
            # trusting the setup to have produced it.
            $absoluteReferenceId | Should -BeLessThan $relativeReferenceId
            $splatCollision = @{
                SqlInstance = $ssisInstance
                Folder      = $executionFolder
                Project     = $executionProject
                Package     = "$executionPackage.dtsx"
                Environment = $executionEnvironment
            }
            $unqualified = @(Start-DbaSsisExecution @splatCollision)
            $unqualified.Count | Should -Be 1
            $unqualified[0].ReferenceId | Should -Be $relativeReferenceId
            (Get-SsisExecutionRow -ExecutionId $unqualified[0].ExecutionID)[0].reference_id | Should -Be $relativeReferenceId
        }

        It "Binds the other folder's environment when -EnvironmentFolder names it" {
            $splatQualified = @{
                SqlInstance       = $ssisInstance
                Folder            = $executionFolder
                Project           = $executionProject
                Package           = "$executionPackage.dtsx"
                Environment       = $executionEnvironment
                EnvironmentFolder = $decoyFolder
            }
            $qualified = @(Start-DbaSsisExecution @splatQualified)
            $qualified.Count | Should -Be 1
            $qualified[0].ReferenceId | Should -Be $absoluteReferenceId
            (Get-SsisExecutionRow -ExecutionId $qualified[0].ExecutionID)[0].reference_id | Should -Be $absoluteReferenceId
        }

        It "Refuses an environment the project does not reference" {
            # Starting anyway would run the package on its design-time values and fail somewhere
            # inside it, which reads as a package bug rather than as the missing reference it is.
            $splatNoReference = @{
                SqlInstance = $ssisInstance
                Folder      = $executionFolder
                Project     = $executionProject
                Package     = "$executionPackage.dtsx"
                Environment = "dbatoolsci_execnosuchenv"
            }
            { Start-DbaSsisExecution @splatNoReference } | Should -Throw "*has no reference to environment dbatoolsci_execnosuchenv*"
        }
    }

    Context "-WhatIf" {
        It "Reports without creating an execution" {
            $splatBefore = @{
                SqlInstance  = $ssisInstance
                Database     = "SSISDB"
                Query        = "SELECT COUNT(*) AS executions FROM [catalog].[executions] WHERE folder_name = @folder AND project_name = @project"
                SqlParameter = @{
                    folder  = $executionFolder
                    project = $executionProject
                }
            }
            $countBefore = (Invoke-DbaQuery @splatBefore).executions

            $splatWhatIf = @{
                SqlInstance = $ssisInstance
                Folder      = $executionFolder
                Project     = $executionProject
                Package     = "$executionPackage.dtsx"
                WhatIf      = $true
            }
            $whatIfResult = @(Start-DbaSsisExecution @splatWhatIf)
            $whatIfResult.Count | Should -Be 0
            (Invoke-DbaQuery @splatBefore).executions | Should -Be $countBefore
        }
    }

    Context "A package that does not exist" {
        It "Refuses rather than reporting a run that never started" {
            $splatMissingPackage = @{
                SqlInstance = $ssisInstance
                Folder      = $executionFolder
                Project     = $executionProject
                Package     = "dbatoolsci_execnosuchpackage.dtsx"
            }
            { Start-DbaSsisExecution @splatMissingPackage } | Should -Throw
        }
    }

    Context "An instance with no SSIS catalog" {
        # InstanceSingle carries no SSISDB, so this exercises the presence check rather than
        # failing inside the catalog schema.
        It "Warns and returns nothing" {
            $splatNoCatalog = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Folder          = $executionFolder
                Project         = $executionProject
                Package         = "$executionPackage.dtsx"
                EnableException = $false
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $none = @(Start-DbaSsisExecution @splatNoCatalog)
            $none.Count | Should -Be 0
            ($warn -join " ") | Should -BeLike "*No SSIS catalog (SSISDB) found*"
        }

        It "Throws under -EnableException" {
            $splatNoCatalogThrow = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Folder          = $executionFolder
                Project         = $executionProject
                Package         = "$executionPackage.dtsx"
                EnableException = $true
            }
            { Start-DbaSsisExecution @splatNoCatalogThrow } | Should -Throw "*No SSIS catalog (SSISDB) found*"
        }
    }
}
