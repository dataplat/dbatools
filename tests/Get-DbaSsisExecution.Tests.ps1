#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaSsisExecution",
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
                "Since",
                "Status",
                "Project",
                "Folder",
                "Environment",
                "ExecutionId",
                "Type",
                "IncludeOperations",
                "IncludeMessages",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Back-compatibility with the command it supersedes" {
        It "Resolves Get-DbaSsisExecutionHistory to this command" {
            $superseded = Get-Command -Name Get-DbaSsisExecutionHistory
            $superseded.CommandType | Should -Be "Alias"
            $superseded.ResolvedCommand.Name | Should -Be "Get-DbaSsisExecution"
        }

        It "Keeps every superseded parameter in its original position" {
            $expectedPositions = @{
                SqlInstance   = 0
                SqlCredential = 1
                Since         = 2
                Status        = 3
                Project       = 4
                Folder        = 5
                Environment   = 6
            }
            $parameters = (Get-Command $CommandName).Parameters
            foreach ($name in $expectedPositions.Keys) {
                $position = ($parameters[$name].Attributes | Where-Object { $PSItem -is [System.Management.Automation.ParameterAttribute] }).Position
                $position | Should -Be $expectedPositions[$name] -Because "scripts written against Get-DbaSsisExecutionHistory bind $name positionally"
            }
        }

        It "Keeps the superseded status vocabulary" {
            $validation = (Get-Command $CommandName).Parameters["Status"].Attributes | Where-Object { $PSItem -is [System.Management.Automation.ValidateSetAttribute] }
            $validation.ValidValues | Should -Contain "Succeeded"
            $validation.ValidValues | Should -Contain "Cancelled"
            $validation.ValidValues.Count | Should -Be 9
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # The lab carries one deployed characterization project (folder dbatoolsci_charfolder, project
    # dbatoolsci_charproject, package dbatoolsci_charpackage.dtsx) that has been executed once to
    # Succeeded with LOGGING_LEVEL 1. A second execution is created here but never started, which
    # gives a deterministic second record with a different status and no log messages - the shape a
    # cross-record leak between attached rows would break. The catalog stored procedures refuse SQL
    # Server Authentication, so this only works from an integrated-auth session.
    BeforeAll {
        $ssisInstance = $TestConfig.InstanceSsis
        $charFolder = "dbatoolsci_charfolder"
        $charProject = "dbatoolsci_charproject"
        $charPackage = "dbatoolsci_charpackage.dtsx"

        $splatCreate = @{
            SqlInstance     = $ssisInstance
            Database        = "SSISDB"
            EnableException = $true
            Query           = "DECLARE @id BIGINT; EXEC [catalog].[create_execution] @folder_name = N'$charFolder', @project_name = N'$charProject', @package_name = N'$charPackage', @use32bitruntime = 0, @reference_id = NULL, @execution_id = @id OUTPUT; SELECT CreatedExecutionId = @id;"
        }
        $createdExecutionId = (Invoke-DbaQuery @splatCreate).CreatedExecutionId

        $allExecutions = @(Get-DbaSsisExecution -SqlInstance $ssisInstance)
        $ranExecution = $allExecutions | Where-Object { $PSItem.FolderName -eq $charFolder -and $PSItem.StatusCode -eq "Succeeded" } | Select-Object -First 1
    }

    Context "Reading the catalog" {
        It "Returns the executions recorded in the catalog" {
            $allExecutions.Count | Should -BeGreaterOrEqual 2
            $ranExecution | Should -Not -BeNullOrEmpty
        }

        It "Emits the property shape the superseded command reported" {
            $ranExecution.ExecutionID | Should -BeOfType [long]
            $ranExecution.FolderName | Should -Be $charFolder
            $ranExecution.ProjectName | Should -Be $charProject
            $ranExecution.PackageName | Should -Be $charPackage
            $ranExecution.Environment | Should -Be ""
            $ranExecution.StatusCode | Should -Be "Succeeded"
            $ranExecution.StartTime | Should -BeOfType [Dataplat.Dbatools.Utility.DbaDateTime]
            $ranExecution.EndTime | Should -BeOfType [Dataplat.Dbatools.Utility.DbaDateTime]
            $ranExecution.ElapsedMinutes | Should -BeOfType [int]
            $ranExecution.LoggingLevel | Should -Be 1
        }

        It "Reports the machine and caller the catalog recorded" {
            $ranExecution.ServerName | Should -Not -BeNullOrEmpty
            $ranExecution.CallerName | Should -Not -BeNullOrEmpty
            $ranExecution.CreatedTime | Should -BeOfType [Dataplat.Dbatools.Utility.DbaDateTime]
        }
    }

    Context "Filtering" {
        It "Matches on folder, project and status together" {
            $splatFilter = @{
                SqlInstance = $ssisInstance
                Folder      = $charFolder
                Project     = $charProject
                Status      = "Succeeded"
            }
            $matched = @(Get-DbaSsisExecution @splatFilter)
            $matched.Count | Should -BeGreaterOrEqual 1
            ($matched.StatusCode | Sort-Object -Unique) | Should -Be "Succeeded"
        }

        It "Separates the created execution from the one that ran" {
            $created = @(Get-DbaSsisExecution -SqlInstance $ssisInstance -Status Created)
            $created.ExecutionID | Should -Contain $createdExecutionId
            $succeeded = @(Get-DbaSsisExecution -SqlInstance $ssisInstance -Status Succeeded)
            $succeeded.ExecutionID | Should -Not -Contain $createdExecutionId
        }

        It "Excludes non-matching status and future Since values" {
            $failedOnly = @(Get-DbaSsisExecution -SqlInstance $ssisInstance -Status Failed | Where-Object FolderName -eq $charFolder)
            $failedOnly.Count | Should -Be 0
            $futureOnly = @(Get-DbaSsisExecution -SqlInstance $ssisInstance -Since (Get-Date).AddDays(1))
            $futureOnly.Count | Should -Be 0
        }

        It "Selects a single execution by id" {
            $single = @(Get-DbaSsisExecution -SqlInstance $ssisInstance -ExecutionId $createdExecutionId)
            $single.Count | Should -Be 1
            $single[0].ExecutionID | Should -Be $createdExecutionId
        }

        It "Returns nothing for an execution id the catalog does not hold" {
            $absent = @(Get-DbaSsisExecution -SqlInstance $ssisInstance -ExecutionId 9223372036854775807)
            $absent.Count | Should -Be 0
        }
    }

    Context "-Folder and -Project are exact name lists" {
        It "Does not return executions from a folder whose name merely starts with the requested one" {
            $prefix = @(Get-DbaSsisExecution -SqlInstance $ssisInstance -Folder "dbatoolsci_char")
            $prefix.Count | Should -Be 0
        }

        It "Treats a LIKE metacharacter in -Folder as a literal, returning nothing" {
            $metacharacter = @(Get-DbaSsisExecution -SqlInstance $ssisInstance -Folder "dbatoolsci_charfolde_")
            $metacharacter.Count | Should -Be 0
        }

        It "Treats a wildcard in -Project as a literal, returning nothing" {
            $wildcard = @(Get-DbaSsisExecution -SqlInstance $ssisInstance -Project "dbatoolsci_charproject*")
            $wildcard.Count | Should -Be 0
        }
    }

    Context "-IncludeOperations" {
        It "Leaves the operation rows off by default" {
            $plain = @(Get-DbaSsisExecution -SqlInstance $ssisInstance -Folder $charFolder)
            $plain.Count | Should -BeGreaterOrEqual 2
            $plain[0].PSObject.Properties.Name | Should -Not -Contain "Operations"
        }

        It "Attaches each execution its own operation row and nobody else's" {
            $withOperations = @(Get-DbaSsisExecution -SqlInstance $ssisInstance -Folder $charFolder -IncludeOperations)
            $withOperations.Count | Should -BeGreaterOrEqual 2
            foreach ($execution in $withOperations) {
                $execution.Operations.Count | Should -Be 1
                $execution.Operations[0].OperationId | Should -Be $execution.ExecutionID
            }
            ($withOperations.Operations.OperationId | Sort-Object -Unique).Count | Should -Be $withOperations.Count
        }

        It "Narrows the attached operations with -Type" {
            $kept = @(Get-DbaSsisExecution -SqlInstance $ssisInstance -ExecutionId $createdExecutionId -IncludeOperations -Type 200)
            $kept[0].Operations.Count | Should -Be 1
            $kept[0].Operations[0].OperationType | Should -Be 200
            $dropped = @(Get-DbaSsisExecution -SqlInstance $ssisInstance -ExecutionId $createdExecutionId -IncludeOperations -Type 101)
            $dropped.Count | Should -Be 1
            $dropped[0].Operations.Count | Should -Be 0
        }

        It "Refuses -Type without -IncludeOperations rather than ignoring it" {
            $splatOrphan = @{
                SqlInstance     = $ssisInstance
                Type            = 200
                WarningAction   = "SilentlyContinue"
                WarningVariable = "orphanWarning"
            }
            $null = Get-DbaSsisExecution @splatOrphan
            $orphanWarning | Should -Match "IncludeOperations"
            { Get-DbaSsisExecution -SqlInstance $ssisInstance -Type 200 -EnableException } | Should -Throw
        }
    }

    Context "-IncludeMessages" {
        It "Leaves the log messages off by default" {
            $plain = @(Get-DbaSsisExecution -SqlInstance $ssisInstance -ExecutionId $ranExecution.ExecutionID)
            $plain[0].PSObject.Properties.Name | Should -Not -Contain "Messages"
        }

        It "Gives each execution only the messages logged against it" {
            $withMessages = @(Get-DbaSsisExecution -SqlInstance $ssisInstance -Folder $charFolder -IncludeMessages)
            $withMessages.Count | Should -BeGreaterOrEqual 2
            foreach ($execution in $withMessages) {
                foreach ($message in $execution.Messages) {
                    $message.OperationId | Should -Be $execution.ExecutionID
                }
            }
            $ran = $withMessages | Where-Object ExecutionID -eq $ranExecution.ExecutionID
            $ran.Messages.Count | Should -BeGreaterOrEqual 1
            $ran.Messages[0].Message | Should -Not -BeNullOrEmpty
            $ran.Messages[0].MessageTime | Should -BeOfType [Dataplat.Dbatools.Utility.DbaDateTime]
            $created = $withMessages | Where-Object ExecutionID -eq $createdExecutionId
            $created.Messages.Count | Should -Be 0
        }
    }

    Context "The alias still binds the way scripts wrote it" {
        It "Accepts the superseded command's parameters positionally" {
            $positional = @(Get-DbaSsisExecutionHistory $ssisInstance $null ([datetime]"2000-01-01") "Succeeded" $charProject $charFolder)
            $positional.Count | Should -BeGreaterOrEqual 1
            $positional[0].FolderName | Should -Be $charFolder
            $positional[0].ProjectName | Should -Be $charProject
            $positional[0].StatusCode | Should -Be "Succeeded"
        }
    }

    Context "More than one instance down the pipeline" {
        # The SQL text and its parameter set are composed once in the begin block and reused for
        # every piped instance, so the second record is the one that would show a carry.
        It "Applies the same filters to the second piped instance as the first" {
            $single = @(Get-DbaSsisExecution -SqlInstance $ssisInstance -Folder $charFolder -Status Succeeded)
            $single.Count | Should -BeGreaterOrEqual 1
            $piped = @(@($ssisInstance, $ssisInstance) | Get-DbaSsisExecution -Folder $charFolder -Status Succeeded)
            $piped.Count | Should -Be ($single.Count * 2)
            ($piped.StatusCode | Sort-Object -Unique) | Should -Be "Succeeded"
            ($piped.FolderName | Sort-Object -Unique) | Should -Be $charFolder
            $piped[$single.Count].ExecutionID | Should -Be $single[0].ExecutionID
        }

        It "Keeps reading after a piped instance that has no catalog" {
            $splatMixed = @{
                Folder          = $charFolder
                WarningAction   = "SilentlyContinue"
                WarningVariable = "mixedWarning"
            }
            $mixed = @(@($TestConfig.InstanceSingle, $ssisInstance) | Get-DbaSsisExecution @splatMixed)
            $mixed.Count | Should -BeGreaterOrEqual 2
            ($mixed.FolderName | Sort-Object -Unique) | Should -Be $charFolder
            $mixedWarning | Should -Match "SSISDB"
        }
    }

    Context "Output decoration" {
        It "Carries the instance property triple" {
            $ranExecution.ComputerName | Should -Not -BeNullOrEmpty
            $ranExecution.InstanceName | Should -Not -BeNullOrEmpty
            $ranExecution.SqlInstance | Should -Not -BeNullOrEmpty
        }

        It "Carries the dbatools.SsisExecution type name" {
            $ranExecution.PSObject.TypeNames | Should -Contain "dbatools.SsisExecution"
        }

        It "Keeps ProjectLsn on the object but off the default view" {
            $ranExecution.PSObject.Properties.Name | Should -Contain "ProjectLsn"
            $defaultView = $ranExecution.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $defaultView | Should -Contain "ElapsedMinutes"
            $defaultView | Should -Not -Contain "ProjectLsn"
        }
    }

    Context "An instance with no SSIS catalog" {
        It "Warns and returns nothing" {
            $splatNoCatalog = @{
                SqlInstance     = $TestConfig.InstanceSingle
                WarningAction   = "SilentlyContinue"
                WarningVariable = "catalogWarning"
            }
            $nothing = @(Get-DbaSsisExecution @splatNoCatalog)
            $nothing.Count | Should -Be 0
            $catalogWarning | Should -Match "SSISDB"
        }

        It "Throws under -EnableException" {
            { Get-DbaSsisExecution -SqlInstance $TestConfig.InstanceSingle -EnableException } | Should -Throw
        }
    }
}
