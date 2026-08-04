#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Stop-DbaSsisExecution",
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
                "ExecutionId",
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
            # The command's own documented usage is Get-DbaSsisExecution -Status Running |
            # Stop-DbaSsisExecution. A mandatory SqlInstance makes that call fail to bind outright,
            # and a second ValueFromPipeline parameter double-binds the piped executions onto
            # -SqlInstance instead of -InputObject.
            $sqlInstance = (Get-Command $CommandName).Parameters["SqlInstance"].Attributes | Where-Object { $PSItem -is [System.Management.Automation.ParameterAttribute] }
            $sqlInstance.Mandatory | Should -BeFalse
            $sqlInstance.ValueFromPipeline | Should -BeFalse
            $inputObject = (Get-Command $CommandName).Parameters["InputObject"].Attributes | Where-Object { $PSItem -is [System.Management.Automation.ParameterAttribute] }
            $inputObject.ValueFromPipeline | Should -BeTrue
        }
    }

    Context "Refusals that settle before anything connects" {
        It "Refuses a call with no instance and no input object" {
            { Stop-DbaSsisExecution -ExecutionId 1 -EnableException } | Should -Throw "*either -SqlInstance or an Input Object*"
        }

        It "Refuses an instance with no execution named, without reaching the server" {
            # The instance is unreachable, so a command that had lost the guard would fail with a
            # connection error instead of this message - which is how the leg tells "refused" from
            # "tried and could not", and so proves no catalog.stop_operation call was issued.
            $splatNoTarget = @{
                SqlInstance     = $TestConfig.InstanceUnreachable
                EnableException = $true
            }
            { Stop-DbaSsisExecution @splatNoTarget } | Should -Throw "*You must supply -ExecutionId, or pipe in executions from Get-DbaSsisExecution*"
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        $ssisInstance    = $TestConfig.InstanceSsis
        $executionFolder = "dbatoolsci_stopexecfolder1"
        $slowProject     = "dbatoolsci_stopslowproject1"
        $slowPackage     = "dbatoolsci_stopslowpackage1"
        $failProject     = "dbatoolsci_stopfailproject1"
        $failPackage     = "dbatoolsci_stopfailpackage1"

        function New-SsisProcessProjectFile {
            param($ProjectName, $PackageName, $Path, $Executable, $Arguments)

            if (-not ("System.IO.Compression.ZipArchive" -as [type])) {
                Add-Type -AssemblyName "System.IO.Compression"
            }

            # An Execute Process task is the one task type that needs no connection manager, so the
            # package it lives in stays hand-writable. What it runs is what decides whether the
            # execution stays Running long enough to be stopped, or reaches a terminal status on
            # its own.
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
    <SSIS:Property SSIS:Name="CreationDate">2026-08-04T00:00:00.000000+02:00</SSIS:Property>
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

        function Get-SsisExecutionStatus {
            param($ExecutionId)
            $splatStatusRead = @{
                SqlInstance  = $TestConfig.InstanceSsis
                Database     = "SSISDB"
                Query        = "SELECT status FROM [catalog].[executions] WHERE execution_id = @executionId"
                SqlParameter = @{ executionId = $ExecutionId }
            }
            (Invoke-DbaQuery @splatStatusRead).status
        }

        function Get-SsisStopRequestCount {
            param($Since)
            # internal.prepare_stop opens by INSERTing an operations row of type 202 - before it sets
            # SERIALIZABLE and opens its transaction, so the row survives even a stop that then
            # fails and rolls back. Counting those rows is therefore "was catalog.stop_operation
            # entered", which is the assertion the target guard needs; the emitted object and the
            # execution's own status only say what happened afterwards. Windowed on created_time
            # because a stop request is keyed to the project it stopped, not to the execution.
            $splatStopCount = @{
                SqlInstance  = $TestConfig.InstanceSsis
                Database     = "SSISDB"
                Query        = "SELECT COUNT(*) AS requests FROM [internal].[operations] WHERE operation_type = 202 AND created_time >= @since"
                SqlParameter = @{ since = $Since }
            }
            [int](Invoke-DbaQuery @splatStopCount).requests
        }

        function Get-SsisCatalogTime {
            $splatCatalogTime = @{
                SqlInstance = $TestConfig.InstanceSsis
                Database    = "SSISDB"
                Query       = "SELECT SYSDATETIMEOFFSET() AS now"
            }
            # The catalog's clock, not the client's: created_time is a datetimeoffset stamped by the
            # server, and a window opened from a client clock a few seconds fast counts nothing.
            (Invoke-DbaQuery @splatCatalogTime).now
        }

        function Start-SsisRunningExecution {
            $splatStart = @{
                SqlInstance = $TestConfig.InstanceSsis
                Folder      = "dbatoolsci_stopexecfolder1"
                Project     = "dbatoolsci_stopslowproject1"
                Package     = "dbatoolsci_stopslowpackage1"
            }
            $execution = Start-DbaSsisExecution @splatStart
            $executionId = [long]$execution.ExecutionID

            $runningDeadline = (Get-Date).AddSeconds(90)
            while ((Get-SsisExecutionStatus -ExecutionId $executionId) -ne 2 -and (Get-Date) -lt $runningDeadline) {
                Start-Sleep -Seconds 1
            }
            if ((Get-SsisExecutionStatus -ExecutionId $executionId) -ne 2) {
                throw "Execution $executionId never reached Running on $($TestConfig.InstanceSsis) - a leg asserting that a stop moved it out of Running would prove nothing about the stop."
            }
            $executionId
        }

        function Wait-SsisExecutionTerminal {
            param($ExecutionId)
            $terminalDeadline = (Get-Date).AddSeconds(90)
            $status = Get-SsisExecutionStatus -ExecutionId $ExecutionId
            while ($status -in 1, 2, 5, 8 -and (Get-Date) -lt $terminalDeadline) {
                Start-Sleep -Seconds 2
                $status = Get-SsisExecutionStatus -ExecutionId $ExecutionId
            }
            $status
        }

        function Stop-SsisFixtureExecution {
            param($ExecutionId)
            # Cleanup goes through the proc directly rather than through the command under test: a
            # teardown built on the thing being tested reports success when the command is broken.
            $splatFixtureStop = @{
                SqlInstance     = $TestConfig.InstanceSsis
                Database        = "SSISDB"
                Query           = "IF EXISTS (SELECT 1 FROM [catalog].[executions] WHERE execution_id = @executionId AND status = 2) EXEC [catalog].[stop_operation] @operation_id = @executionId;"
                SqlParameter    = @{ executionId = $ExecutionId }
                EnableException = $false
            }
            Invoke-DbaQuery @splatFixtureStop
        }

        function Remove-SsisExecutionFixture {
            foreach ($fixtureProject in @("dbatoolsci_stopslowproject1", "dbatoolsci_stopfailproject1")) {
                $splatProjectDrop = @{
                    SqlInstance     = $TestConfig.InstanceSsis
                    Database        = "SSISDB"
                    Query           = "IF EXISTS (SELECT 1 FROM [catalog].[projects] p JOIN [catalog].[folders] f ON f.folder_id = p.folder_id WHERE f.name = @folder AND p.name = @project) EXEC [catalog].[delete_project] @folder_name = @folder, @project_name = @project;"
                    SqlParameter    = @{ folder = "dbatoolsci_stopexecfolder1"; project = $fixtureProject }
                    EnableException = $false
                }
                Invoke-DbaQuery @splatProjectDrop
            }

            # delete_folder refuses a folder that still holds anything, so the projects go first.
            $splatFolderDrop = @{
                SqlInstance     = $TestConfig.InstanceSsis
                Database        = "SSISDB"
                Query           = "IF EXISTS (SELECT 1 FROM [catalog].[folders] WHERE name = @folder) EXEC [catalog].[delete_folder] @folder_name = @folder;"
                SqlParameter    = @{ folder = "dbatoolsci_stopexecfolder1" }
                EnableException = $false
            }
            Invoke-DbaQuery @splatFolderDrop
        }

        # A leftover project from an interrupted run would be deployed from a different .ispac, and
        # the ping length is what every timing assumption below rests on.
        Remove-SsisExecutionFixture

        $splatCreateFolder = @{
            SqlInstance  = $ssisInstance
            Database     = "SSISDB"
            Query        = "IF NOT EXISTS (SELECT 1 FROM [catalog].[folders] WHERE name = @folder) EXEC [catalog].[create_folder] @folder_name = @folder, @folder_id = NULL;"
            SqlParameter = @{ folder = $executionFolder }
        }
        Invoke-DbaQuery @splatCreateFolder

        # A directory of this run's own rather than a predictable name in the shared temp root: two
        # runs at once would otherwise overwrite each other's project file.
        $executionRunId = [guid]::NewGuid().ToString("n")
        $projectRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "dbatoolsci_stop_$executionRunId"
        $null = New-Item -Path $projectRoot -ItemType Directory -Force

        # Four minutes of ping is far longer than the whole suite, so every "it was still Running"
        # assertion below is about the command and never about the package finishing on its own.
        # The failing project is the opposite: no such executable, so it reaches Failed in about a
        # second and gives the not-Running refusal a real terminal execution to refuse.
        foreach ($processFixture in @(
                @{ Project = $slowProject; Package = $slowPackage; Executable = "ping.exe"; Arguments = "-n 240 127.0.0.1" },
                @{ Project = $failProject; Package = $failPackage; Executable = "dbatoolsci_nosuchprogram.exe"; Arguments = "" }
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

        # Every leg below starts an execution of these two projects, so a deploy that did not land
        # would turn the whole Describe into legs that prove nothing about stopping.
        $splatDeployedRead = @{
            SqlInstance  = $ssisInstance
            Database     = "SSISDB"
            Query        = "SELECT p.name FROM [catalog].[projects] p JOIN [catalog].[folders] f ON f.folder_id = p.folder_id WHERE f.name = @folder"
            SqlParameter = @{ folder = $executionFolder }
        }
        $deployedProjects = @((Invoke-DbaQuery @splatDeployedRead).name)
        foreach ($requiredProject in @($slowProject, $failProject)) {
            if ($deployedProjects -notcontains $requiredProject) {
                throw "Fixture project $requiredProject was not deployed to $executionFolder on $ssisInstance - the suite cannot stop an execution of a project that is not there."
            }
        }

        # An ArrayList that legs mutate rather than an array they reassign: `$list += $id` inside an
        # It creates a local copy, and AfterAll would then see an empty list and leave four
        # four-minute pings running on a shared instance.
        $startedExecutions = New-Object -TypeName System.Collections.ArrayList
    }

    AfterAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        foreach ($leftover in $startedExecutions) {
            Stop-SsisFixtureExecution -ExecutionId $leftover
        }
        Remove-SsisExecutionFixture
        Remove-Item -Path $projectRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context "Stopping a running execution" {
        It "Issues the stop, reports the execution and takes it out of Running" {
            $executionId = Start-SsisRunningExecution
            $null = $startedExecutions.Add($executionId)
            $legStart = Get-SsisCatalogTime

            $splatStop = @{
                SqlInstance = $ssisInstance
                ExecutionId = $executionId
                Confirm     = $false
            }
            $stopped = @(Stop-DbaSsisExecution @splatStop)
            $stopped.Count | Should -Be 1
            [long]$stopped[0].ExecutionID | Should -Be $executionId
            $stopped[0].PSObject.TypeNames[0] | Should -Be "dbatools.SsisExecution"
            $stopped[0].ProjectName | Should -Be $slowProject
            $stopped[0].Status | Should -Not -Be 2

            Get-SsisStopRequestCount -Since $legStart | Should -Be 1

            # The package pings for four minutes, so a terminal status inside this wait can only be
            # the stop taking effect - and Succeeded would mean it ran to completion, which is the
            # one outcome a stop must never produce.
            $terminal = Wait-SsisExecutionTerminal -ExecutionId $executionId
            $terminal | Should -Not -Be 2
            $terminal | Should -Not -Be 7
        }
    }

    Context "The target guard" {
        It "Refuses an instance with no execution named, and issues no stop" {
            # An instance with no execution named reads as "every running execution on it". The
            # assertion that closes this is the catalog's own stop-request count, not the message:
            # a guard that had been lost and let a stop through leaves a type-202 operations row
            # behind even if the stop then failed.
            $executionId = Start-SsisRunningExecution
            $null = $startedExecutions.Add($executionId)
            $legStart = Get-SsisCatalogTime

            $splatNoTarget = @{
                SqlInstance     = $ssisInstance
                EnableException = $false
                WarningVariable = "guardWarnings"
                WarningAction   = "SilentlyContinue"
                Confirm         = $false
            }
            $none = @(Stop-DbaSsisExecution @splatNoTarget)
            $none.Count | Should -Be 0
            ($guardWarnings -join " ") | Should -BeLike "*You must supply -ExecutionId*"

            Get-SsisStopRequestCount -Since $legStart | Should -Be 0
            Get-SsisExecutionStatus -ExecutionId $executionId | Should -Be 2

            Stop-SsisFixtureExecution -ExecutionId $executionId
        }
    }

    Context "-WhatIf" {
        It "Reports without stopping anything" {
            $executionId = Start-SsisRunningExecution
            $null = $startedExecutions.Add($executionId)
            $legStart = Get-SsisCatalogTime

            $splatWhatIf = @{
                SqlInstance = $ssisInstance
                ExecutionId = $executionId
                WhatIf      = $true
            }
            $whatIfResult = @(Stop-DbaSsisExecution @splatWhatIf)
            $whatIfResult.Count | Should -Be 0
            Get-SsisStopRequestCount -Since $legStart | Should -Be 0
            Get-SsisExecutionStatus -ExecutionId $executionId | Should -Be 2

            Stop-SsisFixtureExecution -ExecutionId $executionId
        }
    }

    Context "An execution that is not Running" {
        It "Reports the status it found and issues no stop" {
            # internal.prepare_stop only selects an operation WHERE status = 2 OR status = 8, and
            # raises 27126 immediately on 8 - so Running is the only stoppable status, and handing
            # the server a finished execution buys a server error instead of a clear message.
            $splatStartFailing = @{
                SqlInstance = $ssisInstance
                Folder      = $executionFolder
                Project     = $failProject
                Package     = $failPackage
            }
            $failing = Start-DbaSsisExecution @splatStartFailing
            $failedId = [long]$failing.ExecutionID
            $null = $startedExecutions.Add($failedId)
            $terminal = Wait-SsisExecutionTerminal -ExecutionId $failedId
            $terminal | Should -Not -Be 2

            $legStart = Get-SsisCatalogTime
            $splatStopFinished = @{
                SqlInstance     = $ssisInstance
                ExecutionId     = $failedId
                EnableException = $false
                WarningVariable = "finishedWarnings"
                WarningAction   = "SilentlyContinue"
                Confirm         = $false
            }
            $none = @(Stop-DbaSsisExecution @splatStopFinished)
            $none.Count | Should -Be 0
            ($finishedWarnings -join " ") | Should -BeLike "*not Running, so there is nothing to stop*"
            Get-SsisStopRequestCount -Since $legStart | Should -Be 0
        }

        It "Reports an execution id that does not exist" {
            $splatAbsent = @{
                SqlInstance     = $ssisInstance
                ExecutionId     = 999999999999
                EnableException = $false
                WarningVariable = "absentWarnings"
                WarningAction   = "SilentlyContinue"
                Confirm         = $false
            }
            $none = @(Stop-DbaSsisExecution @splatAbsent)
            $none.Count | Should -Be 0
            ($absentWarnings -join " ") | Should -BeLike "*does not exist on*"
        }
    }

    Context "Two records in one pipeline" {
        It "Stops the second piped execution as well as the first" {
            # Stopping streams per record, so what record 2 does is decided entirely on the second
            # record - record 1 alone proves none of it. This is also the composition the help
            # documents, piped from Get-DbaSsisExecution rather than hand-built.
            $firstId = Start-SsisRunningExecution
            $null = $startedExecutions.Add($firstId)
            $secondId = Start-SsisRunningExecution
            $null = $startedExecutions.Add($secondId)
            $legStart = Get-SsisCatalogTime

            $piped = @(Get-DbaSsisExecution -SqlInstance $ssisInstance -ExecutionId $firstId, $secondId)
            $piped.Count | Should -Be 2
            $firstExecution = $piped | Where-Object { [long]$PSItem.ExecutionID -eq $firstId }
            $secondExecution = $piped | Where-Object { [long]$PSItem.ExecutionID -eq $secondId }

            $stopped = @($firstExecution, $secondExecution | Stop-DbaSsisExecution -Confirm:$false)
            $stopped.Count | Should -Be 2
            @($stopped | ForEach-Object { [long]$PSItem.ExecutionID }) | Should -Contain $firstId
            @($stopped | ForEach-Object { [long]$PSItem.ExecutionID }) | Should -Contain $secondId
            Get-SsisStopRequestCount -Since $legStart | Should -Be 2

            (Wait-SsisExecutionTerminal -ExecutionId $firstId) | Should -Not -Be 7
            (Wait-SsisExecutionTerminal -ExecutionId $secondId) | Should -Not -Be 7
        }
    }

    Context "-InputObject" {
        It "Refuses an object that is not an execution" {
            $executionId = Start-SsisRunningExecution
            $null = $startedExecutions.Add($executionId)
            $legStart = Get-SsisCatalogTime

            $imposter = [PSCustomObject]@{
                SqlInstance = $ssisInstance
                ExecutionID = $executionId
            }
            $splatImposter = @{
                EnableException = $false
                WarningVariable = "imposterWarnings"
                WarningAction   = "SilentlyContinue"
                Confirm         = $false
            }
            $refused = @($imposter | Stop-DbaSsisExecution @splatImposter)
            $refused.Count | Should -Be 0
            ($imposterWarnings -join " ") | Should -BeLike "*not a dbatools.SsisExecution*"
            # The imposter carries a real, running execution id, so a type check that had been lost
            # would have stopped it - which is what makes this leg a positive control rather than a
            # message assertion.
            Get-SsisStopRequestCount -Since $legStart | Should -Be 0
            Get-SsisExecutionStatus -ExecutionId $executionId | Should -Be 2

            Stop-SsisFixtureExecution -ExecutionId $executionId
        }
    }

    Context "An instance with no SSIS catalog" {
        It "Warns and returns nothing" {
            $splatNoCatalog = @{
                SqlInstance     = $TestConfig.InstanceSingle
                ExecutionId     = 1
                EnableException = $false
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                Confirm         = $false
            }
            $none = @(Stop-DbaSsisExecution @splatNoCatalog)
            $none.Count | Should -Be 0
            ($warn -join " ") | Should -BeLike "*No SSIS catalog (SSISDB) found*"
        }

        It "Throws on the same instance under -EnableException" {
            $splatNoCatalogThrow = @{
                SqlInstance     = $TestConfig.InstanceSingle
                ExecutionId     = 1
                EnableException = $true
                Confirm         = $false
            }
            { Stop-DbaSsisExecution @splatNoCatalogThrow } | Should -Throw "*No SSIS catalog (SSISDB) found*"
        }
    }
}
